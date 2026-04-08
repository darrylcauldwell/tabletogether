import Foundation
import CoreData

// MARK: - IngredientMergeService
//
// Merges one Ingredient master into another, preserving the merged-away
// record's name and aliases on the canonical record. Used by the
// Ingredient Library merge action (#59 Phase 8).
//
// **Operation (single Core Data transaction):**
// 1. Append `source.name` to `canonical.userAliases` (deduped via addAlias)
// 2. Append every element of `source.userAliases` to `canonical.userAliases`
// 3. Walk every incoming foreign key on `source` and reassign to `canonical`:
//    - RecipeIngredient.ingredient
//    - MealSlotComponent.ingredient
//    - GroceryItem.ingredient
// 4. Delete `source`
// 5. Save the context
//
// **Recovery model:** per `feedback_source_files_are_truth.md`, this is
// straightforwardly destructive. There is no transactional rollback within
// a session beyond what Core Data's save semantics provide, and no persistent
// undo stack. Recovery is "wipe local + re-import from JSON / Paprika source
// files". The confirmation dialog in the UI is the only safety net.

@MainActor
final class IngredientMergeService {

    enum MergeError: LocalizedError {
        case sameRecord
        case missingContext
        case mismatchedHousehold
        case saveFailed(String)

        var errorDescription: String? {
            switch self {
            case .sameRecord:
                return "Cannot merge an ingredient into itself."
            case .missingContext:
                return "Ingredient is not attached to a managed object context."
            case .mismatchedHousehold:
                return "Cannot merge ingredients across different households."
            case .saveFailed(let detail):
                return "Save failed: \(detail)"
            }
        }
    }

    /// Summary of what a merge will do, used by the confirmation UI.
    struct MergePreview {
        let sourceName: String
        let canonicalName: String
        let aliasesToTransfer: [String]   // Includes source.name + source.userAliases minus already-present
        let recipeIngredientCount: Int
        let mealSlotComponentCount: Int
        let groceryItemCount: Int

        var totalReassignments: Int {
            recipeIngredientCount + mealSlotComponentCount + groceryItemCount
        }
    }

    /// Compute a preview without modifying any state. The UI uses this to
    /// render the confirm dialog.
    func preview(source: Ingredient, into canonical: Ingredient) -> MergePreview {
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
            sourceName: source.name,
            canonicalName: canonical.name,
            aliasesToTransfer: aliasesToTransfer,
            recipeIngredientCount: source.recipeIngredientsArray.count,
            mealSlotComponentCount: mealSlotComponents(of: source).count,
            groceryItemCount: source.groceryItemsArray.count
        )
    }

    /// Execute the merge. After this returns successfully, `source` is no
    /// longer in the context and `canonical` has absorbed everything.
    @discardableResult
    func merge(source: Ingredient, into canonical: Ingredient) throws -> MergePreview {
        guard source !== canonical else { throw MergeError.sameRecord }
        guard let context = canonical.managedObjectContext else { throw MergeError.missingContext }
        guard source.household == canonical.household else { throw MergeError.mismatchedHousehold }

        // Compute preview before mutating so the returned value reflects the
        // intended operation, not the post-merge state.
        let snapshot = preview(source: source, into: canonical)

        // 1. Transfer name + aliases. Use addAlias so it normalises and dedupes.
        canonical.addAlias(source.name)
        for alias in source.userAliasesList {
            canonical.addAlias(alias)
        }

        // 2. Reassign every incoming FK to canonical.
        for recipeIngredient in source.recipeIngredientsArray {
            recipeIngredient.ingredient = canonical
        }
        for component in mealSlotComponents(of: source) {
            component.ingredient = canonical
        }
        for groceryItem in source.groceryItemsArray {
            groceryItem.ingredient = canonical
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
            "Merged Ingredient '\(snapshot.sourceName)' into '\(snapshot.canonicalName)' — \(snapshot.totalReassignments) FKs reassigned, \(snapshot.aliasesToTransfer.count) aliases added"
        )

        return snapshot
    }

    // MARK: - Helpers

    private func mealSlotComponents(of ingredient: Ingredient) -> [MealSlotComponent] {
        (ingredient.mealSlotComponents?.allObjects as? [MealSlotComponent]) ?? []
    }
}
