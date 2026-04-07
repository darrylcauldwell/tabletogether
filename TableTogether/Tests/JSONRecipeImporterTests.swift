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
}
