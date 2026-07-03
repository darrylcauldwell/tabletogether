import Testing
import Foundation
import CoreData
@testable import TableTogetherLib

/// Tests the fetch-or-create logic behind the Add to Plan sheet and the lazy
/// slot structure (#Change2): plans and slots materialize only when a meal is
/// planned into them, with deterministic ids so concurrent creation converges.
@MainActor
@Suite("Add to Plan slot resolution", .serialized)
struct AddToPlanLogicTests {

    private func makeContext() -> NSManagedObjectContext {
        PersistenceController(inMemory: true).container.viewContext
    }

    private func makeRecipe(in context: NSManagedObjectContext, title: String) -> Recipe {
        Recipe(context: context, title: title, servings: 4)
    }

    @Test("Adding a recipe to an empty week creates a new MealSlot with its deterministic id")
    func addToEmptyWeek() throws {
        let context = makeContext()
        let weekPlan = WeekPlan.fetchOrCreate(for: Date(), household: nil, in: context)
        let recipe = makeRecipe(in: context, title: "Butter Chicken")

        let slot = weekPlan.fetchOrCreateSlot(day: .friday, mealType: .dinner, in: context)
        slot.addToRecipes(recipe)
        slot.modifiedAt = Date()

        try context.save()

        #expect(weekPlan.slotsArray.count == 1)
        #expect(slot.dayOfWeek == .friday)
        #expect(slot.mealType == .dinner)
        #expect(slot.id == MealSlot.deterministicID(
            weekStartDate: weekPlan.weekStartDate, dayOfWeek: .friday, mealType: .dinner))
        #expect(slot.recipesArray.contains { $0.title == "Butter Chicken" })
    }

    @Test("Adding a recipe to a week with an existing slot appends, not replaces")
    func appendToExistingSlot() throws {
        let context = makeContext()
        let weekPlan = WeekPlan.fetchOrCreate(for: Date(), household: nil, in: context)

        let firstSlot = weekPlan.fetchOrCreateSlot(day: .friday, mealType: .dinner, in: context)
        firstSlot.addToRecipes(makeRecipe(in: context, title: "Aloo Gobi"))

        let resolved = weekPlan.fetchOrCreateSlot(day: .friday, mealType: .dinner, in: context)
        resolved.addToRecipes(makeRecipe(in: context, title: "Naan"))

        try context.save()

        // Same slot, both recipes
        #expect(resolved === firstSlot)
        #expect(weekPlan.slotsArray.count == 1)
        #expect(resolved.recipesArray.count == 2)
        #expect(resolved.recipesArray.contains { $0.title == "Aloo Gobi" })
        #expect(resolved.recipesArray.contains { $0.title == "Naan" })
    }

    @Test("Different day or meal type creates a separate slot")
    func differentSlotDoesNotCollide() throws {
        let context = makeContext()
        let weekPlan = WeekPlan.fetchOrCreate(for: Date(), household: nil, in: context)

        let lunch = weekPlan.fetchOrCreateSlot(day: .friday, mealType: .lunch, in: context)
        lunch.addToRecipes(makeRecipe(in: context, title: "Soup"))

        let dinner = weekPlan.fetchOrCreateSlot(day: .friday, mealType: .dinner, in: context)
        dinner.addToRecipes(makeRecipe(in: context, title: "Curry"))

        try context.save()

        #expect(weekPlan.slotsArray.count == 2)
        #expect(weekPlan.slot(for: .friday, mealType: .dinner)?.recipesArray.first?.title == "Curry")
        #expect(weekPlan.slot(for: .friday, mealType: .lunch)?.recipesArray.first?.title == "Soup")
    }

    @Test("fetchOrCreate returns the same plan for any date in the same week")
    func fetchOrCreatePlanConverges() throws {
        let context = makeContext()
        let monday = WeekPlan.normalizeToMonday(Date())
        let midweek = Calendar.current.date(byAdding: .day, value: 3, to: monday)!

        let first = WeekPlan.fetchOrCreate(for: monday, household: nil, in: context)
        try context.save()
        let second = WeekPlan.fetchOrCreate(for: midweek, household: nil, in: context)

        #expect(first === second)
        #expect(first.id == WeekPlan.deterministicID(for: monday))
        // Lazily created plans start slotless — empty cells are UI, not data.
        #expect(first.slotsArray.isEmpty)
    }

    @Test("copyFrom materializes destination slots for content-bearing source slots only")
    func copyFromMaterializesOnDemand() throws {
        let context = makeContext()
        let user = User(context: context, displayName: "Me")

        let lastMonday = Calendar.current.date(byAdding: .weekOfYear, value: -1, to: WeekPlan.normalizeToMonday(Date()))!
        let source = WeekPlan.fetchOrCreate(for: lastMonday, household: nil, in: context)
        let planned = source.fetchOrCreateSlot(day: .monday, mealType: .dinner, in: context)
        planned.addToRecipes(makeRecipe(in: context, title: "Lasagne"))
        let named = source.fetchOrCreateSlot(day: .tuesday, mealType: .lunch, in: context)
        named.customMealName = "Leftovers"
        let skipped = source.fetchOrCreateSlot(day: .wednesday, mealType: .breakfast, in: context)
        skipped.isSkipped = true

        let destination = WeekPlan.fetchOrCreate(for: Date(), household: nil, in: context)
        destination.copyFrom(source, by: user)
        try context.save()

        // Planned + custom-named slots copied; the skip flag is week-specific.
        #expect(destination.slotsArray.count == 2)
        #expect(destination.slot(for: .monday, mealType: .dinner)?.recipesArray.first?.title == "Lasagne")
        #expect(destination.slot(for: .tuesday, mealType: .lunch)?.customMealName == "Leftovers")
        #expect(destination.slot(for: .wednesday, mealType: .breakfast) == nil)
    }
}
