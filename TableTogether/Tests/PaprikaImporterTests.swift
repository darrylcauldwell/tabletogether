import Testing
import Foundation
import CoreData
@testable import TableTogetherLib

@MainActor
@Suite("PaprikaImporter Tests", .serialized)
struct PaprikaImporterTests {

    /// Build a fresh in-memory Core Data context for each test.
    private func makeContext() -> NSManagedObjectContext {
        PersistenceController(inMemory: true).container.viewContext
    }

    /// Helper to construct a PaprikaRecipeData with sensible defaults — only
    /// set the fields each test cares about and rely on nil for everything else.
    private func makeRecipeData(
        name: String = "Test Recipe",
        ingredients: String? = nil,
        directions: String? = nil,
        servings: String? = nil,
        prep_time: String? = nil,
        cook_time: String? = nil,
        notes: String? = nil,
        source: String? = nil,
        source_url: String? = nil,
        photo_data: String? = nil,
        on_favorites: Int? = nil,
        categories: [String]? = nil,
        description: String? = nil
    ) -> PaprikaRecipeData {
        PaprikaRecipeData(
            uid: nil,
            name: name,
            ingredients: ingredients,
            directions: directions,
            servings: servings,
            prep_time: prep_time,
            cook_time: cook_time,
            notes: notes,
            source: source,
            source_url: source_url,
            nutritional_info: nil,
            photo_data: photo_data,
            on_favorites: on_favorites,
            categories: categories,
            rating: nil,
            difficulty: nil,
            description: description
        )
    }

    // MARK: - Cookbook attribution (Phase 2 of #59)

    @Test("Paprika source field populates Recipe.cookbook")
    func sourceFieldPopulatesCookbook() {
        let context = makeContext()
        let importer = PaprikaImporter()
        let data = makeRecipeData(
            name: "Lamb Rogan Josh",
            source: "Madhur Jaffrey's Curry Nation"
        )

        let recipe = importer.buildRecipe(from: data, context: context)

        #expect(recipe.cookbook == "Madhur Jaffrey's Curry Nation")
        #expect(recipe.title == "Lamb Rogan Josh")
    }

    @Test("Paprika source and source_url are stored independently")
    func sourceAndSourceURLCoexist() {
        let context = makeContext()
        let importer = PaprikaImporter()
        let data = makeRecipeData(
            name: "BBC Lemon Drizzle",
            source: "BBC Good Food",
            source_url: "https://www.bbcgoodfood.com/recipes/lemon-drizzle-cake"
        )

        let recipe = importer.buildRecipe(from: data, context: context)

        #expect(recipe.cookbook == "BBC Good Food")
        #expect(recipe.sourceURL?.absoluteString == "https://www.bbcgoodfood.com/recipes/lemon-drizzle-cake")
    }

    @Test("Missing source field leaves cookbook nil")
    func missingSourceLeavesCookbookNil() {
        let context = makeContext()
        let importer = PaprikaImporter()
        let data = makeRecipeData(name: "Untitled Recipe")

        let recipe = importer.buildRecipe(from: data, context: context)

        #expect(recipe.cookbook == nil)
    }

    @Test("Empty source string leaves cookbook nil")
    func emptySourceLeavesCookbookNil() {
        let context = makeContext()
        let importer = PaprikaImporter()
        let data = makeRecipeData(name: "Bare Recipe", source: "")

        let recipe = importer.buildRecipe(from: data, context: context)

        #expect(recipe.cookbook == nil)
    }

    @Test("Whitespace-only source string leaves cookbook nil")
    func whitespaceOnlySourceLeavesCookbookNil() {
        let context = makeContext()
        let importer = PaprikaImporter()
        let data = makeRecipeData(name: "Bare Recipe", source: "   \n  ")

        let recipe = importer.buildRecipe(from: data, context: context)

        #expect(recipe.cookbook == nil)
    }

    @Test("Source string is trimmed before storing")
    func sourceIsTrimmed() {
        let context = makeContext()
        let importer = PaprikaImporter()
        let data = makeRecipeData(
            name: "Trimmed Recipe",
            source: "  Cook's Illustrated  "
        )

        let recipe = importer.buildRecipe(from: data, context: context)

        #expect(recipe.cookbook == "Cook's Illustrated")
    }

    // MARK: - Existing field mapping (regression coverage)

    @Test("Basic Paprika fields round-trip into Recipe")
    func basicFieldsRoundTrip() {
        let context = makeContext()
        let importer = PaprikaImporter()
        let data = makeRecipeData(
            name: "Quick Curry",
            ingredients: "1 tbsp oil\n1 onion\n2 cloves garlic\n400g chickpeas",
            directions: "Heat oil.\nFry onion.\nAdd everything else.",
            servings: "Serves 4",
            prep_time: "10 min",
            cook_time: "25 minutes",
            on_favorites: 1,
            categories: ["Vegetarian", "Indian"]
        )

        let recipe = importer.buildRecipe(from: data, context: context)

        #expect(recipe.title == "Quick Curry")
        #expect(recipe.servings == 4)
        #expect(recipe.prepTimeMinutes == 10)
        #expect(recipe.cookTimeMinutes == 25)
        #expect(recipe.isFavorite == true)
        #expect(recipe.tagsList.contains("vegetarian"))
        #expect(recipe.tagsList.contains("indian"))
        #expect(recipe.instructionsList.count == 3)
    }
}
