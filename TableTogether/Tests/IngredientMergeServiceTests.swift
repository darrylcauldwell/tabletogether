import Testing
import Foundation
import CoreData
@testable import TableTogetherLib

@MainActor
@Suite("IngredientMergeService Tests", .serialized)
struct IngredientMergeServiceTests {

    private func makeContext() -> (NSManagedObjectContext, Household) {
        let context = PersistenceController(inMemory: true).container.viewContext
        let household = Household(context: context, name: "Test")
        return (context, household)
    }

    /// Convenience: build an Ingredient attached to the household.
    private func makeIngredient(
        _ name: String,
        in context: NSManagedObjectContext,
        household: Household,
        aliases: [String] = []
    ) -> Ingredient {
        let ingredient = Ingredient(context: context, name: name)
        ingredient.household = household
        for alias in aliases {
            ingredient.addAlias(alias)
        }
        return ingredient
    }

    /// Convenience: attach a RecipeIngredient referencing this Ingredient.
    @discardableResult
    private func attachRecipeIngredient(
        to ingredient: Ingredient,
        in context: NSManagedObjectContext,
        recipe: Recipe? = nil
    ) -> RecipeIngredient {
        let r = recipe ?? Recipe(context: context, title: "Test Recipe")
        if recipe == nil {
            r.household = ingredient.household
        }
        let ri = RecipeIngredient(
            context: context,
            quantity: 1,
            unit: .gram,
            order: 0,
            customName: ingredient.name
        )
        ri.recipe = r
        ri.ingredient = ingredient
        return ri
    }

    private func ingredientCount(in context: NSManagedObjectContext) -> Int {
        let request = NSFetchRequest<Ingredient>(entityName: "Ingredient")
        return (try? context.count(for: request)) ?? 0
    }

    // MARK: - Basic merge

    @Test("Merging source into canonical deletes source and reassigns FKs")
    func basicMerge() throws {
        let (context, household) = makeContext()
        let source = makeIngredient("scallions", in: context, household: household)
        let canonical = makeIngredient("spring onion", in: context, household: household)
        attachRecipeIngredient(to: source, in: context)
        attachRecipeIngredient(to: source, in: context)
        try context.save()

        #expect(ingredientCount(in: context) == 2)

        let service = IngredientMergeService()
        let preview = try service.merge(source: source, into: canonical)

        #expect(preview.recipeIngredientCount == 2)
        #expect(ingredientCount(in: context) == 1)
        #expect(source.isDeleted || source.managedObjectContext == nil)

        // The two RecipeIngredient rows should now point at canonical
        let allRI = try context.fetch(NSFetchRequest<RecipeIngredient>(entityName: "RecipeIngredient"))
        #expect(allRI.count == 2)
        for ri in allRI {
            #expect(ri.ingredient === canonical)
        }
    }

    // MARK: - Alias preservation

    @Test("Source name becomes an alias on canonical")
    func sourceNameBecomesAlias() throws {
        let (context, household) = makeContext()
        let source = makeIngredient("scallions", in: context, household: household)
        let canonical = makeIngredient("spring onion", in: context, household: household)

        let service = IngredientMergeService()
        try service.merge(source: source, into: canonical)

        #expect(canonical.userAliasesList.contains("scallions"))
    }

    @Test("Source aliases transfer to canonical")
    func sourceAliasesTransfer() throws {
        let (context, household) = makeContext()
        let source = makeIngredient(
            "scallions",
            in: context,
            household: household,
            aliases: ["green onion", "salad onion"]
        )
        let canonical = makeIngredient("spring onion", in: context, household: household)

        let service = IngredientMergeService()
        try service.merge(source: source, into: canonical)

        #expect(canonical.userAliasesList.contains("scallions"))
        #expect(canonical.userAliasesList.contains("green onion"))
        #expect(canonical.userAliasesList.contains("salad onion"))
    }

    @Test("Existing aliases on canonical are preserved and not duplicated")
    func canonicalAliasesPreservedNoDup() throws {
        let (context, household) = makeContext()
        let source = makeIngredient(
            "scallions",
            in: context,
            household: household,
            aliases: ["green onion"]
        )
        let canonical = makeIngredient(
            "spring onion",
            in: context,
            household: household,
            aliases: ["green onion", "fresh onion"]  // already has "green onion"
        )

        let service = IngredientMergeService()
        try service.merge(source: source, into: canonical)

        // Canonical's existing aliases preserved
        #expect(canonical.userAliasesList.contains("green onion"))
        #expect(canonical.userAliasesList.contains("fresh onion"))
        // Source's name added
        #expect(canonical.userAliasesList.contains("scallions"))
        // No duplication of "green onion"
        let count = canonical.userAliasesList.filter { $0 == "green onion" }.count
        #expect(count == 1)
    }

    @Test("Source name equal to canonical name is not added as alias")
    func sourceNameEqualToCanonicalNotAdded() throws {
        let (context, household) = makeContext()
        let source = makeIngredient("Tomato", in: context, household: household)
        let canonical = makeIngredient("tomato", in: context, household: household)

        let service = IngredientMergeService()
        try service.merge(source: source, into: canonical)

        // Both normalise to "tomato" — should NOT be added to aliases
        #expect(!canonical.userAliasesList.contains("tomato"))
    }

    // MARK: - All FK types

    @Test("Merge reassigns RecipeIngredient, MealSlotComponent, and GroceryItem FKs")
    func allFKTypesReassigned() throws {
        let (context, household) = makeContext()
        let source = makeIngredient("source", in: context, household: household)
        let canonical = makeIngredient("canonical", in: context, household: household)

        // RecipeIngredient
        attachRecipeIngredient(to: source, in: context)

        // GroceryItem
        let grocery = GroceryItem(
            context: context,
            ingredient: source,
            quantity: 1,
            unit: .gram
        )
        _ = grocery

        // MealSlotComponent
        let weekPlan = WeekPlan(context: context)
        weekPlan.household = household
        let slot = MealSlot(context: context)
        slot.weekPlan = weekPlan
        let component = MealSlotComponent(context: context)
        component.slot = slot
        component.ingredient = source

        try context.save()

        let service = IngredientMergeService()
        let preview = try service.merge(source: source, into: canonical)

        #expect(preview.recipeIngredientCount == 1)
        #expect(preview.groceryItemCount == 1)
        #expect(preview.mealSlotComponentCount == 1)
        #expect(preview.totalReassignments == 3)

        // All three should now reference canonical
        let allRI = try context.fetch(NSFetchRequest<RecipeIngredient>(entityName: "RecipeIngredient"))
        #expect(allRI.first?.ingredient === canonical)
        let allGI = try context.fetch(NSFetchRequest<GroceryItem>(entityName: "GroceryItem"))
        #expect(allGI.first?.ingredient === canonical)
        let allMSC = try context.fetch(NSFetchRequest<MealSlotComponent>(entityName: "MealSlotComponent"))
        #expect(allMSC.first?.ingredient === canonical)
    }

    // MARK: - Error cases

    @Test("Merging an ingredient into itself throws sameRecord")
    func sameRecordError() throws {
        let (context, household) = makeContext()
        let only = makeIngredient("solo", in: context, household: household)

        let service = IngredientMergeService()
        #expect(throws: IngredientMergeService.MergeError.self) {
            try service.merge(source: only, into: only)
        }
    }

    @Test("Merging across households throws mismatchedHousehold")
    func mismatchedHouseholdError() throws {
        let context = PersistenceController(inMemory: true).container.viewContext
        let householdA = Household(context: context, name: "A")
        let householdB = Household(context: context, name: "B")
        let inA = makeIngredient("foo", in: context, household: householdA)
        let inB = makeIngredient("foo", in: context, household: householdB)

        let service = IngredientMergeService()
        #expect(throws: IngredientMergeService.MergeError.self) {
            try service.merge(source: inA, into: inB)
        }
    }

    // MARK: - Preview

    @Test("Preview returns counts without modifying state")
    func previewIsNonMutating() throws {
        let (context, household) = makeContext()
        let source = makeIngredient(
            "source",
            in: context,
            household: household,
            aliases: ["alt1", "alt2"]
        )
        let canonical = makeIngredient("canonical", in: context, household: household)
        attachRecipeIngredient(to: source, in: context)
        attachRecipeIngredient(to: source, in: context)
        try context.save()

        let service = IngredientMergeService()
        let preview = service.preview(source: source, into: canonical)

        #expect(preview.sourceName == "source")
        #expect(preview.canonicalName == "canonical")
        #expect(preview.recipeIngredientCount == 2)
        // source name + 2 aliases = 3 transfers
        #expect(preview.aliasesToTransfer.count == 3)

        // State unchanged: both ingredients still present, no aliases on canonical
        #expect(ingredientCount(in: context) == 2)
        #expect(canonical.userAliasesList.isEmpty)
    }
}
