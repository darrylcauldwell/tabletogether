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

    // MARK: - Stage 1: reconciling plateItems

    /// Builds a recipe whose per-serving calories are known.
    private func makeRecipe(in context: NSManagedObjectContext, title: String, servings: Int, chickenGrams: Double) -> Recipe {
        let recipe = Recipe(context: context, title: title, servings: Int(servings))
        let chicken = makeIngredient(in: context, name: "chicken-\(title)", cal: 200, protein: 30, carbs: 0, fat: 8)
        let ri = RecipeIngredient(context: context, quantity: chickenGrams, unit: .gram, customName: "chicken")
        ri.ingredient = chicken
        recipe.addIngredient(ri)
        return recipe
    }

    @Test("plateItems: a recipe read via legacy relationship and via a component give identical macros")
    func legacyAndComponentEquivalence() {
        let context = makeContext()
        let recipe = makeRecipe(in: context, title: "Equiv Curry", servings: 4, chickenGrams: 400)

        let legacySlot = makeSlot(in: context, servingsPlanned: 2)
        legacySlot.addToRecipes(recipe)

        let componentSlot = makeSlot(in: context, servingsPlanned: 2)
        _ = MealSlotComponent(context: context, slot: componentSlot, recipe: recipe, portionScale: 1.0)

        #expect(legacySlot.plateItems.count == 1)
        #expect(componentSlot.plateItems.count == 1)
        #expect(abs((legacySlot.plannedMacros?.calories ?? 0) - (componentSlot.plannedMacros?.calories ?? -1)) < 0.01)
    }

    @Test("plateItems unions un-migrated legacy recipes with components (no drop)")
    func plateItemsUnionsLegacyRecipes() {
        let context = makeContext()
        let slot = makeSlot(in: context, servingsPlanned: 1)
        let dhal = makeRecipe(in: context, title: "Dhal", servings: 4, chickenGrams: 400)   // 200 cal/serving
        let curry = makeRecipe(in: context, title: "Curry", servings: 4, chickenGrams: 400) // 200 cal/serving

        // Dhal as a component, Curry only in the legacy relationship (a merge/old-client case).
        _ = MealSlotComponent(context: context, slot: slot, recipe: dhal, portionScale: 1.0)
        slot.addToRecipes(curry)

        // Both must appear — union, not either/or.
        #expect(slot.plateItems.count == 2)
        #expect(abs((slot.plannedMacros?.calories ?? 0) - 400) < 0.01)
    }

    @Test("plateItems does not re-add a legacy recipe already represented by a component (no double-count)")
    func plateItemsNoDoubleCountAcrossRepresentations() {
        let context = makeContext()
        let slot = makeSlot(in: context, servingsPlanned: 1)
        let recipe = makeRecipe(in: context, title: "Both", servings: 4, chickenGrams: 400) // 200 cal/serving

        // Same recipe present in BOTH stores (the copy-week duplication case).
        _ = MealSlotComponent(context: context, slot: slot, recipe: recipe, portionScale: 1.0)
        slot.addToRecipes(recipe)

        #expect(slot.plateItems.count == 1)
        #expect(abs((slot.plannedMacros?.calories ?? 0) - 200) < 0.01)
    }

    @Test("plateItems dedupes duplicate component rows for the same entity (CloudKit dup safety)")
    func plateItemsDedupesDuplicateComponents() {
        let context = makeContext()
        let slot = makeSlot(in: context, servingsPlanned: 1)
        let recipe = makeRecipe(in: context, title: "Dup", servings: 4, chickenGrams: 400) // 200 cal/serving

        // Two component rows for the same recipe — as two devices' concurrent
        // migrate-on-touch would produce (MealSlotComponent is dedup-excluded).
        _ = MealSlotComponent(context: context, slot: slot, recipe: recipe, portionScale: 1.0, order: 0)
        _ = MealSlotComponent(context: context, slot: slot, recipe: recipe, portionScale: 1.0, order: 1)

        #expect(slot.storedComponents.count == 2)   // both rows persist...
        #expect(slot.plateItems.count == 1)          // ...but reads collapse them
        #expect(abs((slot.plannedMacros?.calories ?? 0) - 200) < 0.01) // not 400
    }

    @Test("isPlanned / isEmpty / displayTitle reflect component-only slots")
    func gatekeepersReadPlate() {
        let context = makeContext()
        let slot = makeSlot(in: context, servingsPlanned: 1)
        let recipe = makeRecipe(in: context, title: "Component Only", servings: 4, chickenGrams: 400)
        _ = MealSlotComponent(context: context, slot: slot, recipe: recipe, portionScale: 1.0)

        #expect(slot.recipesArray.isEmpty)       // nothing in the legacy relationship
        #expect(slot.isPlanned)                  // but the slot is planned via components
        #expect(!slot.isEmpty)
        #expect(slot.displayTitle == "Component Only")
    }

    // MARK: - Stage 3: write paths & migration

    private func makeUser(in context: NSManagedObjectContext) -> User {
        User(context: context, displayName: "Tester")
    }

    @Test("ensureComponentsMigrated converts legacy recipes to components, clears recipes, and is idempotent")
    func migrationIdempotent() {
        let context = makeContext()
        let slot = makeSlot(in: context, servingsPlanned: 1)
        let recipe = makeRecipe(in: context, title: "Legacy", servings: 4, chickenGrams: 400)
        slot.addToRecipes(recipe)

        #expect(slot.ensureComponentsMigrated() == true)
        #expect(slot.recipesArray.isEmpty)
        #expect(slot.storedComponents.count == 1)
        let idAfterFirst = slot.storedComponents.first?.id

        // Second call is a no-op (guard: legacy empty) and doesn't duplicate.
        #expect(slot.ensureComponentsMigrated() == false)
        #expect(slot.storedComponents.count == 1)
        #expect(slot.storedComponents.first?.id == idAfterFirst)
    }

    @Test("Migration uses deterministic ids so two contexts produce the same component id")
    func migrationDeterministicIDs() {
        let c1 = makeContext(); let c2 = makeContext()
        // Same slot id + same recipe id on two independent stores.
        let slotID = UUID(); let recipeID = UUID()
        func build(_ ctx: NSManagedObjectContext) -> MealSlot {
            let slot = MealSlot(context: ctx, id: slotID, dayOfWeek: .monday, mealType: .dinner)
            let r = Recipe(context: ctx, title: "R", servings: 4); r.id = recipeID
            slot.addToRecipes(r); slot.ensureComponentsMigrated()
            return slot
        }
        let a = build(c1); let b = build(c2)
        #expect(a.storedComponents.first?.id == b.storedComponents.first?.id)
    }

    @Test("addRecipe migrates a legacy slot then appends without double-counting")
    func addRecipeMigratesThenAppends() {
        let context = makeContext()
        let user = makeUser(in: context)
        let slot = makeSlot(in: context, servingsPlanned: 1)
        let first = makeRecipe(in: context, title: "First", servings: 4, chickenGrams: 400)  // 200/serving
        let second = makeRecipe(in: context, title: "Second", servings: 4, chickenGrams: 400) // 200/serving
        slot.addToRecipes(first)                 // legacy

        slot.addRecipe(second, by: user)         // triggers migration + append
        #expect(slot.recipesArray.isEmpty)
        #expect(slot.plateItems.count == 2)
        #expect(abs((slot.plannedMacros?.calories ?? 0) - 400) < 0.01) // 200 + 200, no double-count
    }

    @Test("addRecipe twice for the same recipe keeps one entry (one-entity invariant)")
    func addRecipeOneEntityInvariant() {
        let context = makeContext()
        let user = makeUser(in: context)
        let slot = makeSlot(in: context, servingsPlanned: 1)
        let recipe = makeRecipe(in: context, title: "Once", servings: 4, chickenGrams: 400)

        slot.addRecipe(recipe, by: user)
        slot.addRecipe(recipe, by: user)
        #expect(slot.plateItems.count == 1)
        #expect(abs((slot.plannedMacros?.calories ?? 0) - 200) < 0.01)
    }

    @Test("removeRecipe drops the right component when duplicate recipes are present, no resurrection")
    func removeRecipeMigrateExcept() {
        let context = makeContext()
        let user = makeUser(in: context)
        let slot = makeSlot(in: context, servingsPlanned: 1)
        let keep = makeRecipe(in: context, title: "Keep", servings: 4, chickenGrams: 400)
        let drop = makeRecipe(in: context, title: "Drop", servings: 4, chickenGrams: 400)
        slot.addToRecipes(keep)
        slot.addToRecipes(drop)

        slot.removeRecipe(drop, by: user)        // migrate-all-except-drop, then ensure gone
        #expect(slot.recipesArray.isEmpty)
        #expect(slot.plateItems.count == 1)
        #expect(slot.plateItems.first?.recipe?.id == keep.id)
        // No component was ever created for `drop`.
        #expect(!slot.storedComponents.contains { $0.recipe?.id == drop.id })
    }

    @Test("setCustomMeal and skip leave zero components")
    func customAndSkipClearComponents() {
        let context = makeContext()
        let user = makeUser(in: context)
        let slot = makeSlot(in: context, servingsPlanned: 1)
        let recipe = makeRecipe(in: context, title: "X", servings: 4, chickenGrams: 400)
        slot.addRecipe(recipe, by: user)
        #expect(slot.storedComponents.count == 1)

        slot.setCustomMeal("Pub dinner", by: user)
        #expect(slot.storedComponents.isEmpty)
        #expect(slot.recipesArray.isEmpty)
        #expect(slot.displayTitle == "Pub dinner")

        slot.addRecipe(recipe, by: user)
        slot.skip(by: user)
        #expect(slot.storedComponents.isEmpty)
        #expect(slot.isSkipped)
    }

    @Test("setPortionScale changes plannedMacros proportionally")
    func portionScaleAffectsMacros() {
        let context = makeContext()
        let user = makeUser(in: context)
        let slot = makeSlot(in: context, servingsPlanned: 1)
        let recipe = makeRecipe(in: context, title: "Half", servings: 4, chickenGrams: 400) // 200/serving
        slot.addRecipe(recipe, by: user)
        #expect(abs((slot.plannedMacros?.calories ?? 0) - 200) < 0.01)

        slot.setPortionScale(0.5, forRecipe: recipe, by: user)
        #expect(abs((slot.plannedMacros?.calories ?? 0) - 100) < 0.01)
    }

    @Test("copyFrom carries a legacy-only source into components and keeps recipes for old clients")
    func copyFromLegacySource() {
        let context = makeContext()
        let user = makeUser(in: context)
        let household = Household(context: context, name: "H")

        let sourcePlan = WeekPlan(context: context, weekStartDate: Date()); sourcePlan.household = household
        let sourceSlot = MealSlot(context: context, dayOfWeek: .monday, mealType: .dinner, servingsPlanned: 2)
        sourceSlot.weekPlan = sourcePlan; sourcePlan.addToSlots(sourceSlot)
        let recipe = makeRecipe(in: context, title: "Carried", servings: 4, chickenGrams: 400)
        sourceSlot.addToRecipes(recipe)   // legacy-only source

        let destPlan = WeekPlan(context: context, weekStartDate: Calendar.current.date(byAdding: .weekOfYear, value: 1, to: Date())!)
        destPlan.household = household
        destPlan.copyFrom(sourcePlan, by: user)

        let destSlot = destPlan.slotsArray.first { $0.dayOfWeek == .monday && $0.mealType == .dinner }
        #expect(destSlot != nil)
        #expect(destSlot?.plateItems.count == 1)
        #expect(destSlot?.plateItems.first?.recipe?.id == recipe.id)
        // Old-client visibility preserved: recipes relationship carried too.
        #expect(destSlot?.recipesArray.contains { $0.id == recipe.id } == true)
    }
}
