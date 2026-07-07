import Foundation
import CoreData
import SwiftUI

// MARK: - Import Result

struct FoodItemImportResult {
    let imported: Int
    let skipped: Int
    let errors: [String]
}

// MARK: - Import Errors

enum FoodItemImportError: LocalizedError {
    case invalidFile
    case decodingFailed(String)
    case noFoodItemsFound

    var errorDescription: String? {
        switch self {
        case .invalidFile: return "The file could not be read."
        case .decodingFailed(let detail): return "Could not decode food item JSON: \(detail)"
        case .noFoodItemsFound: return "No food items found in the file."
        }
    }
}

// MARK: - FoodItem Importer
//
// Imports a hand-curated JSON file containing either a single CodableFoodItem
// or an array of them. Mirrors JSONRecipeImporter exactly in shape so the
// Settings UI affordance is symmetric (#59 Phase 7.5).
//
// **Dedup strategy** — two-tier so the importer is safe to re-run repeatedly:
// 1. Primary key: fdcId (when non-zero). USDA records have stable, globally
//    unique fdcIds, and the existing meal-logging cache also dedupes by fdcId.
// 2. Secondary key: lowercased displayName + brandOwner. Used for hand-curated
//    entries with fdcId == 0 (or absent) where the user is providing custom
//    items that don't exist in USDA. Two records collide iff they have the
//    same name AND the same brand (so "Chicken breast" and "Tesco Chicken
//    breast" stay separate).
//
// Records that match an existing FoodItem under either key are **skipped**,
// not overwritten — preserves any user edits made via FoodItemDetailView.

@MainActor
@Observable
final class FoodItemImporter {

    var isImporting = false
    var progress: String = ""
    var result: FoodItemImportResult?
    var errorMessage: String?

    /// Main entry point: import food items from a `.json` file URL.
    func importFoodItems(from url: URL, context: NSManagedObjectContext, household: Household?) async {
        isImporting = true
        progress = "Reading file..."
        errorMessage = nil
        result = nil

        do {
            // Access security-scoped resource (from file picker)
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }

            let data = try Data(contentsOf: url)
            let foodItems = try decode(data: data)

            guard !foodItems.isEmpty else {
                throw FoodItemImportError.noFoodItemsFound
            }

            result = importDecoded(foodItems, context: context, household: household)
            progress = "Done"
        } catch {
            errorMessage = error.localizedDescription
        }

        isImporting = false
    }

    // MARK: - Decoding

    /// Decode either a single `CodableFoodItem` object or an array of them.
    /// Exposed internally so tests can drive the same path without a file URL.
    func decode(data: Data) throws -> [CodableFoodItem] {
        let decoder = JSONDecoder()

        // Try array first
        if let array = try? decoder.decode([CodableFoodItem].self, from: data) {
            return array
        }

        // Then a single food item
        do {
            let single = try decoder.decode(CodableFoodItem.self, from: data)
            return [single]
        } catch {
            throw FoodItemImportError.decodingFailed(error.localizedDescription)
        }
    }

    /// Insert decoded food items into the context, deduping by fdcId (when
    /// non-zero) and by normalized name + brand owner (otherwise).
    /// Exposed internally so tests can drive imports without a file.
    func importDecoded(
        _ foodItems: [CodableFoodItem],
        context: NSManagedObjectContext,
        household: Household?
    ) -> FoodItemImportResult {
        // Fetch existing food items for dedup
        let existingRequest = NSFetchRequest<FoodItem>(entityName: "FoodItem")
        let existingItems: [FoodItem]
        do {
            existingItems = try context.fetch(existingRequest)
        } catch {
            AppLogger.swiftData.error("Failed to fetch existing food items for duplicate check: \(error.localizedDescription)")
            existingItems = []
        }

        // Build dedup indexes:
        //   fdcIdIndex:    Int32 (>0)            → existing FoodItem
        //   nameBrandIndex: "name|brand"-lowered → existing FoodItem
        var fdcIdIndex: [Int32: FoodItem] = [:]
        var nameBrandIndex: [String: FoodItem] = [:]
        for item in existingItems {
            if item.fdcId > 0 {
                fdcIdIndex[item.fdcId] = item
            }
            nameBrandIndex[Self.dedupKey(name: item.displayName, brand: item.brandOwner)] = item
        }

        var imported = 0
        var skipped = 0
        var errors: [String] = []

        for (index, codable) in foodItems.enumerated() {
            let trimmed = codable.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                errors.append("Skipped food item with no displayName")
                continue
            }

            progress = "Importing \(index + 1) of \(foodItems.count)..."

            // Dedup primary: fdcId. Int32(exactly:) so a barcode-sized id in
            // the JSON falls through to name+brand dedup instead of trapping.
            if let fdc = codable.fdcId, fdc > 0, let fdc32 = Int32(exactly: fdc), fdcIdIndex[fdc32] != nil {
                skipped += 1
                continue
            }

            // Dedup secondary: name + brand
            let key = Self.dedupKey(name: trimmed, brand: codable.brandOwner)
            if nameBrandIndex[key] != nil {
                skipped += 1
                continue
            }

            // Create
            let foodItem = codable.toFoodItem(context: context)
            foodItem.household = household

            // Update indexes so subsequent rows in this batch can dedupe against it
            if foodItem.fdcId > 0 {
                fdcIdIndex[foodItem.fdcId] = foodItem
            }
            nameBrandIndex[key] = foodItem
            imported += 1
        }

        do {
            try context.save()
        } catch {
            // Nothing was committed — roll back and report zero imported rather than a
            // false success count with the inserts still pending in the context.
            context.rollback()
            errors.append("Save failed: \(error.localizedDescription)")
            return FoodItemImportResult(imported: 0, skipped: skipped, errors: errors)
        }

        return FoodItemImportResult(imported: imported, skipped: skipped, errors: errors)
    }

    // MARK: - Helpers

    /// Build the secondary dedup key. Lowercased + trimmed name plus a
    /// pipe-separated brand owner so "Chicken breast" without a brand and
    /// "Chicken breast" with brand "Tesco" produce different keys.
    static func dedupKey(name: String, brand: String?) -> String {
        let normalisedName = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let normalisedBrand = (brand ?? "").lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(normalisedName)|\(normalisedBrand)"
    }
}
