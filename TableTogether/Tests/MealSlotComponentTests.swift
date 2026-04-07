import Testing
import Foundation
import CoreData
@testable import TableTogetherLib

@MainActor
@Suite("MealSlotComponent Tests", .serialized)
struct MealSlotComponentTests {

    /// Build a fresh in-memory Core Data context for each test.
    private func makeContext() -> NSManagedObjectContext {
        PersistenceController(inMemory: true).container.viewContext
    }

    private func makeSlot(in context: NSManagedObjectContext, servingsPlanned: Int = 1) -> MealSlot {
        let slot = MealSlot(
            context: context,
            dayOfWeek: .monday,
            mealType: .dinner
        )
        slot.servingsPlanned = Int32(servingsPlanned)
        return slot
    }

    private func makeIngredient(
        in context: NSManagedObjectContext,
        name: String,
        cal: Double,
        protein: Double,
        carbs: Double,
        fat: Double
    ) -> Ingredient {
        let ing = Ingredient(
            context: context,
            name: name,
            category: .other,
            defaultUnit: .gram,
            caloriesPer100g: cal,
            proteinPer100g: protein,
            carbsPer100g: carbs,
            fatPer100g: fat
        )
        return ing
    }

    // MARK: - Kind detection

    @Test("Component with a recipe has kind .recipe")
    func recipeKind() {
        let context = makeContext()
        let slot = makeSlot(in: context)
        let recipe = Recipe(context: context, title: "Test Recipe", servings: 4)
        let component = MealSlotComponent(context: context, slot: slot, recipe: recipe)
        #expect(component.kind == .recipe)
        #expect(component.displayName == "Test Recipe")
    }

    @Test("Component with an ingredient has kind .ingredient")
    func ingredientKind() {
        let context = makeContext()
        let slot = makeSlot(in: context)
        let ing = makeIngredient(in: context, name: "Basmati Rice (cooked)", cal: 130, protein: 2.7, carbs: 28, fat: 0.3)
        let component = MealSlotComponent(context: context, slot: slot, ingredient: ing, quantity: 200, unit: .gram)
        #expect(component.kind == .ingredient)
        #expect(component.displayName == "Basmati Rice (cooked)")
    }

    @Test("Component with neither relationship has kind .empty")
    func emptyKind() {
        let context = makeContext()
        let slot = makeSlot(in: context)
        let recipe = Recipe(context: context, title: "Detached", servings: 4)
        let component = MealSlotComponent(context: context, slot: slot, recipe: recipe)
        component.recipe = nil
        #expect(component.kind == .empty)
    }

    // MARK: - Macro aggregation: recipe component

    @Test("Recipe component scales macros by portionScale")
    func recipeComponentMacroScaling() {
        let context = makeContext()
        let slot = makeSlot(in: context, servingsPlanned: 2)
        let recipe = Recipe(context: context, title: "Test Curry", servings: 4)

        // Add an ingredient with known macros to the recipe so macrosPerServing returns non-nil
        let chicken = makeIngredient(in: context, name: "chicken", cal: 200, protein: 30, carbs: 0, fat: 8)
        let ri = RecipeIngredient(context: context, quantity: 800, unit: .gram, customName: "chicken")
        ri.ingredient = chicken
        recipe.addIngredient(ri)

        // Recipe macrosPerServing should be: 800g chicken = 1600 cal, 240g protein, 0 carbs, 64g fat
        // Per serving (4 servings): 400 cal, 60g protein, 0 carbs, 16g fat
        guard let perServing = recipe.macrosPerServing else {
            Issue.record("recipe.macrosPerServing returned nil")
            return
        }
        #expect(abs((perServing.calories ?? 0) - 400) < 0.01)

        // Half portion of recipe in the slot
        let component = MealSlotComponent(
            context: context,
            slot: slot,
            recipe: recipe,
            portionScale: 0.5
        )

        guard let oneSlotServing = component.macrosForOneSlotServing else {
            Issue.record("component.macrosForOneSlotServing returned nil")
            return
        }
        // 0.5 × 400 = 200 cal per slot serving
        #expect(abs((oneSlotServing.calories ?? 0) - 200) < 0.01)
        #expect(abs((oneSlotServing.protein ?? 0) - 30) < 0.01)
    }

    // MARK: - Macro aggregation: ingredient component

    @Test("Ingredient component scales macros by quantity in grams")
    func ingredientComponentMacroScaling() {
        let context = makeContext()
        let slot = makeSlot(in: context)
        let rice = makeIngredient(in: context, name: "Basmati Rice (cooked)", cal: 130, protein: 2.7, carbs: 28, fat: 0.3)

        // 200g of cooked basmati rice
        let component = MealSlotComponent(context: context, slot: slot, ingredient: rice, quantity: 200, unit: .gram)

        guard let macros = component.macrosForOneSlotServing else {
            Issue.record("component.macrosForOneSlotServing returned nil")
            return
        }
        // 200g × 130 cal/100g = 260 cal
        #expect(abs((macros.calories ?? 0) - 260) < 0.01)
        #expect(abs((macros.protein ?? 0) - 5.4) < 0.01)
        #expect(abs((macros.carbs ?? 0) - 56) < 0.01)
        #expect(abs((macros.fat ?? 0) - 0.6) < 0.01)
    }

    @Test("Ingredient component with no macro data returns nil")
    func ingredientComponentNoMacroData() {
        let context = makeContext()
        let slot = makeSlot(in: context)
        let mystery = Ingredient(
            context: context,
            name: "mystery",
            category: .other,
            defaultUnit: .gram
        )
        let component = MealSlotComponent(context: context, slot: slot, ingredient: mystery, quantity: 100, unit: .gram)
        #expect(component.macrosForOneSlotServing == nil)
    }

    // MARK: - MealSlot.plannedMacros aggregation

    @Test("MealSlot aggregates macros across multiple components and scales by servingsPlanned")
    func mealSlotAggregation() {
        let context = makeContext()
        let slot = makeSlot(in: context, servingsPlanned: 2)

        // Component 1: 200g rice — 260 cal per slot serving
        let rice = makeIngredient(in: context, name: "rice", cal: 130, protein: 2.7, carbs: 28, fat: 0.3)
        _ = MealSlotComponent(context: context, slot: slot, ingredient: rice, quantity: 200, unit: .gram, order: 0)

        // Component 2: 100g naan — 300 cal per slot serving
        let naan = makeIngredient(in: context, name: "naan", cal: 300, protein: 9, carbs: 50, fat: 8)
        _ = MealSlotComponent(context: context, slot: slot, ingredient: naan, quantity: 100, unit: .gram, order: 1)

        // Per slot serving: 260 + 300 = 560 cal
        // × 2 servingsPlanned = 1120 cal total
        guard let macros = slot.plannedMacros else {
            Issue.record("slot.plannedMacros returned nil")
            return
        }
        #expect(abs((macros.calories ?? 0) - 1120) < 0.01)
    }

    @Test("Empty slot with no components and no recipes returns nil macros (no-data, no judgement)")
    func emptySlotMacros() {
        let context = makeContext()
        let slot = makeSlot(in: context)
        slot.customMealName = "Friday: pub dinner"
        // No components, no recipes
        #expect(slot.plannedMacros == nil)
    }

    @Test("Legacy slot with only recipes (no components) still aggregates via the fallback path")
    func legacyRecipesFallback() {
        let context = makeContext()
        let slot = makeSlot(in: context, servingsPlanned: 2)

        // Create a recipe with macros
        let recipe = Recipe(context: context, title: "Old-school slot recipe", servings: 4)
        let chicken = makeIngredient(in: context, name: "chicken", cal: 200, protein: 30, carbs: 0, fat: 8)
        let ri = RecipeIngredient(context: context, quantity: 400, unit: .gram, customName: "chicken")
        ri.ingredient = chicken
        recipe.addIngredient(ri)

        // Add via the LEGACY recipes relationship (no components)
        slot.addToRecipes(recipe)

        // 400g × 200 cal / 100 = 800 cal total / 4 servings = 200 cal per serving
        // × 2 servingsPlanned = 400 cal
        #expect(slot.storedComponents.isEmpty)
        guard let macros = slot.plannedMacros else {
            Issue.record("legacy fallback returned nil")
            return
        }
        #expect(abs((macros.calories ?? 0) - 400) < 0.01)
    }
}
