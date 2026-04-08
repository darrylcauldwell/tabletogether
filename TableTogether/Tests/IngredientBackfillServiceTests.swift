import Testing
import Foundation
import CoreData
@testable import TableTogetherLib

@MainActor
@Suite("IngredientBackfillService Tests", .serialized)
struct IngredientBackfillServiceTests {

    private func makeContext() -> (NSManagedObjectContext, Household) {
        let context = PersistenceController(inMemory: true).container.viewContext
        let household = Household(context: context, name: "Test")
        return (context, household)
    }

    /// Build a Recipe with N RecipeIngredient rows (no Ingredient master FK).
    /// Mirrors the state of pre-Phase-4 imports — RecipeIngredient.customName
    /// is set but RecipeIngredient.ingredient is nil.
    @discardableResult
    private func makeRecipe(
        title: String,
        ingredientNames: [String],
        in context: NSManagedObjectContext,
        household: Household
    ) -> Recipe {
        let recipe = Recipe(context: context, title: title)
        recipe.household = household
        for (index, name) in ingredientNames.enumerated() {
            let ri = RecipeIngredient(
                context: context,
                quantity: 1,
                unit: .gram,
                order: index,
                customName: name
            )
            ri.recipe = recipe
        }
        return recipe
    }

    private func ingredientCount(in context: NSManagedObjectContext) -> Int {
        let request = NSFetchRequest<Ingredient>(entityName: "Ingredient")
        return (try? context.count(for: request)) ?? 0
    }

    // MARK: - Basic backfill

    @Test("Backfill links every unlinked RecipeIngredient")
    func backfillLinksUnlinked() throws {
        let (context, household) = makeContext()
        makeRecipe(title: "A", ingredientNames: ["tomato", "basil", "olive oil"], in: context, household: household)
        try context.save()

        let service = IngredientBackfillService()
        let result = service.run(context: context, household: household)

        #expect(result.processed == 3)
        #expect(result.linked == 3)
        #expect(result.alreadyLinked == 0)
        #expect(result.mastersCreated == 3)
        #expect(ingredientCount(in: context) == 3)

        // Verify every row got a FK
        let allRI = try context.fetch(NSFetchRequest<RecipeIngredient>(entityName: "RecipeIngredient"))
        for ri in allRI {
            #expect(ri.ingredient != nil)
        }
    }

    @Test("Backfill collapses duplicates by normalised name")
    func backfillCollapsesDuplicates() throws {
        let (context, household) = makeContext()
        makeRecipe(title: "A", ingredientNames: ["tomato", "Tomato", "TOMATO", "  tomato  "], in: context, household: household)
        makeRecipe(title: "B", ingredientNames: ["tomato"], in: context, household: household)
        try context.save()

        let service = IngredientBackfillService()
        let result = service.run(context: context, household: household)

        #expect(result.processed == 5)
        #expect(result.linked == 5)
        // All 5 rows collapse to ONE master record
        #expect(result.mastersCreated == 1)
        #expect(ingredientCount(in: context) == 1)
    }

    // MARK: - Idempotence

    @Test("Backfill is idempotent — second run is a no-op")
    func backfillIsIdempotent() throws {
        let (context, household) = makeContext()
        makeRecipe(title: "A", ingredientNames: ["tomato", "basil"], in: context, household: household)
        try context.save()

        let service = IngredientBackfillService()
        let firstRun = service.run(context: context, household: household)
        #expect(firstRun.linked == 2)
        #expect(firstRun.alreadyLinked == 0)

        let secondRun = service.run(context: context, household: household)
        #expect(secondRun.processed == 2)
        #expect(secondRun.linked == 0)
        #expect(secondRun.alreadyLinked == 2)
        #expect(secondRun.mastersCreated == 0)
        // No new ingredients should have been created
        #expect(ingredientCount(in: context) == 2)
    }

    @Test("Backfill picks up existing aliases when resolving")
    func backfillUsesExistingAliases() throws {
        let (context, household) = makeContext()

        // Pre-create a master with an alias
        let canonical = Ingredient(context: context, name: "spring onion")
        canonical.household = household
        canonical.addAlias("scallion")

        // Create unlinked recipe with the alias name
        makeRecipe(title: "A", ingredientNames: ["scallion"], in: context, household: household)
        try context.save()

        let service = IngredientBackfillService()
        let result = service.run(context: context, household: household)

        #expect(result.linked == 1)
        #expect(result.mastersCreated == 0) // Should reuse the existing canonical, not create new
        #expect(ingredientCount(in: context) == 1)

        let ri = try context.fetch(NSFetchRequest<RecipeIngredient>(entityName: "RecipeIngredient")).first
        #expect(ri?.ingredient === canonical)
    }

    // MARK: - Empty cases

    @Test("Backfill of empty library returns zero processed")
    func backfillEmptyLibrary() throws {
        let (context, household) = makeContext()
        let service = IngredientBackfillService()
        let result = service.run(context: context, household: household)
        #expect(result.processed == 0)
        #expect(result.linked == 0)
        #expect(result.mastersCreated == 0)
    }

    @Test("Backfill skips rows with empty customName")
    func backfillSkipsEmptyNames() throws {
        let (context, household) = makeContext()
        let recipe = Recipe(context: context, title: "A")
        recipe.household = household
        let ri = RecipeIngredient(context: context, quantity: 1, unit: .gram, order: 0, customName: "")
        ri.recipe = recipe
        try context.save()

        let service = IngredientBackfillService()
        let result = service.run(context: context, household: household)

        #expect(result.processed == 1)
        #expect(result.linked == 0)
        #expect(result.skippedEmptyName == 1)
    }
}
