import Testing
import CoreData
@testable import TableTogetherLib

@MainActor
struct SuggestionMemoryTests {

    private func makeContext() -> NSManagedObjectContext {
        PersistenceController(inMemory: true).viewContext
    }

    @Test("markAsCooked creates a SuggestionMemory and records the cooking")
    func cookingCreatesMemory() {
        let context = makeContext()
        let recipe = Recipe(context: context, title: "Test", servings: 2)

        recipe.markAsCooked()

        let memory = SuggestionMemory.findOrCreate(for: recipe, in: context)
        #expect(memory.timesCooked == 1)
        #expect(memory.recipe?.id == recipe.id)
        #expect(memory.lastCookedDate != nil)
    }

    @Test("Cooking the same recipe twice reuses one memory and increments")
    func cookingTwiceReusesMemory() {
        let context = makeContext()
        let recipe = Recipe(context: context, title: "Test", servings: 2)

        recipe.markAsCooked()
        recipe.markAsCooked()

        let request = NSFetchRequest<SuggestionMemory>(entityName: "SuggestionMemory")
        request.predicate = NSPredicate(format: "recipe == %@", recipe)
        let memories = (try? context.fetch(request)) ?? []
        #expect(memories.count == 1)
        #expect(memories.first?.timesCooked == 2)
    }

    @Test("Familiarity advances past .new once a recipe has been cooked")
    func familiarityAdvances() {
        let context = makeContext()
        let recipe = Recipe(context: context, title: "Test", servings: 2)

        recipe.markAsCooked()

        let memory = SuggestionMemory.findOrCreate(for: recipe, in: context)
        #expect(memory.householdFamiliarity == .tried) // 1...2 cooks -> .tried
    }
}
