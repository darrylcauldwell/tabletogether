import Testing
import Foundation
import CoreData
@testable import TableTogetherLib

/// Tests the find-or-create logic that the Add to Plan sheet relies on. The
/// sheet itself is a SwiftUI view (hard to test in isolation) but the slot
/// resolution + add-recipe flow is pure model logic that we CAN test.
@MainActor
@Suite("Add to Plan slot resolution", .serialized)
struct AddToPlanLogicTests {

    private func makeContext() -> NSManagedObjectContext {
        PersistenceController(inMemory: true).container.viewContext
    }

    private func makeWeekPlan(in context: NSManagedObjectContext) -> WeekPlan {
        WeekPlan(context: context, weekStartDate: Date())
    }

    private func makeRecipe(in context: NSManagedObjectContext, title: String) -> Recipe {
        Recipe(context: context, title: title, servings: 4)
    }

    @Test("Adding a recipe to an empty week creates a new MealSlot")
    func addToEmptyWeek() throws {
        let context = makeContext()
        let weekPlan = makeWeekPlan(in: context)
        let recipe = makeRecipe(in: context, title: "Butter Chicken")

        // Simulate the sheet's find-or-create logic
        let day = DayOfWeek.friday
        let mealType = MealType.dinner

        let slot: MealSlot
        if let existing = weekPlan.slot(for: day, mealType: mealType) {
            slot = existing
        } else {
            let newSlot = MealSlot(context: context, dayOfWeek: day, mealType: mealType)
            newSlot.weekPlan = weekPlan
            slot = newSlot
        }
        slot.addToRecipes(recipe)
        slot.modifiedAt = Date()

        try context.save()

        #expect(weekPlan.slotsArray.count == 1)
        #expect(slot.dayOfWeek == .friday)
        #expect(slot.mealType == .dinner)
        #expect(slot.recipesArray.contains { $0.title == "Butter Chicken" })
    }

    @Test("Adding a recipe to a week with an existing slot appends, not replaces")
    func appendToExistingSlot() throws {
        let context = makeContext()
        let weekPlan = makeWeekPlan(in: context)

        // Pre-create a slot with one recipe
        let firstSlot = MealSlot(context: context, dayOfWeek: .friday, mealType: .dinner)
        firstSlot.weekPlan = weekPlan
        let firstRecipe = makeRecipe(in: context, title: "Aloo Gobi")
        firstSlot.addToRecipes(firstRecipe)

        // Now simulate adding another recipe to the SAME day/mealType
        let secondRecipe = makeRecipe(in: context, title: "Naan")
        let day = DayOfWeek.friday
        let mealType = MealType.dinner

        let resolved: MealSlot
        if let existing = weekPlan.slot(for: day, mealType: mealType) {
            resolved = existing
        } else {
            let newSlot = MealSlot(context: context, dayOfWeek: day, mealType: mealType)
            newSlot.weekPlan = weekPlan
            resolved = newSlot
        }
        resolved.addToRecipes(secondRecipe)

        try context.save()

        // Same slot, both recipes
        #expect(weekPlan.slotsArray.count == 1)
        #expect(resolved.recipesArray.count == 2)
        #expect(resolved.recipesArray.contains { $0.title == "Aloo Gobi" })
        #expect(resolved.recipesArray.contains { $0.title == "Naan" })
    }

    @Test("Different day or meal type creates a separate slot")
    func differentSlotDoesNotCollide() throws {
        let context = makeContext()
        let weekPlan = makeWeekPlan(in: context)

        let lunch = MealSlot(context: context, dayOfWeek: .friday, mealType: .lunch)
        lunch.weekPlan = weekPlan
        lunch.addToRecipes(makeRecipe(in: context, title: "Soup"))

        // Now add to dinner — should NOT find lunch's slot
        let day = DayOfWeek.friday
        let mealType = MealType.dinner

        let resolved: MealSlot
        if let existing = weekPlan.slot(for: day, mealType: mealType) {
            resolved = existing
        } else {
            let newSlot = MealSlot(context: context, dayOfWeek: day, mealType: mealType)
            newSlot.weekPlan = weekPlan
            resolved = newSlot
        }
        resolved.addToRecipes(makeRecipe(in: context, title: "Curry"))

        try context.save()

        #expect(weekPlan.slotsArray.count == 2)
        let dinnerSlot = weekPlan.slot(for: .friday, mealType: .dinner)
        let lunchSlot = weekPlan.slot(for: .friday, mealType: .lunch)
        #expect(dinnerSlot?.recipesArray.first?.title == "Curry")
        #expect(lunchSlot?.recipesArray.first?.title == "Soup")
    }
}
