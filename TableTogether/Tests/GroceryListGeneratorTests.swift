import Testing
import Foundation
import CoreData
@testable import TableTogetherLib

@MainActor
@Suite("GroceryListGenerator Tests", .serialized)
struct GroceryListGeneratorTests {

    // MARK: - Fixtures

    private func makeContext() -> (NSManagedObjectContext, Household) {
        let context = PersistenceController(inMemory: true).container.viewContext
        let household = Household(context: context, name: "Test")
        return (context, household)
    }

    /// Build an Ingredient attached to the household.
    private func makeIngredient(
        _ name: String,
        in context: NSManagedObjectContext,
        household: Household
    ) -> Ingredient {
        let ingredient = Ingredient(context: context, name: name)
        ingredient.household = household
        return ingredient
    }

    /// Build a recipe with a single ingredient line.
    @discardableResult
    private func makeRecipe(
        _ title: String,
        servings: Int,
        ingredient: Ingredient,
        quantity: Double,
        unit: MeasurementUnit,
        in context: NSManagedObjectContext,
        household: Household
    ) -> Recipe {
        let recipe = Recipe(context: context, title: title, servings: servings)
        recipe.household = household
        let ri = RecipeIngredient(
            context: context,
            ingredient: ingredient,
            quantity: quantity,
            unit: unit
        )
        recipe.addIngredient(ri)
        return recipe
    }

    /// Build a planned slot containing the given recipes.
    @discardableResult
    private func makeSlot(
        day: DayOfWeek,
        mealType: MealType,
        servingsPlanned: Int,
        recipes: [Recipe],
        isSkipped: Bool = false,
        in context: NSManagedObjectContext,
        weekPlan: WeekPlan
    ) -> MealSlot {
        let slot = MealSlot(
            context: context,
            dayOfWeek: day,
            mealType: mealType,
            servingsPlanned: servingsPlanned,
            isSkipped: isSkipped
        )
        slot.weekPlan = weekPlan
        for recipe in recipes {
            slot.addToRecipes(recipe)
        }
        weekPlan.addToSlots(slot)
        return slot
    }

    private func makeWeekPlan(
        in context: NSManagedObjectContext,
        household: Household
    ) -> WeekPlan {
        let plan = WeekPlan(context: context, weekStartDate: Date())
        plan.household = household
        return plan
    }

    // MARK: - Same ingredient, same unit → SUM into one line

    @Test("Same ingredient with same unit across two recipes sums into one grocery line")
    func sameIngredientSameUnitSums() throws {
        let (context, household) = makeContext()
        let flour = makeIngredient("flour", in: context, household: household)

        // Both recipes use grams; servings match servingsPlanned so multiplier == 1.
        let recipeA = makeRecipe("A", servings: 2, ingredient: flour, quantity: 100, unit: .gram, in: context, household: household)
        let recipeB = makeRecipe("B", servings: 2, ingredient: flour, quantity: 250, unit: .gram, in: context, household: household)

        let plan = makeWeekPlan(in: context, household: household)
        makeSlot(day: .monday, mealType: .dinner, servingsPlanned: 2, recipes: [recipeA], in: context, weekPlan: plan)
        makeSlot(day: .tuesday, mealType: .dinner, servingsPlanned: 2, recipes: [recipeB], in: context, weekPlan: plan)

        let generator = GroceryListGenerator()
        let items = generator.generateGroceryList(from: plan, context: context)

        #expect(items.count == 1)
        let item = try #require(items.first)
        #expect(item.ingredient === flour)
        #expect(item.unit == .gram)
        #expect(item.quantity == 350) // 100 + 250
    }

    // MARK: - Same ingredient, DIFFERENT units → TWO separate lines (regression)

    @Test("Same ingredient with different units produces two separate grocery lines")
    func sameIngredientDifferentUnitsStaySeparate() throws {
        let (context, household) = makeContext()
        let oil = makeIngredient("olive oil", in: context, household: household)

        // grams in one recipe, tablespoons in another — no conversion, must not be summed.
        let recipeA = makeRecipe("A", servings: 2, ingredient: oil, quantity: 30, unit: .gram, in: context, household: household)
        let recipeB = makeRecipe("B", servings: 2, ingredient: oil, quantity: 2, unit: .tablespoon, in: context, household: household)

        let plan = makeWeekPlan(in: context, household: household)
        makeSlot(day: .monday, mealType: .dinner, servingsPlanned: 2, recipes: [recipeA], in: context, weekPlan: plan)
        makeSlot(day: .tuesday, mealType: .dinner, servingsPlanned: 2, recipes: [recipeB], in: context, weekPlan: plan)

        let generator = GroceryListGenerator()
        let items = generator.generateGroceryList(from: plan, context: context)

        // Two line items: both for the same ingredient but different units.
        #expect(items.count == 2)
        #expect(items.allSatisfy { $0.ingredient === oil })

        let gramItem = try #require(items.first { $0.unit == .gram })
        let tbspItem = try #require(items.first { $0.unit == .tablespoon })
        #expect(gramItem.quantity == 30)
        #expect(tbspItem.quantity == 2)
    }

    // MARK: - Serving multiplier scales the quantity

    @Test("servingsPlanned vs recipe.servings scales the aggregated quantity")
    func servingMultiplierScalesQuantity() throws {
        let (context, household) = makeContext()
        let rice = makeIngredient("rice", in: context, household: household)

        // Recipe serves 2; plan for 6 → multiplier 3 → 100g * 3 = 300g.
        let recipe = makeRecipe("Rice bowl", servings: 2, ingredient: rice, quantity: 100, unit: .gram, in: context, household: household)

        let plan = makeWeekPlan(in: context, household: household)
        makeSlot(day: .monday, mealType: .dinner, servingsPlanned: 6, recipes: [recipe], in: context, weekPlan: plan)

        let generator = GroceryListGenerator()
        let items = generator.generateGroceryList(from: plan, context: context)

        #expect(items.count == 1)
        let item = try #require(items.first)
        #expect(item.quantity == 300)
    }

    // MARK: - Skipped and empty slots are excluded

    @Test("Skipped and empty slots are excluded from the grocery list")
    func skippedAndEmptySlotsExcluded() throws {
        let (context, household) = makeContext()
        let beans = makeIngredient("beans", in: context, household: household)
        let onion = makeIngredient("onion", in: context, household: household)
        let salt = makeIngredient("salt", in: context, household: household)

        let included = makeRecipe("Included", servings: 2, ingredient: beans, quantity: 200, unit: .gram, in: context, household: household)
        let skippedRecipe = makeRecipe("Skipped", servings: 2, ingredient: onion, quantity: 50, unit: .gram, in: context, household: household)
        let unusedRecipe = makeRecipe("Unused", servings: 2, ingredient: salt, quantity: 5, unit: .gram, in: context, household: household)
        _ = unusedRecipe // not attached to any slot

        let plan = makeWeekPlan(in: context, household: household)
        // Active slot
        makeSlot(day: .monday, mealType: .dinner, servingsPlanned: 2, recipes: [included], in: context, weekPlan: plan)
        // Skipped slot (carries a recipe but must be ignored)
        makeSlot(day: .tuesday, mealType: .dinner, servingsPlanned: 2, recipes: [skippedRecipe], isSkipped: true, in: context, weekPlan: plan)
        // Empty slot (no recipes)
        makeSlot(day: .wednesday, mealType: .dinner, servingsPlanned: 2, recipes: [], in: context, weekPlan: plan)

        let generator = GroceryListGenerator()
        let items = generator.generateGroceryList(from: plan, context: context)

        #expect(items.count == 1)
        let item = try #require(items.first)
        #expect(item.ingredient === beans)
        #expect(item.quantity == 200)
        // Skipped/empty ingredients must not appear.
        #expect(!items.contains { $0.ingredient === onion })
        #expect(!items.contains { $0.ingredient === salt })
    }
}
