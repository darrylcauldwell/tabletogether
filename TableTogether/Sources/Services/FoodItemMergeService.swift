import Foundation
import CoreData

// MARK: - FoodItemMergeService
//
// Merges one FoodItem master into another, preserving the merged-away
// record's display name and aliases on the canonical record. Used by the
// FoodItem Library merge action (#59 Phase 8).
//
// Mirrors `IngredientMergeService` in shape but the FK list is shorter:
// FoodItem is only referenced by `MealSlotComponent.foodItem`. The class
// is intentionally separate (rather than generic over Core Data entities)
// because the FK lists differ across entity types and a generic abstraction
// would force a lot of conditional rendering. Two short concrete services
// are clearer than one tangled generic.
//
// Recovery model: same as IngredientMergeService — destructive, no rollback.
// Recovery is "wipe local + re-import from source files".

@MainActor
final class FoodItemMergeService {

    enum MergeError: LocalizedError {
        case sameRecord
        case missingContext
        case mismatchedHousehold
        case saveFailed(String)

        var errorDescription: String? {
            switch self {
            case .sameRecord:
                return "Cannot merge a food item into itself."
            case .missingContext:
                return "Food item is not attached to a managed object context."
            case .mismatchedHousehold:
                return "Cannot merge food items across different households."
            case .saveFailed(let detail):
                return "Save failed: \(detail)"
            }
        }
    }

    /// Summary of what a merge will do, used by the confirmation UI.
    struct MergePreview {
        let sourceName: String
        let canonicalName: String
        let aliasesToTransfer: [String]
        let mealSlotComponentCount: Int

        var totalReassignments: Int { mealSlotComponentCount }
    }

    /// Compute a preview without modifying any state.
    func preview(source: FoodItem, into canonical: FoodItem) -> MergePreview {
        let normalisedCanonicalName = canonical.normalizedName
        let canonicalAliases = Set(canonical.userAliasesList)

        var aliasesToTransfer: [String] = []
        let sourceNormalisedName = source.normalizedName
        if sourceNormalisedName != normalisedCanonicalName,
           !canonicalAliases.contains(sourceNormalisedName) {
            aliasesToTransfer.append(sourceNormalisedName)
        }
        for alias in source.userAliasesList {
            if alias != normalisedCanonicalName,
               !canonicalAliases.contains(alias),
               !aliasesToTransfer.contains(alias) {
                aliasesToTransfer.append(alias)
            }
        }

        return MergePreview(
            sourceName: source.displayName,
            canonicalName: canonical.displayName,
            aliasesToTransfer: aliasesToTransfer,
            mealSlotComponentCount: mealSlotComponents(of: source).count
        )
    }

    /// Execute the merge. After this returns successfully, `source` is no
    /// longer in the context and `canonical` has absorbed everything.
    @discardableResult
    func merge(source: FoodItem, into canonical: FoodItem) throws -> MergePreview {
        guard source !== canonical else { throw MergeError.sameRecord }
        guard let context = canonical.managedObjectContext else { throw MergeError.missingContext }
        guard source.household == canonical.household else { throw MergeError.mismatchedHousehold }

        let snapshot = preview(source: source, into: canonical)

        // 1. Transfer name + aliases.
        canonical.addAlias(source.displayName)
        for alias in source.userAliasesList {
            canonical.addAlias(alias)
        }

        // 2. Reassign FKs.
        for component in mealSlotComponents(of: source) {
            component.foodItem = canonical
        }

        // 3. Delete source.
        context.delete(source)

        // 4. Save.
        do {
            try context.save()
        } catch {
            throw MergeError.saveFailed(error.localizedDescription)
        }

        AppLogger.swiftData.info(
            "Merged FoodItem '\(snapshot.sourceName)' into '\(snapshot.canonicalName)' — \(snapshot.totalReassignments) FKs reassigned, \(snapshot.aliasesToTransfer.count) aliases added"
        )

        return snapshot
    }

    // MARK: - Helpers

    private func mealSlotComponents(of foodItem: FoodItem) -> [MealSlotComponent] {
        (foodItem.mealSlotComponents?.allObjects as? [MealSlotComponent]) ?? []
    }
}
