import Foundation
import CoreData

/// Resolves free-text ingredient strings (e.g. "tomato", "TOMATOES", "  spring onion  ")
/// to a master `Ingredient` record, creating new records as needed.
///
/// **Resolution algorithm — conservative, byte-exact matching:**
/// 1. Normalise input (lowercase + trim whitespace)
/// 2. Look up an `Ingredient` in the resolver's household where `normalizedName` equals the normalised input
/// 3. If no match, look up an `Ingredient` whose `userAliases` contains the normalised input
/// 4. If still no match, create a new `Ingredient` with `isUserCreated = false` (importer-created)
/// 5. Cache the result for the lifetime of this resolver instance
///
/// **Why no fuzzy/synonym matching:** zero false positives. "tomato" and "tomatoes"
/// will be two separate records unless the user explicitly adds one as an alias of
/// the other via the Ingredient Library UI. This is the only resolution strategy
/// where the user can fully predict what the resolver will do.
///
/// **Lifetime:** create one resolver instance per import operation. The internal
/// cache prewarms once at init and is updated as new ingredients are created during
/// resolution, so the entire import runs against an in-memory dictionary rather
/// than re-fetching from Core Data on every line.
///
/// **Per #59 Phase 3.**
@MainActor
final class RecipeIngredientResolver {

    private let context: NSManagedObjectContext
    private let household: Household?

    /// Maps normalised name → resolved Ingredient. Includes both canonical
    /// `normalizedName` entries and every alias. Built from a single fetch at
    /// init time, then maintained as new ingredients are created during the
    /// resolver's lifetime.
    private var cache: [String: Ingredient] = [:]

    init(context: NSManagedObjectContext, household: Household?) {
        self.context = context
        self.household = household
        prewarmCache()
    }

    // MARK: - Public API

    /// Resolves a raw ingredient string to an `Ingredient` master record.
    /// Returns nil only if the input normalises to an empty string.
    /// All other inputs return either an existing Ingredient (cache hit or
    /// alias match) or a freshly-created one.
    @discardableResult
    func resolve(_ rawName: String) -> Ingredient? {
        let normalized = normalise(rawName)
        guard !normalized.isEmpty else { return nil }

        if let cached = cache[normalized] {
            return cached
        }

        // No match — create a new Ingredient.
        // Preserve the original casing/whitespace of the input as the display
        // name (after a single round of trim) — the user picked it that way
        // when they originally wrote the recipe and it'll be friendlier to
        // see in the Ingredient Library than the lowercased form.
        let displayName = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let ingredient = Ingredient(
            context: context,
            name: displayName,
            isUserCreated: false
        )
        ingredient.household = household

        cache[normalized] = ingredient
        return ingredient
    }

    /// Number of ingredients currently in the cache. Useful for tests and
    /// post-import diagnostics ("backfilled N rows into M masters").
    var cacheCount: Int { cache.count }

    // MARK: - Cache Prewarming

    /// Loads every `Ingredient` for the resolver's household into the cache,
    /// keyed by `normalizedName` and by every entry in `userAliases`. A single
    /// fetch up front avoids N² lookup cost across long import runs.
    private func prewarmCache() {
        let request = NSFetchRequest<Ingredient>(entityName: "Ingredient")
        if let household {
            request.predicate = NSPredicate(format: "household == %@", household)
        } else {
            request.predicate = NSPredicate(format: "household == nil")
        }

        let existing: [Ingredient]
        do {
            existing = try context.fetch(request)
        } catch {
            AppLogger.swiftData.error("RecipeIngredientResolver prewarm fetch failed: \(error.localizedDescription)")
            return
        }

        for ingredient in existing {
            cache[ingredient.normalizedName] = ingredient
            for alias in ingredient.userAliasesList {
                // Aliases stored on Ingredient are already normalised by addAlias().
                // Defensive: still apply normalise() in case legacy data exists.
                let key = normalise(alias)
                if !key.isEmpty {
                    cache[key] = ingredient
                }
            }
        }
    }

    // MARK: - Helpers

    /// The single canonical normalisation: lowercase + trim leading/trailing
    /// whitespace and newlines. Anything more aggressive (qualifier stripping,
    /// plural folding, fuzzy match) is intentionally omitted — see the type's
    /// doc comment.
    private func normalise(_ raw: String) -> String {
        raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
