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
    ///
    /// **Version history:**
    /// - `v1` shipped in build 9 with a broken `normalizeToMonday` that used
    ///   UTC timezone for ISO-week calculation. Users in non-UTC timezones
    ///   ended up with plans shifted one ISO-week earlier than intended.
    /// - `v2` shipped in build 10 with the corrected `normalizeToMonday`
    ///   (ISO 8601 calendar in the device's current timezone) and re-ran
    ///   the dedup/re-normalize pass. Fixed the week shift but deterministic
    ///   IDs were still computed from Date values, which could still diverge
    ///   across devices at subsecond precision or on calendar edge cases.
    /// - `v3` shipped in build 11 with string-based deterministic IDs
    ///   ("2026-W15" instead of a Date). The ID path no longer involves
    ///   Date or timezone arithmetic, so two devices in the same local week
    ///   guarantee identical UUIDs. v3 migration is **destructive**: it
    ///   deletes all WeekPlan and MealSlot records. Recipes, Ingredients,
    ///   FoodItems, etc. are untouched. The next launch of the Meals view
    ///   creates a fresh current-week plan via ensureWeekPlanExists() using
    ///   the new string-based ID. User re-adds any meals that were on the
    ///   old plans; they flagged this as acceptable scope.
    static let migrationFlagKey = "WeekPlanDedupeService.hasRun.v3"

    struct Result {
        let weekPlansDeleted: Int
        let mealSlotsDeleted: Int
        let mealSlotComponentsDeleted: Int
        let groceryItemsOrphaned: Int

        var summary: String {
            "WeekPlan reset: deleted \(weekPlansDeleted) week plans, " +
            "\(mealSlotsDeleted) meal slots, " +
            "\(mealSlotComponentsDeleted) meal slot components; " +
            "orphaned \(groceryItemsOrphaned) grocery items (preserved, unlinked)"
        }
    }

    /// Runs the reset migration if it hasn't run yet on this install.
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

    /// Runs unconditionally. Exposed for tests.
    ///
    /// **Destructive:** deletes every WeekPlan, MealSlot, and
    /// MealSlotComponent in the context. Recipes, Ingredients, and FoodItems
    /// are preserved. Grocery items that reference a deleted week plan are
    /// unlinked (weekPlan = nil) but kept in the database — the user's
    /// manual grocery list survives.
    ///
    /// The next time `ensureWeekPlanExists()` runs (e.g. when the user opens
    /// Meals → This Week), a fresh WeekPlan is created using the new
    /// string-based deterministic ID, which will match across devices.
    @discardableResult
    func run(context: NSManagedObjectContext) -> Result {
        var weekPlansDeleted = 0
        var mealSlotsDeleted = 0
        var mealSlotComponentsDeleted = 0
        var groceryItemsOrphaned = 0

        // Phase 1: unlink grocery items from any week plan
        let groceryFetch = NSFetchRequest<GroceryItem>(entityName: "GroceryItem")
        groceryFetch.predicate = NSPredicate(format: "weekPlan != nil")
        if let groceryItems = try? context.fetch(groceryFetch) {
            for item in groceryItems {
                item.weekPlan = nil
                groceryItemsOrphaned += 1
            }
        }

        // Phase 2: delete all MealSlotComponents (children of MealSlot)
        let componentFetch = NSFetchRequest<MealSlotComponent>(entityName: "MealSlotComponent")
        if let components = try? context.fetch(componentFetch) {
            for component in components {
                context.delete(component)
                mealSlotComponentsDeleted += 1
            }
        }

        // Phase 3: delete all MealSlots
        let slotFetch = NSFetchRequest<MealSlot>(entityName: "MealSlot")
        if let slots = try? context.fetch(slotFetch) {
            for slot in slots {
                context.delete(slot)
                mealSlotsDeleted += 1
            }
        }

        // Phase 4: delete all WeekPlans
        let planFetch = NSFetchRequest<WeekPlan>(entityName: "WeekPlan")
        if let plans = try? context.fetch(planFetch) {
            for plan in plans {
                context.delete(plan)
                weekPlansDeleted += 1
            }
        }

        // Save
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                AppLogger.swiftData.error("WeekPlanDedupeService: save failed: \(error.localizedDescription)")
            }
        }

        let result = Result(
            weekPlansDeleted: weekPlansDeleted,
            mealSlotsDeleted: mealSlotsDeleted,
            mealSlotComponentsDeleted: mealSlotComponentsDeleted,
            groceryItemsOrphaned: groceryItemsOrphaned
        )
        AppLogger.swiftData.info("\(result.summary)")
        return result
    }
}
