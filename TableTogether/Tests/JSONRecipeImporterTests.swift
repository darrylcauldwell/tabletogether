import Testing
import Foundation
import CoreData
@testable import TableTogetherLib

@MainActor
@Suite("JSONRecipeImporter Tests", .serialized)
struct JSONRecipeImporterTests {

    /// Build a fresh in-memory Core Data context for each test.
    private func makeContext() -> NSManagedObjectContext {
        PersistenceController(inMemory: true).container.viewContext
    }

    private func sampleRecipeJSON(title: String = "Lemon Chicken Pasta") -> Data {
        let json = """
        {
          "title": "\(title)",
          "summary": "A bright weeknight dinner.",
          "sourceURL": null,
          "servings": 4,
          "prepTimeMinutes": 10,
          "cookTimeMinutes": 15,
          "instructions": ["Boil pasta.", "Make sauce.", "Combine."],
          "tags": ["weeknight", "pasta"],
          "suggestedArchetypes": [],
          "ingredients": [
            {
              "name": "spaghetti",
              "quantity": 400,
              "unit": "gram",
              "preparationNote": null,
              "isOptional": false
            },
            {
              "name": "lemon",
              "quantity": 1,
              "unit": "piece",
              "preparationNote": "zested and juiced",
              "isOptional": false
            }
          ],
          "isFavorite": false,
          "imageDataBase64": null
        }
        """
        return Data(json.utf8)
    }

    // MARK: - Decode

    @Test("Decodes a single recipe object")
    func decodesSingleRecipe() throws {
        let importer = JSONRecipeImporter()
        let recipes = try importer.decode(data: sampleRecipeJSON())
        #expect(recipes.count == 1)
        #expect(recipes[0].title == "Lemon Chicken Pasta")
        #expect(recipes[0].servings == 4)
        #expect(recipes[0].ingredients.count == 2)
    }

    // MARK: - Resolver integration (Phase 4 of #59)

    /// Helper to count Ingredient master records in a context.
    private func ingredientCount(in context: NSManagedObjectContext) -> Int {
        let request = NSFetchRequest<Ingredient>(entityName: "Ingredient")
        return (try? context.count(for: request)) ?? 0
    }

    @Test("Importing a recipe creates linked Ingredient master records")
    func importCreatesIngredientMasters() throws {
        let context = makeContext()
        let household = Household(context: context, name: "Test")
        let importer = JSONRecipeImporter()
        let recipes = try importer.decode(data: sampleRecipeJSON())
        let result = importer.importDecoded(recipes, context: context, household: household)

        #expect(result.imported == 1)
        // Two distinct ingredients in the sample (spaghetti, lemon)
        #expect(ingredientCount(in: context) == 2)

        // All RecipeIngredient rows should have the FK populated
        let allRI = try context.fetch(NSFetchRequest<RecipeIngredient>(entityName: "RecipeIngredient"))
        #expect(allRI.count == 2)
        for ri in allRI {
            #expect(ri.ingredient != nil)
        }
    }

    @Test("Duplicate ingredient strings within one import collapse to one master")
    func duplicateIngredientsCollapse() throws {
        let context = makeContext()
        let household = Household(context: context, name: "Test")
        let importer = JSONRecipeImporter()

        // Two recipes that share an ingredient name
        let json = """
        [
          {
            "title": "Recipe One",
            "summary": null, "sourceURL": null, "servings": 2,
            "prepTimeMinutes": 5, "cookTimeMinutes": 5,
            "instructions": [], "tags": [], "suggestedArchetypes": [],
            "ingredients": [
              {"name": "tomato", "quantity": 2, "unit": "piece", "preparationNote": null, "isOptional": false}
            ],
            "isFavorite": false, "imageDataBase64": null
          },
          {
            "title": "Recipe Two",
            "summary": null, "sourceURL": null, "servings": 2,
            "prepTimeMinutes": 5, "cookTimeMinutes": 5,
            "instructions": [], "tags": [], "suggestedArchetypes": [],
            "ingredients": [
              {"name": "Tomato", "quantity": 1, "unit": "piece", "preparationNote": null, "isOptional": false},
              {"name": "TOMATO", "quantity": 3, "unit": "piece", "preparationNote": null, "isOptional": false}
            ],
            "isFavorite": false, "imageDataBase64": null
          }
        ]
        """
        let recipes = try importer.decode(data: Data(json.utf8))
        let result = importer.importDecoded(recipes, context: context, household: household)

        #expect(result.imported == 2)
        // All three "tomato" / "Tomato" / "TOMATO" should collapse to ONE master
        #expect(ingredientCount(in: context) == 1)
    }

    @Test("Re-importing a recipe with the same ingredients reuses existing masters")
    func reimportReusesMasters() throws {
        let context = makeContext()
        let household = Household(context: context, name: "Test")
        let importer = JSONRecipeImporter()

        // First import creates the masters
        let recipes1 = try importer.decode(data: sampleRecipeJSON(title: "First"))
        _ = importer.importDecoded(recipes1, context: context, household: household)
        #expect(ingredientCount(in: context) == 2)

        // Second import (different recipe title, same ingredients) should reuse
        let recipes2 = try importer.decode(data: sampleRecipeJSON(title: "Second"))
        _ = importer.importDecoded(recipes2, context: context, household: household)
        #expect(ingredientCount(in: context) == 2)

        // Both recipes should have RecipeIngredient rows linked to the SAME masters
        let allRecipes = try context.fetch(NSFetchRequest<Recipe>(entityName: "Recipe"))
        #expect(allRecipes.count == 2)
        for recipe in allRecipes {
            for ri in recipe.recipeIngredientsArray {
                #expect(ri.ingredient != nil)
            }
        }
    }

    @Test("Decodes an array of recipes")
    func decodesArrayOfRecipes() throws {
        let importer = JSONRecipeImporter()
        let json = "[\(String(data: sampleRecipeJSON(title: "A"), encoding: .utf8)!),\(String(data: sampleRecipeJSON(title: "B"), encoding: .utf8)!)]"
        let recipes = try importer.decode(data: Data(json.utf8))
        #expect(recipes.count == 2)
        #expect(recipes.map(\.title).sorted() == ["A", "B"])
    }

    @Test("Malformed JSON throws decodingFailed")
    func malformedJSONThrows() {
        let importer = JSONRecipeImporter()
        let bad = Data("{ not valid json".utf8)
        #expect(throws: JSONRecipeImportError.self) {
            try importer.decode(data: bad)
        }
    }

    // MARK: - Import

    @Test("Imports a single recipe into the context")
    func importsSingleRecipe() throws {
        let context = makeContext()
        let importer = JSONRecipeImporter()
        let recipes = try importer.decode(data: sampleRecipeJSON())

        let result = importer.importDecoded(recipes, context: context, household: nil)

        #expect(result.imported == 1)
        #expect(result.skipped == 0)
        #expect(result.errors.isEmpty)

        let fetched = try context.fetch(NSFetchRequest<Recipe>(entityName: "Recipe"))
        #expect(fetched.count == 1)
        #expect(fetched.first?.title == "Lemon Chicken Pasta")
        #expect(fetched.first?.servings == 4)
        #expect(fetched.first?.recipeIngredientsArray.count == 2)
    }

    @Test("Skips duplicate by case-insensitive title")
    func skipsDuplicateTitle() throws {
        let context = makeContext()
        let importer = JSONRecipeImporter()

        let first = try importer.decode(data: sampleRecipeJSON(title: "Pasta Bake"))
        _ = importer.importDecoded(first, context: context, household: nil)

        let second = try importer.decode(data: sampleRecipeJSON(title: "PASTA BAKE"))
        let result = importer.importDecoded(second, context: context, household: nil)

        #expect(result.imported == 0)
        #expect(result.skipped == 1)

        let fetched = try context.fetch(NSFetchRequest<Recipe>(entityName: "Recipe"))
        #expect(fetched.count == 1)
    }

    @Test("Dedupes within a single import batch")
    func dedupesWithinBatch() throws {
        let context = makeContext()
        let importer = JSONRecipeImporter()

        let json = "[\(String(data: sampleRecipeJSON(title: "Stew"), encoding: .utf8)!),\(String(data: sampleRecipeJSON(title: "stew"), encoding: .utf8)!)]"
        let recipes = try importer.decode(data: Data(json.utf8))
        let result = importer.importDecoded(recipes, context: context, household: nil)

        #expect(result.imported == 1)
        #expect(result.skipped == 1)
    }

    @Test("Empty title is reported as an error and not imported")
    func emptyTitleErrors() throws {
        let context = makeContext()
        let importer = JSONRecipeImporter()
        let recipes = try importer.decode(data: sampleRecipeJSON(title: "   "))

        let result = importer.importDecoded(recipes, context: context, household: nil)

        #expect(result.imported == 0)
        #expect(result.skipped == 0)
        #expect(result.errors.count == 1)
    }

    @Test("Round-trips through CodableRecipe export and reimport")
    func roundTripExportImport() throws {
        let context = makeContext()
        let importer = JSONRecipeImporter()

        // 1. Import the seed recipe
        let seed = try importer.decode(data: sampleRecipeJSON(title: "Risotto"))
        _ = importer.importDecoded(seed, context: context, household: nil)

        // 2. Export the imported recipe back to JSON via CodableRecipe
        let inserted = try context.fetch(NSFetchRequest<Recipe>(entityName: "Recipe")).first!
        let exported = CodableRecipe(from: inserted)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let exportData = try encoder.encode(exported)

        // 3. Decoding the exported JSON should produce a CodableRecipe equivalent to the seed
        let redecoded = try importer.decode(data: exportData)
        #expect(redecoded.count == 1)
        #expect(redecoded[0].title == "Risotto")
        #expect(redecoded[0].servings == 4)
        #expect(redecoded[0].ingredients.count == 2)
        #expect(redecoded[0].ingredients[0].name == "spaghetti")
        #expect(redecoded[0].ingredients[1].preparationNote == "zested and juiced")
    }

    @Test("Cookbook field round-trips through import and export")
    func cookbookFieldRoundTrip() throws {
        let context = makeContext()
        let importer = JSONRecipeImporter()

        let json = """
        {
          "title": "Cookbook Test",
          "summary": "Has a cookbook.",
          "sourceURL": null,
          "cookbook": "Curry Easy",
          "servings": 2,
          "prepTimeMinutes": 0,
          "cookTimeMinutes": 0,
          "instructions": ["Cook it."],
          "tags": [],
          "suggestedArchetypes": [],
          "ingredients": [],
          "isFavorite": false,
          "imageDataBase64": null
        }
        """
        let decoded = try importer.decode(data: Data(json.utf8))
        _ = importer.importDecoded(decoded, context: context, household: nil)

        let fetched = try context.fetch(NSFetchRequest<Recipe>(entityName: "Recipe")).first!
        #expect(fetched.cookbook == "Curry Easy")

        // Round-trip through CodableRecipe should preserve the cookbook
        let exported = CodableRecipe(from: fetched)
        #expect(exported.cookbook == "Curry Easy")
    }

    @Test("Recipe with no cookbook field decodes with nil cookbook")
    func recipeWithoutCookbook() throws {
        let importer = JSONRecipeImporter()
        // sampleRecipeJSON intentionally has no cookbook field
        let decoded = try importer.decode(data: sampleRecipeJSON(title: "No Book"))
        #expect(decoded[0].cookbook == nil)
    }

    @Test("imageURL field round-trips through import and export")
    func imageURLRoundTrip() throws {
        let context = makeContext()
        let importer = JSONRecipeImporter()

        let json = """
        {
          "title": "Image Test",
          "summary": "Has an image URL.",
          "sourceURL": null,
          "cookbook": null,
          "imageURL": "https://example.com/thumbnail.jpg",
          "servings": 2,
          "prepTimeMinutes": 0,
          "cookTimeMinutes": 0,
          "instructions": ["Cook it."],
          "tags": [],
          "suggestedArchetypes": [],
          "ingredients": [],
          "isFavorite": false,
          "imageDataBase64": null
        }
        """
        let decoded = try importer.decode(data: Data(json.utf8))
        _ = importer.importDecoded(decoded, context: context, household: nil)

        let fetched = try context.fetch(NSFetchRequest<Recipe>(entityName: "Recipe")).first!
        #expect(fetched.imageURL?.absoluteString == "https://example.com/thumbnail.jpg")

        // Round-trip through CodableRecipe should preserve the URL
        let exported = CodableRecipe(from: fetched)
        #expect(exported.imageURL == "https://example.com/thumbnail.jpg")
    }

    @Test("Recipe with no imageURL decodes with nil imageURL")
    func recipeWithoutImageURL() throws {
        let importer = JSONRecipeImporter()
        // sampleRecipeJSON intentionally has no imageURL field
        let decoded = try importer.decode(data: sampleRecipeJSON(title: "No Image"))
        #expect(decoded[0].imageURL == nil)
    }
}
