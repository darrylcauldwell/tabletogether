import Foundation
import CoreData
import SwiftUI

// MARK: - Import Result

struct JSONRecipeImportResult {
    let imported: Int
    let skipped: Int
    let errors: [String]
}

// MARK: - Import Errors

enum JSONRecipeImportError: LocalizedError {
    case invalidFile
    case decodingFailed(String)
    case noRecipesFound

    var errorDescription: String? {
        switch self {
        case .invalidFile: return "The file could not be read."
        case .decodingFailed(let detail): return "Could not decode recipe JSON: \(detail)"
        case .noRecipesFound: return "No recipes found in the file."
        }
    }
}

// MARK: - JSON Recipe Importer

/// Imports recipes from a `.json` file containing either a single `CodableRecipe`
/// or an array of `CodableRecipe`. Used by the curated recipe library workflow.
@MainActor
@Observable
final class JSONRecipeImporter {

    var isImporting = false
    var progress: String = ""
    var result: JSONRecipeImportResult?
    var errorMessage: String?

    /// Main entry point: import recipes from a `.json` file URL.
    func importRecipes(from url: URL, context: NSManagedObjectContext, household: Household?) async {
        isImporting = true
        progress = "Reading file..."
        errorMessage = nil
        result = nil

        do {
            // Access security-scoped resource (from file picker)
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }

            let data = try Data(contentsOf: url)
            let recipes = try decode(data: data)

            guard !recipes.isEmpty else {
                throw JSONRecipeImportError.noRecipesFound
            }

            result = importDecoded(recipes, context: context, household: household)
            progress = "Done"
        } catch {
            errorMessage = error.localizedDescription
        }

        isImporting = false
    }

    // MARK: - Decoding

    /// Decode either a single `CodableRecipe` object or an array of them.
    /// Exposed internally so tests can exercise the same path without a file URL.
    func decode(data: Data) throws -> [CodableRecipe] {
        let decoder = JSONDecoder()

        // Try array first
        if let array = try? decoder.decode([CodableRecipe].self, from: data) {
            return array
        }

        // Then a single recipe
        do {
            let single = try decoder.decode(CodableRecipe.self, from: data)
            return [single]
        } catch {
            throw JSONRecipeImportError.decodingFailed(error.localizedDescription)
        }
    }

    /// Insert decoded recipes into the context, deduping by case-insensitive title.
    /// Exposed internally so tests can drive imports without a file.
    func importDecoded(
        _ recipes: [CodableRecipe],
        context: NSManagedObjectContext,
        household: Household?
    ) -> JSONRecipeImportResult {
        // Fetch existing titles for duplicate detection
        let existingRequest = NSFetchRequest<Recipe>(entityName: "Recipe")
        let existingRecipes: [Recipe]
        do {
            existingRecipes = try context.fetch(existingRequest)
        } catch {
            AppLogger.swiftData.error("Failed to fetch existing recipes for duplicate check: \(error.localizedDescription)")
            existingRecipes = []
        }
        var existingTitles = Set(existingRecipes.map { $0.title.lowercased() })

        // One resolver instance for the whole import — prewarms the Ingredient
        // master cache once and reuses it across all recipes/ingredients in
        // this batch. See RecipeIngredientResolver for the dedup rules.
        let resolver = RecipeIngredientResolver(context: context, household: household)

        var imported = 0
        var skipped = 0
        var errors: [String] = []

        for (index, codable) in recipes.enumerated() {
            let trimmed = codable.title.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else {
                errors.append("Skipped recipe with no title")
                continue
            }

            progress = "Importing \(index + 1) of \(recipes.count)..."

            let key = trimmed.lowercased()
            if existingTitles.contains(key) {
                skipped += 1
                continue
            }

            codable.toRecipe(context: context, household: household, resolver: resolver)
            existingTitles.insert(key)
            imported += 1
        }

        do {
            try context.save()
        } catch {
            // Nothing was committed — roll back and report zero imported rather than a
            // false success count with the inserts still pending in the context.
            context.rollback()
            errors.append("Save failed: \(error.localizedDescription)")
            return JSONRecipeImportResult(imported: 0, skipped: skipped, errors: errors)
        }

        return JSONRecipeImportResult(imported: imported, skipped: skipped, errors: errors)
    }
}
