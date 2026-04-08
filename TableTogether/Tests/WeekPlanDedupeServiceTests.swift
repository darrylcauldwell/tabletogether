import Testing
import Foundation
import CoreData
@testable import TableTogetherLib

@MainActor
@Suite("WeekPlanDedupeService Tests", .serialized)
struct WeekPlanDedupeServiceTests {

    private func makeContext() -> NSManagedObjectContext {
        PersistenceController(inMemory: true).container.viewContext
    }

    /// Build "Monday local-midnight" as a Date. Uses the device's current
    /// timezone to match what `WeekPlan.normalizeToMonday` produces.
    private func monday(year: Int, month: Int, day: Int) -> Date {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .current
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 0
        components.minute = 0
        components.second = 0
        return calendar.date(from: components)!
    }

    // MARK: - normalizeToMonday

    @Test("normalizeToMonday returns the Monday of the week containing the input")
    func normalizeReturnsMondayOfWeek() {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = .current
        let wednesday = cal.date(from: DateComponents(
            year: 2026, month: 4, day: 8, hour: 12, minute: 0, second: 0
        ))!

        let normalized = WeekPlan.normalizeToMonday(wednesday)
        let expectedMonday = monday(year: 2026, month: 4, day: 6)
        #expect(normalized == expectedMonday)
    }

    @Test("normalizeToMonday is stable across the 7 days of a week")
    func normalizeIsStableAcrossWeek() {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = .current
        let expectedMonday = monday(year: 2026, month: 4, day: 6)

        for dayOffset in 0...6 {
            let day = cal.date(byAdding: .day, value: dayOffset, to: expectedMonday)!
            let normalized = WeekPlan.normalizeToMonday(day)
            #expect(normalized == expectedMonday, "Day offset \(dayOffset) normalized to wrong Monday")
        }
    }

    // MARK: - ISO week key

    @Test("isoWeekKey produces YYYY-Www format")
    func isoWeekKeyFormat() {
        let wednesday = monday(year: 2026, month: 4, day: 6).addingTimeInterval(2 * 86400)
        let key = WeekPlan.isoWeekKey(for: wednesday)
        #expect(key == "2026-W15")
    }

    @Test("isoWeekKey is stable for all days within an ISO week")
    func isoWeekKeyStableAcrossWeek() {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = .current
        let mondayAt0 = monday(year: 2026, month: 4, day: 6)

        for dayOffset in 0...6 {
            let day = cal.date(byAdding: .day, value: dayOffset, to: mondayAt0)!
            let key = WeekPlan.isoWeekKey(for: day)
            #expect(key == "2026-W15", "Day offset \(dayOffset) produced unexpected key \(key)")
        }
    }

    @Test("Deterministic UUID is identical for any date within the same ISO week")
    func deterministicUUIDStableAcrossWeek() {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = .current
        let mondayAt0 = monday(year: 2026, month: 4, day: 6)

        let id1 = WeekPlan.deterministicID(for: mondayAt0)
        let id2 = WeekPlan.deterministicID(for: mondayAt0.addingTimeInterval(3 * 86400 + 12 * 3600)) // Thu noon
        let id3 = WeekPlan.deterministicID(for: mondayAt0.addingTimeInterval(6 * 86400 + 23 * 3600)) // Sun 23:00
        #expect(id1 == id2)
        #expect(id2 == id3)
    }

    @Test("MealSlot deterministic UUID is identical for any date within the same ISO week")
    func mealSlotDeterministicUUIDStable() {
        let mondayAt0 = monday(year: 2026, month: 4, day: 6)
        let wednesdayNoon = mondayAt0.addingTimeInterval(2 * 86400 + 12 * 3600)
        let id1 = MealSlot.deterministicID(weekStartDate: mondayAt0, dayOfWeek: .wednesday, mealType: .dinner)
        let id2 = MealSlot.deterministicID(weekStartDate: wednesdayNoon, dayOfWeek: .wednesday, mealType: .dinner)
        #expect(id1 == id2)
    }

    // MARK: - Destructive reset

    @Test("runIfNeeded is idempotent via UserDefaults flag")
    func runIfNeededIsIdempotent() {
        let context = makeContext()
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: WeekPlanDedupeService.migrationFlagKey)
        defer { defaults.removeObject(forKey: WeekPlanDedupeService.migrationFlagKey) }

        let service = WeekPlanDedupeService()
        let first = service.runIfNeeded(context: context)
        #expect(first != nil)

        let second = service.runIfNeeded(context: context)
        #expect(second == nil, "Second run should be guarded by the flag")
    }

    @Test("run deletes all WeekPlans")
    func runDeletesWeekPlans() throws {
        let context = makeContext()
        let household = Household(context: context, name: "Test")

        let plan1 = WeekPlan(context: context, weekStartDate: monday(year: 2026, month: 4, day: 6))
        plan1.household = household
        let plan2 = WeekPlan(context: context, weekStartDate: monday(year: 2026, month: 4, day: 13))
        plan2.household = household
        try context.save()

        #expect(entityCount(WeekPlan.self, "WeekPlan", context) == 2)

        let result = WeekPlanDedupeService().run(context: context)

        #expect(result.weekPlansDeleted == 2)
        #expect(entityCount(WeekPlan.self, "WeekPlan", context) == 0)
    }

    @Test("run deletes all MealSlots")
    func runDeletesMealSlots() throws {
        let context = makeContext()
        let household = Household(context: context, name: "Test")
        let plan = WeekPlan(context: context, weekStartDate: monday(year: 2026, month: 4, day: 6))
        plan.household = household
        plan.createDefaultSlots(context: context)
        try context.save()

        #expect(entityCount(MealSlot.self, "MealSlot", context) == 28)

        let result = WeekPlanDedupeService().run(context: context)

        #expect(result.mealSlotsDeleted == 28)
        #expect(entityCount(MealSlot.self, "MealSlot", context) == 0)
    }

    @Test("run preserves Recipes even when attached to deleted slots")
    func runPreservesRecipes() throws {
        let context = makeContext()
        let household = Household(context: context, name: "Test")
        let recipe = Recipe(context: context, title: "Chinese chicken curry")
        recipe.household = household

        let plan = WeekPlan(context: context, weekStartDate: monday(year: 2026, month: 4, day: 6))
        plan.household = household
        plan.createDefaultSlots(context: context)
        let wedDinner = plan.slot(for: .wednesday, mealType: .dinner)!
        wedDinner.addToRecipes(recipe)
        try context.save()

        #expect(entityCount(Recipe.self, "Recipe", context) == 1)

        WeekPlanDedupeService().run(context: context)

        #expect(entityCount(Recipe.self, "Recipe", context) == 1, "Recipe should survive the reset")
        #expect(entityCount(WeekPlan.self, "WeekPlan", context) == 0)
        #expect(entityCount(MealSlot.self, "MealSlot", context) == 0)
    }

    @Test("run preserves Household, User, Ingredient, FoodItem")
    func runPreservesReferenceData() throws {
        let context = makeContext()
        let household = Household(context: context, name: "Test")
        let user = User(context: context, displayName: "Me")
        user.household = household
        let ingredient = Ingredient(context: context, name: "tomato")
        ingredient.household = household
        let plan = WeekPlan(context: context, weekStartDate: monday(year: 2026, month: 4, day: 6))
        plan.household = household
        plan.createDefaultSlots(context: context)
        try context.save()

        WeekPlanDedupeService().run(context: context)

        #expect(entityCount(Household.self, "Household", context) == 1)
        #expect(entityCount(User.self, "User", context) == 1)
        #expect(entityCount(Ingredient.self, "Ingredient", context) == 1)
        #expect(entityCount(WeekPlan.self, "WeekPlan", context) == 0)
    }

    @Test("run orphans grocery items rather than deleting them")
    func runOrphansGroceryItems() throws {
        let context = makeContext()
        let household = Household(context: context, name: "Test")
        let ingredient = Ingredient(context: context, name: "tomato")
        ingredient.household = household
        let plan = WeekPlan(context: context, weekStartDate: monday(year: 2026, month: 4, day: 6))
        plan.household = household

        let grocery = GroceryItem(
            context: context,
            ingredient: ingredient,
            quantity: 1,
            unit: .piece,
            weekPlan: plan
        )
        _ = grocery

        try context.save()
        #expect(entityCount(GroceryItem.self, "GroceryItem", context) == 1)

        let result = WeekPlanDedupeService().run(context: context)

        #expect(result.groceryItemsOrphaned == 1)
        #expect(entityCount(GroceryItem.self, "GroceryItem", context) == 1, "Grocery item should not be deleted")

        let remaining = try context.fetch(NSFetchRequest<GroceryItem>(entityName: "GroceryItem")).first!
        #expect(remaining.weekPlan == nil, "Grocery item should have weekPlan unlinked")
    }

    @Test("run on empty database returns zero counts")
    func runOnEmptyDatabase() {
        let context = makeContext()
        let result = WeekPlanDedupeService().run(context: context)
        #expect(result.weekPlansDeleted == 0)
        #expect(result.mealSlotsDeleted == 0)
        #expect(result.groceryItemsOrphaned == 0)
    }

    // MARK: - Helpers

    private func entityCount<T: NSManagedObject>(_ type: T.Type, _ name: String, _ context: NSManagedObjectContext) -> Int {
        let request = NSFetchRequest<T>(entityName: name)
        return (try? context.count(for: request)) ?? 0
    }
}
