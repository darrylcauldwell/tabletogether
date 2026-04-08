import Foundation
import CoreData

// MARK: - WeekPlanDedupeService
//
// One-shot migration that cleans up duplicate `WeekPlan` and `MealSlot`
// records created by the locale-dependent deterministic-ID bug fixed on
// 2026-04-08.
//
// **The bug:** `WeekPlan.normalizeToMonday()` used `Calendar.current`, which
// varies by device locale (firstWeekday, minimumDaysInFirstWeek) and
// timezone. Two devices with slightly different regional settings computed
// different `Date` objects for "the same Monday", producing different
// deterministic UUIDs and therefore distinct `WeekPlan` records in CloudKit
// for the same wall-clock week. The meal slots attached to each plan were
// likewise distinct. On sync, devices accumulated duplicates.
//
// **The fix:** `normalizeToMonday()` now uses a fixed ISO 8601 UTC
// calendar, so both devices produce identical UUIDs going forward. But
// that alone doesn't fix the existing corrupted state. This service does.
//
// **Natural key for dedup:**
//   - `WeekPlan`: the normalized-to-Monday weekStartDate (using the new fixed
//     calendar) — regardless of UUID
//   - `MealSlot` within a week: the `(dayOfWeek, mealType)` pair — regardless
//     of UUID
//
// **Merge strategy:**
//   1. Group all `WeekPlan` records by their normalized weekStartDate
//   2. For each group with > 1 plan, pick a canonical (the oldest by createdAt)
//   3. Re-parent every slot from the duplicate plans to the canonical plan
//   4. Delete the duplicate plans
//   5. Within the merged plan, group slots by `(dayOfWeek, mealType)`
//   6. For each group with > 1 slot, pick a canonical (the one with the most
//      attached recipes, ties broken by oldest)
//   7. Merge recipe sets from duplicate slots into the canonical slot
//   8. Merge customMealName if non-empty
//   9. Delete the duplicate slots
//  10. Save context
//
// Idempotent: subsequent runs find no duplicates, do nothing.
//
// Ran automatically on launch, guarded by a UserDefaults flag so it only
// executes once per device install. If the flag is absent, the service
// runs and sets the flag. If it's present, the service is a no-op.

@MainActor
final class WeekPlanDedupeService {

    /// UserDefaults key used to gate the one-shot run.
    static let migrationFlagKey = "WeekPlanDedupeService.hasRun.v1"

    struct Result {
        let planGroupsFound: Int
        let planDuplicatesRemoved: Int
        let slotDuplicatesRemoved: Int
        let recipeRelationshipsMerged: Int

        var summary: String {
            "WeekPlan dedupe: \(planGroupsFound) groups inspected, " +
            "\(planDuplicatesRemoved) duplicate plans removed, " +
            "\(slotDuplicatesRemoved) duplicate slots removed, " +
            "\(recipeRelationshipsMerged) recipe relationships reassigned"
        }
    }

    /// Runs the dedup migration if it hasn't run yet on this install.
    /// Safe to call multiple times — the flag makes it a no-op after the
    /// first successful run.
    @discardableResult
    func runIfNeeded(context: NSManagedObjectContext) -> Result? {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: Self.migrationFlagKey) {
            return nil
        }
        let result = run(context: context)
        defaults.set(true, forKey: Self.migrationFlagKey)
        return result
    }

    /// Runs unconditionally. Exposed for tests and for a future manual
    /// "Re-run dedupe" action in Settings (if useful).
    @discardableResult
    func run(context: NSManagedObjectContext) -> Result {
        var planGroupsFound = 0
        var planDuplicatesRemoved = 0
        var slotDuplicatesRemoved = 0
        var recipeRelationshipsMerged = 0

        // Phase 1: group WeekPlans by normalized week start date
        let planFetch = NSFetchRequest<WeekPlan>(entityName: "WeekPlan")
        let allPlans: [WeekPlan]
        do {
            allPlans = try context.fetch(planFetch)
        } catch {
            AppLogger.swiftData.error("WeekPlanDedupeService: fetch WeekPlan failed: \(error.localizedDescription)")
            return Result(planGroupsFound: 0, planDuplicatesRemoved: 0, slotDuplicatesRemoved: 0, recipeRelationshipsMerged: 0)
        }

        var plansByNormalizedWeek: [Date: [WeekPlan]] = [:]
        for plan in allPlans {
            let normalized = WeekPlan.normalizeToMonday(plan.weekStartDate)
            plansByNormalizedWeek[normalized, default: []].append(plan)
        }

        // Phase 2: merge duplicates within each group
        for (normalizedDate, plans) in plansByNormalizedWeek {
            planGroupsFound += 1
            guard plans.count > 1 else {
                // No duplication for this week, but normalize the canonical
                // plan's weekStartDate to the fixed-calendar value so future
                // deterministic IDs match.
                if let only = plans.first, only.weekStartDate != normalizedDate {
                    only.weekStartDate = normalizedDate
                    only.modifiedAt = Date()
                }
                continue
            }

            // Canonical: oldest createdAt. Stable tiebreaker by objectID URI.
            let canonical = plans.sorted { a, b in
                if a.createdAt != b.createdAt {
                    return a.createdAt < b.createdAt
                }
                return a.objectID.uriRepresentation().absoluteString
                    < b.objectID.uriRepresentation().absoluteString
            }.first!

            // Normalize the canonical's weekStartDate so future deterministic
            // IDs match its actual Monday.
            if canonical.weekStartDate != normalizedDate {
                canonical.weekStartDate = normalizedDate
            }

            for duplicate in plans where duplicate !== canonical {
                // Move all slots from the duplicate to the canonical. They'll
                // be deduped against existing canonical slots in Phase 3.
                for slot in duplicate.slotsArray {
                    slot.weekPlan = canonical
                    canonical.addToSlots(slot)
                }
                // Move any grocery items referencing the duplicate's weekPlan.
                for groceryItem in duplicate.groceryItemsArray {
                    groceryItem.weekPlan = canonical
                    canonical.addToGroceryItems(groceryItem)
                }
                context.delete(duplicate)
                planDuplicatesRemoved += 1
            }

            canonical.modifiedAt = Date()
        }

        // Phase 3: within each canonical WeekPlan, dedupe slots by (day, mealType)
        let planFetch2 = NSFetchRequest<WeekPlan>(entityName: "WeekPlan")
        let canonicalPlans: [WeekPlan]
        do {
            canonicalPlans = try context.fetch(planFetch2)
        } catch {
            AppLogger.swiftData.error("WeekPlanDedupeService: re-fetch WeekPlan failed: \(error.localizedDescription)")
            canonicalPlans = []
        }

        for plan in canonicalPlans {
            var slotsByKey: [String: [MealSlot]] = [:]
            for slot in plan.slotsArray {
                let key = "\(slot.dayOfWeek.rawValue)|\(slot.mealType.rawValue)"
                slotsByKey[key, default: []].append(slot)
            }

            for (_, slots) in slotsByKey where slots.count > 1 {
                // Canonical slot: the one with the most attached recipes.
                // Tiebreaker: oldest createdAt, then stable objectID URI.
                let canonicalSlot = slots.sorted { a, b in
                    let aCount = a.recipesArray.count
                    let bCount = b.recipesArray.count
                    if aCount != bCount { return aCount > bCount }
                    if a.createdAt != b.createdAt { return a.createdAt < b.createdAt }
                    return a.objectID.uriRepresentation().absoluteString
                        < b.objectID.uriRepresentation().absoluteString
                }.first!

                for duplicate in slots where duplicate !== canonicalSlot {
                    // Merge recipe relationships — union of both sets.
                    for recipe in duplicate.recipesArray
                        where !canonicalSlot.recipesArray.contains(recipe) {
                        canonicalSlot.addToRecipes(recipe)
                        recipeRelationshipsMerged += 1
                    }

                    // Merge customMealName if canonical's is empty
                    if (canonicalSlot.customMealName?.isEmpty ?? true),
                       let dupName = duplicate.customMealName, !dupName.isEmpty {
                        canonicalSlot.customMealName = dupName
                    }

                    // Merge archetype if canonical has none
                    if canonicalSlot.archetype == nil, let dupArch = duplicate.archetype {
                        canonicalSlot.archetype = dupArch
                    }

                    // Prefer non-skipped state
                    if duplicate.isSkipped == false && canonicalSlot.isSkipped {
                        canonicalSlot.isSkipped = false
                    }

                    context.delete(duplicate)
                    slotDuplicatesRemoved += 1
                }

                canonicalSlot.modifiedAt = Date()
            }
        }

        // Save context
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                AppLogger.swiftData.error("WeekPlanDedupeService: save failed: \(error.localizedDescription)")
            }
        }

        let result = Result(
            planGroupsFound: planGroupsFound,
            planDuplicatesRemoved: planDuplicatesRemoved,
            slotDuplicatesRemoved: slotDuplicatesRemoved,
            recipeRelationshipsMerged: recipeRelationshipsMerged
        )
        AppLogger.swiftData.info("\(result.summary)")
        return result
    }
}
