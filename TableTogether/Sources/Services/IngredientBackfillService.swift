import Foundation
import CoreData

/// Result of an `IngredientBackfillService` run.
struct IngredientBackfillResult {
    /// Total `RecipeIngredient` rows examined.
    let processed: Int
    /// Rows whose `.ingredient` foreign key was nil and is now linked.
    let linked: Int
    /// Rows whose `.ingredient` foreign key was already set (skipped — idempotent).
    let alreadyLinked: Int
    /// Rows skipped because their resolved name was empty (rare).
    let skippedEmptyName: Int
    /// Number of `Ingredient` master records created during the backfill.
    let mastersCreated: Int
}

/// Backfills the `RecipeIngredient.ingredient` foreign key for existing rows
/// that pre-date the resolver integration (#59 Phase 4). Idempotent — re-running
/// only touches rows that still have a nil FK.
///
/// The backfill is **manual**, not automatic. It's triggered from
/// Settings → "Reorganise Ingredient Library" so the user can decide when to
/// run it and watch the result. Auto-run on launch was rejected per user
/// preference for explicit operations on data-shape changes.
///
/// Implementation: a single fetch of all `RecipeIngredient` rows in the
/// household, then a per-row resolve via `RecipeIngredientResolver` (which
/// shares its own prewarm cache). For the user's current ~5000-row library
/// this completes in well under a second.
///
/// **Per #59 Phase 5.**
@MainActor
@Observable
final class IngredientBackfillService {

    var isRunning = false
    var progress: String = ""
    var result: IngredientBackfillResult?
    var errorMessage: String?

    /// Runs the backfill for the given household. Safe to call multiple times.
    /// Updates `progress` as it works so a UI can render a status string.
    @discardableResult
    func run(context: NSManagedObjectContext, household: Household?) -> IngredientBackfillResult {
        isRunning = true
        progress = "Loading ingredients..."
        errorMessage = nil
        result = nil

        defer {
            isRunning = false
        }

        // Single fetch — household scoping via the recipe→household relationship.
        let request = NSFetchRequest<RecipeIngredient>(entityName: "RecipeIngredient")
        if let household {
            request.predicate = NSPredicate(format: "recipe.household == %@", household)
        }

        let allRows: [RecipeIngredient]
        do {
            allRows = try context.fetch(request)
        } catch {
            AppLogger.swiftData.error("IngredientBackfillService fetch failed: \(error.localizedDescription)")
            errorMessage = "Could not load ingredients: \(error.localizedDescription)"
            let empty = IngredientBackfillResult(processed: 0, linked: 0, alreadyLinked: 0, skippedEmptyName: 0, mastersCreated: 0)
            result = empty
            return empty
        }

        let total = allRows.count
        progress = "Resolving \(total) ingredient rows..."

        let resolver = RecipeIngredientResolver(context: context, household: household)
        let mastersBefore = resolver.cacheCount

        var linked = 0
        var alreadyLinked = 0
        var skippedEmptyName = 0

        for (index, row) in allRows.enumerated() {
            // Idempotent: rows already linked are left alone
            if row.ingredient != nil {
                alreadyLinked += 1
                continue
            }

            // displayName falls back to customName when no ingredient is linked,
            // which is exactly the path we want for unlinked rows.
            let name = row.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else {
                skippedEmptyName += 1
                continue
            }

            if let master = resolver.resolve(name) {
                row.ingredient = master
                linked += 1
            } else {
                skippedEmptyName += 1
            }

            // Coarse progress updates (every ~5%) to avoid thrashing the UI
            if total > 0 && index % max(total / 20, 1) == 0 {
                progress = "Linking \(index + 1) of \(total)..."
            }
        }

        // Save once at the end. The Core Data context will batch the writes.
        do {
            try context.save()
        } catch {
            AppLogger.swiftData.error("IngredientBackfillService save failed: \(error.localizedDescription)")
            errorMessage = "Could not save: \(error.localizedDescription)"
        }

        let mastersCreated = resolver.cacheCount - mastersBefore
        let backfillResult = IngredientBackfillResult(
            processed: total,
            linked: linked,
            alreadyLinked: alreadyLinked,
            skippedEmptyName: skippedEmptyName,
            mastersCreated: mastersCreated
        )

        AppLogger.swiftData.info(
            "Ingredient backfill: processed=\(total), linked=\(linked), alreadyLinked=\(alreadyLinked), skippedEmpty=\(skippedEmptyName), newMasters=\(mastersCreated)"
        )

        progress = "Done — linked \(linked) of \(total) rows into \(mastersCreated) new ingredients"
        result = backfillResult
        return backfillResult
    }
}
