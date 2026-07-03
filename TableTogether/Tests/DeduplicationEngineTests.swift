import Testing
import CoreData
import Foundation
@testable import TableTogetherLib

/// Tests the dedup merge core with injected CKRecord names — no CloudKit container.
/// Covers the three 2026-07-02 live failures: cross-device winner thrash, cascade
/// slot annihilation, and lost edits (docs/SYNC_DEDUP_REDESIGN.md, Change 1e).
@MainActor
struct DeduplicationEngineTests {

    private func makeContext() -> NSManagedObjectContext {
        PersistenceController(inMemory: true).viewContext
    }

    /// Builds the record-info map the caller normally derives from
    /// `container.recordID(for:)`. Objects must have permanent IDs (save first).
    private func recordInfo(
        _ entries: [(NSManagedObject, String)],
        zone: String = "owner|com.apple.coredata.cloudkit.zone"
    ) -> [NSManagedObjectID: DeduplicationEngine.RecordInfo] {
        Dictionary(uniqueKeysWithValues: entries.map { object, name in
            (object.objectID, DeduplicationEngine.RecordInfo(recordName: name, zoneKey: zone))
        })
    }

    // MARK: - Winner selection

    @Test("Winner is device-independent: smallest record name survives regardless of candidate order")
    func winnerIsOrderIndependent() throws {
        for reversed in [false, true] {
            let context = makeContext()
            let week = Date()
            let planID = WeekPlan.deterministicID(for: week)
            let first = WeekPlan(context: context, id: planID, weekStartDate: week)
            let second = WeekPlan(context: context, id: planID, weekStartDate: week)
            try context.save()

            let info = recordInfo([(first, "record-b"), (second, "record-a")])
            let candidates = reversed ? [second, first] : [first, second]

            let outcome = DeduplicationEngine.deduplicate(candidates: candidates, recordInfo: info, in: context)

            #expect(outcome == .merged(deletedCount: 1))
            #expect(first.isDeleted)
            #expect(!second.isDeleted)
        }
    }

    @Test("A candidate without a record name defers the group and deletes nothing")
    func missingRecordNameDefers() throws {
        let context = makeContext()
        let week = Date()
        let planID = WeekPlan.deterministicID(for: week)
        let exported = WeekPlan(context: context, id: planID, weekStartDate: week)
        let unexported = WeekPlan(context: context, id: planID, weekStartDate: week)
        try context.save()

        // Only the exported copy has a record name — mimics import-before-export.
        let info = recordInfo([(exported, "record-a")])

        let outcome = DeduplicationEngine.deduplicate(candidates: [exported, unexported], recordInfo: info, in: context)

        #expect(outcome == .deferred)
        #expect(!exported.isDeleted)
        #expect(!unexported.isDeleted)
    }

    @Test("Same-id records in different zones are not duplicates")
    func crossZoneRecordsUntouched() throws {
        let context = makeContext()
        let privateHousehold = Household(context: context)
        privateHousehold.id = Household.defaultID
        privateHousehold.name = "Mine"
        privateHousehold.createdAt = Date()
        let sharedZoneHousehold = Household(context: context)
        sharedZoneHousehold.id = Household.defaultID
        sharedZoneHousehold.name = "Share zone copy"
        sharedZoneHousehold.createdAt = Date()
        try context.save()

        var info = recordInfo([(privateHousehold, "record-a")], zone: "owner|default")
        info.merge(recordInfo([(sharedZoneHousehold, "record-b")], zone: "owner|share.zone")) { current, _ in current }

        let outcome = DeduplicationEngine.deduplicate(
            candidates: [privateHousehold, sharedZoneHousehold], recordInfo: info, in: context)

        #expect(outcome == .noDuplicates)
        #expect(!privateHousehold.isDeleted)
        #expect(!sharedZoneHousehold.isDeleted)
    }

    // MARK: - Re-pointing (cascade annihilation)

    @Test("WeekPlan dedup re-points the loser's slots — no cascade annihilation")
    func weekPlanDedupPreservesSlots() throws {
        let context = makeContext()
        let week = Date()
        let planID = WeekPlan.deterministicID(for: week)
        let winner = WeekPlan(context: context, id: planID, weekStartDate: week)
        let loser = WeekPlan(context: context, id: planID, weekStartDate: week)

        for day in [DayOfWeek.monday, .tuesday] {
            let slot = MealSlot(context: context, dayOfWeek: day, mealType: .dinner)
            slot.weekPlan = winner
        }
        for day in [DayOfWeek.wednesday, .thursday, .friday] {
            let slot = MealSlot(context: context, dayOfWeek: day, mealType: .dinner)
            slot.weekPlan = loser
        }
        try context.save()

        let info = recordInfo([(winner, "record-a"), (loser, "record-b")])
        let outcome = DeduplicationEngine.deduplicate(candidates: [winner, loser], recordInfo: info, in: context)
        try context.save()

        #expect(outcome == .merged(deletedCount: 1))
        #expect(winner.slotsArray.count == 5)

        let slotCount = try context.count(for: NSFetchRequest<MealSlot>(entityName: "MealSlot"))
        #expect(slotCount == 5)
    }

    @Test("Structural dedup re-points a loser household's children to the winner")
    func householdDedupRepointsChildren() throws {
        let context = makeContext()
        let winner = Household(context: context, name: "Winner")
        winner.id = Household.defaultID
        let loser = Household(context: context, name: "Loser")
        loser.id = Household.defaultID
        let recipe = Recipe(context: context, title: "Shepherd's Pie")
        recipe.household = loser
        try context.save()

        let info = recordInfo([(winner, "record-a"), (loser, "record-b")])
        let outcome = DeduplicationEngine.deduplicate(candidates: [winner, loser], recordInfo: info, in: context)
        try context.save()

        #expect(outcome == .merged(deletedCount: 1))
        #expect(!recipe.isDeleted)
        #expect(recipe.household === winner)
        // Structural entities keep the winner's attributes — no LWW merge.
        #expect(winner.name == "Winner")
    }

    // MARK: - Last-write-wins merge (lost edits)

    @Test("The newest copy's edit survives even when it loses winner selection")
    func newestEditSurvivesOnWinner() throws {
        let context = makeContext()
        let week = Date()
        let slotID = MealSlot.deterministicID(weekStartDate: week, dayOfWeek: .monday, mealType: .dinner)
        let older = Date(timeIntervalSinceNow: -3600)
        let newer = Date()

        let winner = MealSlot(context: context, id: slotID, dayOfWeek: .monday, mealType: .dinner)
        winner.modifiedAt = older
        let loser = MealSlot(context: context, id: slotID, dayOfWeek: .monday, mealType: .dinner, customMealName: "Chips")
        loser.modifiedAt = newer
        try context.save()

        let info = recordInfo([(winner, "record-a"), (loser, "record-b")])
        let outcome = DeduplicationEngine.deduplicate(candidates: [winner, loser], recordInfo: info, in: context)
        try context.save()

        #expect(outcome == .merged(deletedCount: 1))
        #expect(!winner.isDeleted)
        #expect(winner.customMealName == "Chips")
        #expect(winner.modifiedAt == newer)
        #expect(winner.id == slotID)
    }

    @Test("Winner keeps its own newer state when it is also the freshest copy")
    func winnerKeepsNewerState() throws {
        let context = makeContext()
        let week = Date()
        let slotID = MealSlot.deterministicID(weekStartDate: week, dayOfWeek: .monday, mealType: .dinner)

        let winner = MealSlot(context: context, id: slotID, dayOfWeek: .monday, mealType: .dinner, customMealName: "Curry")
        winner.modifiedAt = Date()
        let loser = MealSlot(context: context, id: slotID, dayOfWeek: .monday, mealType: .dinner, customMealName: "Chips")
        loser.modifiedAt = Date(timeIntervalSinceNow: -3600)
        try context.save()

        let info = recordInfo([(winner, "record-a"), (loser, "record-b")])
        _ = DeduplicationEngine.deduplicate(candidates: [winner, loser], recordInfo: info, in: context)
        try context.save()

        #expect(winner.customMealName == "Curry")
    }

    @Test("Adoption re-points the freshest copy's components before its slot is deleted")
    func adoptionRepointsComponentsBeforeDelete() throws {
        let context = makeContext()
        let week = Date()
        let slotID = MealSlot.deterministicID(weekStartDate: week, dayOfWeek: .monday, mealType: .dinner)
        let recipeOld = Recipe(context: context, title: "Old Meal")
        let recipeNew = Recipe(context: context, title: "New Meal")

        let winner = MealSlot(context: context, id: slotID, dayOfWeek: .monday, mealType: .dinner)
        winner.modifiedAt = Date(timeIntervalSinceNow: -3600)
        let staleComponent = MealSlotComponent(context: context, slot: winner, recipe: recipeOld)

        let loser = MealSlot(context: context, id: slotID, dayOfWeek: .monday, mealType: .dinner)
        loser.modifiedAt = Date()
        let freshComponent = MealSlotComponent(context: context, slot: loser, recipe: recipeNew)
        try context.save()

        let info = recordInfo([(winner, "record-a"), (loser, "record-b")])
        let outcome = DeduplicationEngine.deduplicate(candidates: [winner, loser], recordInfo: info, in: context)

        // The winner's replaced cascade child is deleted, not orphaned.
        // (isDeleted is only true while the deletion is pending — check pre-save.)
        #expect(staleComponent.isDeleted)
        try context.save()

        #expect(outcome == .merged(deletedCount: 1))
        #expect(!freshComponent.isDeleted)
        #expect(freshComponent.slot === winner)

        let componentCount = try context.count(for: NSFetchRequest<MealSlotComponent>(entityName: "MealSlotComponent"))
        #expect(componentCount == 1)
    }

    @Test("Surviving record spans every copy: earliest createdAt, latest modifiedAt")
    func timestampsNormalizeAcrossCopies() throws {
        let context = makeContext()
        let week = Date()
        let slotID = MealSlot.deterministicID(weekStartDate: week, dayOfWeek: .monday, mealType: .dinner)
        let earliest = Date(timeIntervalSinceNow: -7200)
        let latest = Date()

        let winner = MealSlot(context: context, id: slotID, dayOfWeek: .monday, mealType: .dinner)
        winner.createdAt = Date(timeIntervalSinceNow: -3600)
        winner.modifiedAt = latest
        let loser = MealSlot(context: context, id: slotID, dayOfWeek: .monday, mealType: .dinner)
        loser.createdAt = earliest
        loser.modifiedAt = Date(timeIntervalSinceNow: -3600)
        try context.save()

        let info = recordInfo([(winner, "record-a"), (loser, "record-b")])
        _ = DeduplicationEngine.deduplicate(candidates: [winner, loser], recordInfo: info, in: context)
        try context.save()

        #expect(winner.createdAt == earliest)
        #expect(winner.modifiedAt == latest)
    }

    @Test("Single candidate is a no-op")
    func singleCandidateNoOp() throws {
        let context = makeContext()
        let plan = WeekPlan(context: context, weekStartDate: Date())
        try context.save()

        let info = recordInfo([(plan, "record-a")])
        let outcome = DeduplicationEngine.deduplicate(candidates: [plan], recordInfo: info, in: context)

        #expect(outcome == .noDuplicates)
        #expect(!plan.isDeleted)
    }
}
