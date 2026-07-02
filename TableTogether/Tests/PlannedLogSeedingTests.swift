import Testing
import Foundation
import CoreData
@testable import TableTogetherLib

/// Tests for ``PrivateDataManager/plannedLog(for:perPersonServings:date:estimator:)`` —
/// the builder that seeds private log entries from planned meal slots.
@MainActor
struct PlannedLogSeedingTests {

    private func makeContext() -> NSManagedObjectContext {
        PersistenceController(inMemory: true).container.viewContext
    }

    @Test func customMealSlotCarriesNameAndEstimatedMacros() {
        let context = makeContext()
        let slot = MealSlot(context: context, dayOfWeek: .monday, mealType: .dinner)
        slot.customMealName = "chips"

        let log = PrivateDataManager.plannedLog(
            for: slot,
            perPersonServings: 1.0,
            date: Date(timeIntervalSince1970: 1_700_000_000),
            estimator: MealEstimatorService()
        )

        #expect(log.quickLogName == "chips")
        #expect(log.recipeID == nil)
        #expect(log.mealSlotID == slot.id)
        #expect(log.status == .planned)
        // "chips" is in the built-in food database, so macros must be prefilled.
        #expect((log.quickLogCalories ?? 0) > 0)
    }

    @Test func customMealMacrosScaleWithServings() {
        let context = makeContext()
        let slot = MealSlot(context: context, dayOfWeek: .monday, mealType: .dinner)
        slot.customMealName = "chips"

        let single = PrivateDataManager.plannedLog(
            for: slot, perPersonServings: 1.0,
            date: Date(timeIntervalSince1970: 1_700_000_000),
            estimator: MealEstimatorService()
        )
        let double = PrivateDataManager.plannedLog(
            for: slot, perPersonServings: 2.0,
            date: Date(timeIntervalSince1970: 1_700_000_000),
            estimator: MealEstimatorService()
        )

        let singleCalories = single.quickLogCalories ?? 0
        let doubleCalories = double.quickLogCalories ?? 0
        #expect(doubleCalories == singleCalories * 2)
    }

    @Test func unknownCustomMealKeepsNameWithoutMacros() {
        let context = makeContext()
        let slot = MealSlot(context: context, dayOfWeek: .tuesday, mealType: .lunch)
        slot.customMealName = "grandma's mystery casserole"

        let log = PrivateDataManager.plannedLog(
            for: slot,
            perPersonServings: 1.0,
            date: Date(timeIntervalSince1970: 1_700_000_000),
            estimator: MealEstimatorService()
        )

        // The name still reaches the log so the entry isn't anonymous, but no
        // macros are invented for a food the estimator doesn't know.
        #expect(log.quickLogName == "grandma's mystery casserole")
        #expect(log.quickLogCalories == nil)
    }

    @Test func recipeBackedSlotDoesNotBecomeQuickLog() {
        let context = makeContext()
        let slot = MealSlot(context: context, dayOfWeek: .friday, mealType: .dinner)
        let recipe = Recipe(context: context, title: "Fish Pie")
        slot.addToRecipes(recipe)

        let log = PrivateDataManager.plannedLog(
            for: slot,
            perPersonServings: 1.5,
            date: Date(timeIntervalSince1970: 1_700_000_000),
            estimator: MealEstimatorService()
        )

        #expect(log.recipeID == recipe.id)
        #expect(log.quickLogName == nil)
        #expect(log.quickLogCalories == nil)
        #expect(log.servingsConsumed == 1.5)
    }
}
