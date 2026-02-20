import Foundation
import Compression
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

// MARK: - UTType Extension

extension UTType {
    /// Paprika multi-recipe export archive (.paprikarecipes)
    static let paprikaRecipes = UTType(filenameExtension: "paprikarecipes") ?? .data
}

// MARK: - Paprika JSON Model

/// Represents a single recipe as stored in Paprika's export format.
/// All fields are optional strings since Paprika uses loose JSON.
struct PaprikaRecipeData: Decodable {
    let uid: String?
    let name: String?
    let ingredients: String?
    let directions: String?
    let servings: String?
    let prep_time: String?
    let cook_time: String?
    let notes: String?
    let source: String?
    let source_url: String?
    let nutritional_info: String?
    let photo_data: String?
    let on_favorites: Int?
    let categories: [String]?
    let rating: Int?
    let difficulty: String?
    let description: String?
}

// MARK: - Import Result

struct PaprikaImportResult {
    let imported: Int
    let skipped: Int
    let errors: [String]
}

// MARK: - Import Errors

enum PaprikaImportError: LocalizedError {
    case invalidFile
    case invalidGzipData
    case decompressionFailed
    case noRecipesFound

    var errorDescription: String? {
        switch self {
        case .invalidFile: return "The file does not appear to be a valid Paprika export."
        case .invalidGzipData: return "Could not read a recipe entry (invalid compression)."
        case .decompressionFailed: return "Failed to decompress recipe data."
        case .noRecipesFound: return "No recipes found in the file."
        }
    }
}

// MARK: - Paprika Importer

@MainActor
final class PaprikaImporter: ObservableObject {

    @Published var isImporting = false
    @Published var progress: String = ""
    @Published var result: PaprikaImportResult?
    @Published var errorMessage: String?

    /// Main entry point: import recipes from a .paprikarecipes file URL.
    func importRecipes(from url: URL, context: ModelContext, household: Household?) async {
        isImporting = true
        progress = "Reading file..."
        errorMessage = nil
        result = nil

        do {
            // Access security-scoped resource (from file picker)
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }

            let data = try Data(contentsOf: url)

            // Extract individual recipe JSON objects
            progress = "Extracting recipes..."
            let paprikaRecipes = try extractPaprikaRecipes(from: data)

            guard !paprikaRecipes.isEmpty else {
                throw PaprikaImportError.noRecipesFound
            }

            // Fetch existing recipe titles for duplicate detection
            let existingDescriptor = FetchDescriptor<Recipe>()
            let existingRecipes = (try? context.fetch(existingDescriptor)) ?? []
            let existingTitles = Set(existingRecipes.map { $0.title.lowercased() })

            var imported = 0
            var skipped = 0
            var errors: [String] = []

            for (index, paprika) in paprikaRecipes.enumerated() {
                guard let name = paprika.name, !name.trimmingCharacters(in: .whitespaces).isEmpty else {
                    errors.append("Skipped recipe with no name")
                    continue
                }

                progress = "Importing \(index + 1) of \(paprikaRecipes.count)..."

                // Skip duplicates by title
                if existingTitles.contains(name.lowercased()) {
                    skipped += 1
                    continue
                }

                // Create the Recipe
                let recipe = buildRecipe(from: paprika)
                recipe.household = household
                context.insert(recipe)

                // Create RecipeIngredients from ingredient text
                if let ingredientsText = paprika.ingredients {
                    let lines = ingredientsText
                        .components(separatedBy: "\n")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }

                    for (order, line) in lines.enumerated() {
                        let parsed = parseIngredientLine(line)
                        let recipeIngredient = RecipeIngredient(
                            quantity: parsed.quantity,
                            unit: parsed.unit,
                            preparationNote: parsed.preparationNote,
                            order: order,
                            customName: parsed.name
                        )
                        recipe.addIngredient(recipeIngredient)
                        context.insert(recipeIngredient)
                    }
                }

                imported += 1
            }

            try context.save()

            result = PaprikaImportResult(imported: imported, skipped: skipped, errors: errors)
            progress = "Done"

        } catch {
            errorMessage = error.localizedDescription
        }

        isImporting = false
    }

    // MARK: - Recipe Builder

    /// Converts a Paprika JSON record into a TableTogether Recipe.
    private func buildRecipe(from paprika: PaprikaRecipeData) -> Recipe {
        let title = paprika.name ?? "Untitled"

        // Build summary from notes and description
        let summary = paprika.notes ?? paprika.description

        // Parse servings (e.g. "4", "4-6", "Serves 4")
        let servings = parseServings(paprika.servings)

        // Parse times (e.g. "25 min", "1 hr 30 min")
        let prepTime = parseMinutes(paprika.prep_time)
        let cookTime = parseMinutes(paprika.cook_time)

        // Parse directions into steps
        let instructions: [String]
        if let directionsText = paprika.directions {
            instructions = directionsText
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        } else {
            instructions = []
        }

        // Tags from categories
        let tags = paprika.categories?.map { $0.lowercased() } ?? []

        // Source URL
        let sourceURL: URL?
        if let urlString = paprika.source_url, !urlString.isEmpty {
            sourceURL = URL(string: urlString)
        } else {
            sourceURL = nil
        }

        // Photo data (base64 encoded)
        let imageData: Data?
        if let photoBase64 = paprika.photo_data, !photoBase64.isEmpty {
            imageData = Data(base64Encoded: photoBase64)
        } else {
            imageData = nil
        }

        // Favorite status
        let isFavorite = (paprika.on_favorites ?? 0) != 0

        let recipe = Recipe(
            title: title,
            summary: summary,
            sourceURL: sourceURL,
            servings: servings,
            prepTimeMinutes: prepTime,
            cookTimeMinutes: cookTime,
            instructions: instructions,
            tags: tags,
            imageData: imageData,
            isFavorite: isFavorite
        )

        return recipe
    }

    // MARK: - Extraction (ZIP + Gzip)

    /// Extracts all Paprika recipe JSON objects from a .paprikarecipes archive.
    /// The archive is a ZIP file; each entry is a gzip-compressed JSON file.
    private func extractPaprikaRecipes(from data: Data) throws -> [PaprikaRecipeData] {
        // Detect format: ZIP starts with PK (0x50, 0x4b), Gzip starts with 0x1f 0x8b
        guard data.count >= 4 else { throw PaprikaImportError.invalidFile }

        if data[data.startIndex] == 0x50 && data[data.startIndex + 1] == 0x4b {
            // ZIP archive — multiple recipes
            let entries = try extractZipEntries(from: data)
            var recipes: [PaprikaRecipeData] = []

            for entry in entries {
                // Each entry is gzip-compressed JSON
                if let jsonData = try? decompressGzip(entry.data) {
                    if let recipe = try? JSONDecoder().decode(PaprikaRecipeData.self, from: jsonData) {
                        recipes.append(recipe)
                    }
                } else {
                    // Maybe it's already plain JSON (unlikely but handle gracefully)
                    if let recipe = try? JSONDecoder().decode(PaprikaRecipeData.self, from: entry.data) {
                        recipes.append(recipe)
                    }
                }
            }

            return recipes

        } else if data[data.startIndex] == 0x1f && data[data.startIndex + 1] == 0x8b {
            // Single gzip file — one recipe
            let jsonData = try decompressGzip(data)
            let recipe = try JSONDecoder().decode(PaprikaRecipeData.self, from: jsonData)
            return [recipe]

        } else {
            // Try plain JSON
            let recipe = try JSONDecoder().decode(PaprikaRecipeData.self, from: data)
            return [recipe]
        }
    }

    // MARK: - ZIP Parser

    /// Extracts file entries from a ZIP archive.
    private func extractZipEntries(from data: Data) throws -> [(filename: String, data: Data)] {
        var entries: [(String, Data)] = []
        var offset = data.startIndex

        while offset + 30 <= data.endIndex {
            // Read local file header signature
            let sig = readUInt32(from: data, at: offset)
            guard sig == 0x04034b50 else { break }

            let method = readUInt16(from: data, at: offset + 8)
            let compressedSize = Int(readUInt32(from: data, at: offset + 18))
            let uncompressedSize = Int(readUInt32(from: data, at: offset + 22))
            let nameLength = Int(readUInt16(from: data, at: offset + 26))
            let extraLength = Int(readUInt16(from: data, at: offset + 28))

            let nameStart = offset + 30
            guard nameStart + nameLength <= data.endIndex else { break }
            let filename = String(data: data[nameStart..<nameStart + nameLength], encoding: .utf8) ?? ""

            let dataStart = nameStart + nameLength + extraLength

            // Skip directories and entries with unknown size
            guard !filename.hasSuffix("/"), compressedSize > 0 else {
                offset = dataStart + compressedSize
                continue
            }

            guard dataStart + compressedSize <= data.endIndex else { break }
            let fileData = Data(data[dataStart..<dataStart + compressedSize])

            switch method {
            case 0: // Stored (no compression)
                entries.append((filename, fileData))
            case 8: // Deflate
                if let decompressed = decompressDeflate(fileData, expectedSize: uncompressedSize) {
                    entries.append((filename, decompressed))
                }
            default:
                break
            }

            offset = dataStart + compressedSize
        }

        return entries
    }

    // MARK: - Decompression

    /// Decompresses raw deflate data using the Compression framework.
    private func decompressDeflate(_ data: Data, expectedSize: Int) -> Data? {
        // Use expected size with headroom, or a generous default
        let bufferSize = max(expectedSize > 0 ? expectedSize + 1024 : data.count * 10, 65536)
        let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { destinationBuffer.deallocate() }

        let decodedSize = data.withUnsafeBytes { sourceRaw -> Int in
            guard let sourceBytes = sourceRaw.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return 0
            }
            return compression_decode_buffer(
                destinationBuffer, bufferSize,
                sourceBytes, data.count,
                nil,
                COMPRESSION_ZLIB
            )
        }

        guard decodedSize > 0 else { return nil }
        return Data(bytes: destinationBuffer, count: decodedSize)
    }

    /// Decompresses gzip data by stripping the gzip header and inflating the deflate payload.
    private func decompressGzip(_ data: Data) throws -> Data {
        guard data.count >= 10 else { throw PaprikaImportError.invalidGzipData }
        guard data[data.startIndex] == 0x1f && data[data.startIndex + 1] == 0x8b else {
            throw PaprikaImportError.invalidGzipData
        }

        // Parse gzip header to find where deflate data starts
        var headerEnd = data.startIndex + 10
        let flags = data[data.startIndex + 3]

        // FEXTRA
        if flags & 0x04 != 0 {
            guard headerEnd + 2 <= data.endIndex else { throw PaprikaImportError.invalidGzipData }
            let extraLen = Int(data[headerEnd]) | (Int(data[headerEnd + 1]) << 8)
            headerEnd += 2 + extraLen
        }

        // FNAME (null-terminated string)
        if flags & 0x08 != 0 {
            while headerEnd < data.endIndex && data[headerEnd] != 0 {
                headerEnd += 1
            }
            headerEnd += 1 // skip null terminator
        }

        // FCOMMENT (null-terminated string)
        if flags & 0x10 != 0 {
            while headerEnd < data.endIndex && data[headerEnd] != 0 {
                headerEnd += 1
            }
            headerEnd += 1
        }

        // FHCRC
        if flags & 0x02 != 0 {
            headerEnd += 2
        }

        guard headerEnd < data.endIndex - 8 else { throw PaprikaImportError.invalidGzipData }

        // Read uncompressed size from last 4 bytes (little-endian)
        let sizeOffset = data.endIndex - 4
        let uncompressedSize = Int(data[sizeOffset])
            | (Int(data[sizeOffset + 1]) << 8)
            | (Int(data[sizeOffset + 2]) << 16)
            | (Int(data[sizeOffset + 3]) << 24)

        // Extract raw deflate data (between header and 8-byte trailer)
        let deflateData = Data(data[headerEnd..<data.endIndex - 8])

        guard let decompressed = decompressDeflate(deflateData, expectedSize: uncompressedSize) else {
            throw PaprikaImportError.decompressionFailed
        }

        return decompressed
    }

    // MARK: - Binary Helpers

    private func readUInt16(from data: Data, at offset: Data.Index) -> UInt16 {
        data[offset..<offset + 2].withUnsafeBytes { $0.load(as: UInt16.self) }
    }

    private func readUInt32(from data: Data, at offset: Data.Index) -> UInt32 {
        data[offset..<offset + 4].withUnsafeBytes { $0.load(as: UInt32.self) }
    }

    // MARK: - Text Parsers

    /// Parses a servings string like "4", "4-6", "Serves 4" into an integer.
    private func parseServings(_ text: String?) -> Int {
        guard let text = text?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return 4 }

        // Try to find the first integer in the string
        let pattern = #"(\d+)"#
        if let match = text.range(of: pattern, options: .regularExpression) {
            return Int(text[match]) ?? 4
        }
        return 4
    }

    /// Parses a time string like "25 min", "1 hr 30 min", "45 minutes" into total minutes.
    private func parseMinutes(_ text: String?) -> Int? {
        guard let text = text?.trimmingCharacters(in: .whitespaces).lowercased(), !text.isEmpty else {
            return nil
        }

        var totalMinutes = 0

        // Match hours
        let hourPattern = #"(\d+)\s*(?:hr|hour|hrs|hours)"#
        if let hourMatch = text.range(of: hourPattern, options: .regularExpression) {
            let hourStr = text[hourMatch]
            if let digits = hourStr.range(of: #"\d+"#, options: .regularExpression) {
                totalMinutes += (Int(hourStr[digits]) ?? 0) * 60
            }
        }

        // Match minutes
        let minPattern = #"(\d+)\s*(?:min|minute|minutes|mins)"#
        if let minMatch = text.range(of: minPattern, options: .regularExpression) {
            let minStr = text[minMatch]
            if let digits = minStr.range(of: #"\d+"#, options: .regularExpression) {
                totalMinutes += Int(minStr[digits]) ?? 0
            }
        }

        // If no unit matched, try bare number as minutes
        if totalMinutes == 0 {
            if let value = Int(text) {
                return value
            }
        }

        return totalMinutes > 0 ? totalMinutes : nil
    }

    // MARK: - Ingredient Line Parser

    struct ParsedIngredient {
        let name: String
        let quantity: Double
        let unit: MeasurementUnit
        let preparationNote: String?
    }

    /// Parses a single Paprika ingredient line like "2 cups flour, sifted" or "1/2 tsp salt".
    private func parseIngredientLine(_ line: String) -> ParsedIngredient {
        var text = line.trimmingCharacters(in: .whitespaces)

        // Split off preparation note after comma
        var preparationNote: String?
        if let commaRange = text.range(of: ",", options: .backwards) {
            let afterComma = text[commaRange.upperBound...].trimmingCharacters(in: .whitespaces)
            if !afterComma.isEmpty {
                preparationNote = afterComma
                text = String(text[..<commaRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            }
        }

        // Try to parse leading quantity
        var remaining = text
        let quantity = parseLeadingQuantity(&remaining)

        // Try to match a unit from the remaining text
        let (unit, afterUnit) = parseLeadingUnit(remaining)

        // Whatever is left is the ingredient name
        let name = afterUnit.trimmingCharacters(in: .whitespaces)

        return ParsedIngredient(
            name: name.isEmpty ? text : name,
            quantity: quantity ?? 1,
            unit: unit ?? .piece,
            preparationNote: preparationNote
        )
    }

    /// Parses a leading quantity from a string, handling integers, decimals, fractions, and mixed numbers.
    /// Modifies the input string to remove the parsed quantity.
    private func parseLeadingQuantity(_ text: inout String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)

        // Pattern: optional whole number, optional fraction (e.g. "1 1/2", "1/2", "2", "0.5")
        let pattern = #"^(\d+(?:\.\d+)?)\s+(\d+)\s*/\s*(\d+)"# // mixed number: "1 1/2"
        let fractionPattern = #"^(\d+)\s*/\s*(\d+)"# // fraction: "1/2"
        let numberPattern = #"^(\d+(?:\.\d+)?)"# // decimal or integer: "2" or "0.5"

        // Try mixed number first (e.g. "1 1/2")
        if let match = trimmed.range(of: pattern, options: .regularExpression) {
            let matched = String(trimmed[match])
            let components = matched.components(separatedBy: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "/")))
                .filter { !$0.isEmpty }
            if components.count >= 3,
               let whole = Double(components[0]),
               let num = Double(components[1]),
               let den = Double(components[2]),
               den > 0 {
                text = String(trimmed[match.upperBound...]).trimmingCharacters(in: .whitespaces)
                return whole + num / den
            }
        }

        // Try fraction (e.g. "1/2")
        if let match = trimmed.range(of: fractionPattern, options: .regularExpression) {
            let matched = String(trimmed[match])
            let parts = matched.components(separatedBy: "/")
            if parts.count == 2,
               let num = Double(parts[0]),
               let den = Double(parts[1]),
               den > 0 {
                text = String(trimmed[match.upperBound...]).trimmingCharacters(in: .whitespaces)
                return num / den
            }
        }

        // Try plain number (e.g. "2" or "0.5")
        if let match = trimmed.range(of: numberPattern, options: .regularExpression) {
            if let value = Double(trimmed[match]) {
                text = String(trimmed[match.upperBound...]).trimmingCharacters(in: .whitespaces)
                return value
            }
        }

        return nil
    }

    /// Attempts to match a unit keyword at the start of the text.
    /// Returns the matched MeasurementUnit and the remaining text after the unit.
    private func parseLeadingUnit(_ text: String) -> (MeasurementUnit?, String) {
        let lower = text.lowercased()

        // Order matters: longer matches first to avoid partial matches
        let unitMappings: [(keywords: [String], unit: MeasurementUnit)] = [
            (["tablespoons", "tablespoon", "tbsps", "tbsp", "tbs"], .tablespoon),
            (["teaspoons", "teaspoon", "tsps", "tsp"], .teaspoon),
            (["kilograms", "kilogram", "kgs", "kg"], .kilogram),
            (["milliliters", "millilitres", "milliliter", "millilitre", "mls", "ml"], .milliliter),
            (["liters", "litres", "liter", "litre", "lts", "lt", "l"], .liter),
            (["grams", "gram", "gms", "gm", "g"], .gram),
            (["cups", "cup"], .cup),
            (["pieces", "piece", "pcs", "pc"], .piece),
            (["slices", "slice"], .slice),
            (["cloves", "clove"], .clove),
            (["bunches", "bunch"], .bunch),
            (["pinches", "pinch"], .pinch),
        ]

        for (keywords, unit) in unitMappings {
            for keyword in keywords {
                if lower.hasPrefix(keyword) {
                    let afterKeyword = lower.index(lower.startIndex, offsetBy: keyword.count)
                    // Ensure the keyword is followed by a word boundary (space, end, or period)
                    if afterKeyword == lower.endIndex || lower[afterKeyword] == " " || lower[afterKeyword] == "." {
                        let remaining = String(text[text.index(text.startIndex, offsetBy: keyword.count)...])
                        return (unit, remaining.trimmingCharacters(in: .whitespaces))
                    }
                }
            }
        }

        return (nil, text)
    }
}
