import CoreData

/// Collapses duplicate records that share a deterministic `id` attribute but exist
/// as distinct CKRecords because two devices created them concurrently
/// (NSPersistentCloudKitContainer identity is the CKRecord, not the `id` attribute).
///
/// Mirrors Apple's CoreDataCloudKitDemo dedup pattern with three corrections over
/// the previous engine (design: docs/SYNC_DEDUP_REDESIGN.md, Change 1):
///
/// 1. **Device-independent winner** — lexicographically smallest CKRecord name.
///    Every peer reaches the same result with no coordination, so devices can
///    never delete each other's keepers (the 2026-07-02 thrash loop).
/// 2. **Re-point before delete** — losers' children move to the winner before the
///    losers are deleted, so Cascade rules can't annihilate them (the 28→0 slot
///    loss).
/// 3. **Last-write-wins merge** — user-edited entities adopt attributes and owned
///    relationships from the copy with the newest `modifiedAt`, so an edit made on
///    a losing copy survives (the vanished "Chips" edit).
///
/// CKRecord names are injected by the caller, keeping this logic unit-testable
/// without a CloudKit container.
enum DeduplicationEngine {

    /// Entities eligible for dedup. Everything with a deterministic or seeded `id`,
    /// plus user-created entities where a sync echo could duplicate rows.
    /// MealSlotComponent is intentionally absent: random ids, owned via adoption.
    static let eligibleEntityNames: Set<String> = [
        "Household", "Recipe", "Ingredient", "User", "WeekPlan", "MealSlot",
        "MealArchetype", "GroceryItem", "FoodItem", "RecipeIngredient",
        "SuggestionMemory"
    ]

    /// How a duplicate group merges. Entities with a reliable `modifiedAt`
    /// (user-edited) take the freshest copy's state wholesale; structural/system
    /// entities keep the winner's state and only re-point children.
    struct Policy {
        /// Relationships replaced on the winner with the freshest copy's members
        /// (LWW — union would mix two versions of the same meal/recipe).
        let adoptFromFreshest: Set<String>
        /// Whether user attributes are copied from the freshest copy.
        let mergesAttributes: Bool

        static let structural = Policy(adoptFromFreshest: [], mergesAttributes: false)
    }

    static let policies: [String: Policy] = [
        "MealSlot": Policy(
            adoptFromFreshest: ["recipes", "components", "archetype", "modifiedBy", "assignedTo"],
            mergesAttributes: true
        ),
        "Recipe": Policy(adoptFromFreshest: ["recipeIngredients"], mergesAttributes: true),
        "Ingredient": Policy(adoptFromFreshest: [], mergesAttributes: true),
        "WeekPlan": Policy(adoptFromFreshest: [], mergesAttributes: true)
    ]

    /// CloudKit identity for a candidate, injected by the caller.
    struct RecordInfo {
        let recordName: String
        /// Owner + zone name. Same-id rows in different zones are NOT duplicates
        /// (a shared household puts a share zone inside the private database).
        let zoneKey: String

        init(recordName: String, zoneKey: String) {
            self.recordName = recordName
            self.zoneKey = zoneKey
        }
    }

    enum Outcome: Equatable {
        case noDuplicates
        /// A candidate has no CKRecord name yet (created locally, not yet
        /// exported). Winner selection would be device-DEPENDENT — any
        /// nil-vs-non-nil preference makes each device favor the other's copy
        /// and delete its own, killing both. Caller must retry after export.
        case deferred
        case merged(deletedCount: Int)
    }

    /// Merges duplicates among `candidates` (same entity, same `id`). Mutates the
    /// context but does not save; the caller owns the save.
    static func deduplicate(
        candidates: [NSManagedObject],
        recordInfo: [NSManagedObjectID: RecordInfo],
        in context: NSManagedObjectContext
    ) -> Outcome {
        guard candidates.count > 1 else { return .noDuplicates }
        guard candidates.allSatisfy({ recordInfo[$0.objectID] != nil }) else { return .deferred }

        let zoneGroups = Dictionary(grouping: candidates) { recordInfo[$0.objectID]!.zoneKey }

        var deleted = 0
        for group in zoneGroups.values where group.count > 1 {
            deleted += merge(group: group, recordInfo: recordInfo, in: context)
        }
        return deleted > 0 ? .merged(deletedCount: deleted) : .noDuplicates
    }

    // MARK: - Merge

    private static func merge(
        group: [NSManagedObject],
        recordInfo: [NSManagedObjectID: RecordInfo],
        in context: NSManagedObjectContext
    ) -> Int {
        let sorted = group.sorted {
            recordInfo[$0.objectID]!.recordName < recordInfo[$1.objectID]!.recordName
        }
        let winner = sorted[0]
        let losers = Array(sorted.dropFirst())
        let policy = policies[winner.entity.name ?? ""] ?? .structural

        if policy.mergesAttributes {
            let freshest = freshestCopy(in: group, recordInfo: recordInfo)
            if freshest !== winner {
                adoptAttributes(from: freshest, onto: winner)
                for name in policy.adoptFromFreshest {
                    adoptRelationship(name, from: freshest, onto: winner, in: context)
                }
            }
        }
        normalizeTimestamps(group: group, winner: winner)

        for loser in losers {
            for (name, relationship) in loser.entity.relationshipsByName {
                // Adopted relationships were taken from the freshest copy above;
                // stale losers' versions die with them (Cascade) or unlink (Nullify).
                guard !policy.adoptFromFreshest.contains(name) else { continue }
                if relationship.isToMany {
                    unionMembers(of: name, from: loser, onto: winner)
                } else if winner.value(forKey: name) == nil,
                          let value = loser.value(forKey: name) {
                    // Orphan-avoidance: fill a nil to-one (e.g. household) from a loser.
                    winner.setValue(value, forKey: name)
                }
            }
            context.delete(loser)
        }
        return losers.count
    }

    /// The copy with the newest `modifiedAt` (fallback `createdAt`), record-name
    /// tie-break so equal timestamps still resolve identically on every device.
    private static func freshestCopy(
        in group: [NSManagedObject],
        recordInfo: [NSManagedObjectID: RecordInfo]
    ) -> NSManagedObject {
        group.max { a, b in
            let dateA = lastModified(a)
            let dateB = lastModified(b)
            if dateA != dateB { return dateA < dateB }
            return recordInfo[a.objectID]!.recordName < recordInfo[b.objectID]!.recordName
        }!
    }

    private static func lastModified(_ object: NSManagedObject) -> Date {
        (object.value(forKey: "modifiedAt") as? Date)
            ?? (object.value(forKey: "createdAt") as? Date)
            ?? .distantPast
    }

    private static func adoptAttributes(from freshest: NSManagedObject, onto winner: NSManagedObject) {
        for name in winner.entity.attributesByName.keys
        where name != "id" && name != "createdAt" && name != "modifiedAt" {
            winner.setValue(freshest.value(forKey: name), forKey: name)
        }
    }

    /// Replaces the winner's relationship members with the freshest copy's. The
    /// freshest copy's children are re-pointed to the winner BEFORE any delete,
    /// so a Cascade rule on the freshest (if it is a loser) can't destroy them.
    /// The winner's replaced Cascade children are deleted explicitly — unlinking
    /// alone would leave them orphaned forever.
    private static func adoptRelationship(
        _ name: String,
        from freshest: NSManagedObject,
        onto winner: NSManagedObject,
        in context: NSManagedObjectContext
    ) {
        guard let relationship = winner.entity.relationshipsByName[name] else { return }
        guard relationship.isToMany else {
            winner.setValue(freshest.value(forKey: name), forKey: name)
            return
        }

        let newMembers = (freshest.value(forKey: name) as? NSSet) ?? NSSet()
        let winnerSet = winner.mutableSetValue(forKey: name)
        for member in winnerSet.allObjects where !newMembers.contains(member) {
            if relationship.deleteRule == .cascadeDeleteRule,
               let managed = member as? NSManagedObject {
                context.delete(managed)
            } else {
                winnerSet.remove(member)
            }
        }
        for member in newMembers.allObjects {
            winnerSet.add(member)
        }
    }

    /// Moves a loser's to-many members onto the winner. Core Data maintains
    /// inverses, so a child's to-one parent re-points automatically.
    private static func unionMembers(of name: String, from loser: NSManagedObject, onto winner: NSManagedObject) {
        guard let members = (loser.value(forKey: name) as? NSSet)?.allObjects,
              !members.isEmpty else { return }
        let winnerSet = winner.mutableSetValue(forKey: name)
        for member in members {
            winnerSet.add(member)
        }
    }

    /// The surviving record represents every copy: earliest creation, latest edit.
    private static func normalizeTimestamps(group: [NSManagedObject], winner: NSManagedObject) {
        let attributes = winner.entity.attributesByName
        if attributes["modifiedAt"] != nil,
           let newest = group.compactMap({ $0.value(forKey: "modifiedAt") as? Date }).max() {
            winner.setValue(newest, forKey: "modifiedAt")
        }
        if attributes["createdAt"] != nil,
           let earliest = group.compactMap({ $0.value(forKey: "createdAt") as? Date }).min() {
            winner.setValue(earliest, forKey: "createdAt")
        }
    }
}
