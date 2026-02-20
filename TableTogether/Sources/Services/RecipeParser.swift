//
//  RecipeParser.swift
//  TableTogether
//
//  Parses recipes from URLs by extracting structured data.
//  Supports JSON-LD schema.org Recipe format commonly used by recipe websites.
//

import Foundation

// MARK: - Parsed Recipe

/// A recipe parsed from an external source, ready to be converted to a Recipe model.
struct ParsedRecipe: Identifiable {
    let id = UUID()
    var title: String
    var summary: String?
    var sourceURL: URL?
    var servings: Int
    var prepTimeMinutes: Int?
    var cookTimeMinutes: Int?
    var ingredients: [ParsedIngredient]
    var instructions: [String]
    var imageURL: URL?
    var suggestedArchetypes: [ArchetypeType]

    init(
        title: String = "",
        summary: String? = nil,
        sourceURL: URL? = nil,
        servings: Int = 4,
        prepTimeMinutes: Int? = nil,
        cookTimeMinutes: Int? = nil,
        ingredients: [ParsedIngredient] = [],
        instructions: [String] = [],
        imageURL: URL? = nil,
        suggestedArchetypes: [ArchetypeType] = []
    ) {
        self.title = title
        self.summary = summary
        self.sourceURL = sourceURL
        self.servings = servings
        self.prepTimeMinutes = prepTimeMinutes
        self.cookTimeMinutes = cookTimeMinutes
        self.ingredients = ingredients
        self.instructions = instructions
        self.imageURL = imageURL
        self.suggestedArchetypes = suggestedArchetypes
    }
}

/// A parsed ingredient with quantity and unit extracted from text.
struct ParsedIngredient: Identifiable, Equatable {
    let id = UUID()
    var name: String
    var quantity: Double
    var unit: MeasurementUnit
    var preparationNote: String?
    var isOptional: Bool

    /// The original text before parsing (for display/debugging)
    var originalText: String?

    init(
        name: String,
        quantity: Double = 1,
        unit: MeasurementUnit = .piece,
        preparationNote: String? = nil,
        isOptional: Bool = false,
        originalText: String? = nil
    ) {
        self.name = name
        self.quantity = quantity
        self.unit = unit
        self.preparationNote = preparationNote
        self.isOptional = isOptional
        self.originalText = originalText
    }

    var displayString: String {
        var result = ""
        if unit != .toTaste {
            if quantity == Double(Int(quantity)) {
                result = "\(Int(quantity))"
            } else {
                result = String(format: "%.1f", quantity)
            }
            result += " \(unit.displayName) "
        }
        result += name
        if let note = preparationNote, !note.isEmpty {
            result += ", \(note)"
        }
        if isOptional {
            result += " (optional)"
        }
        return result
    }

    static func == (lhs: ParsedIngredient, rhs: ParsedIngredient) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Parser Errors

/// Errors that can occur during recipe parsing.
enum RecipeParserError: LocalizedError {
    case invalidURL
    case networkError(Error)
    case parsingFailed
    case noRecipeFound
    case unsupportedSite

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The URL provided is not valid."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .parsingFailed:
            return "Failed to parse the recipe from the page."
        case .noRecipeFound:
            return "No recipe was found on this page."
        case .unsupportedSite:
            return "This website is not yet supported for automatic import."
        }
    }
}

// MARK: - Recipe Parser Protocol

/// Protocol for recipe parsers that extract recipe data from URLs.
protocol RecipeParserProtocol {
    /// Parses a recipe from the given URL.
    ///
    /// - Parameter url: The URL of the recipe page
    /// - Returns: A `ParsedRecipe` with extracted data
    /// - Throws: `RecipeParserError` if parsing fails
    func parse(url: URL) async throws -> ParsedRecipe
}

// MARK: - Basic Recipe Parser

/// A basic recipe parser that extracts JSON-LD schema.org Recipe data from HTML pages.
///
/// This parser:
/// - Fetches HTML content from the provided URL
/// - Extracts JSON-LD structured data (schema.org Recipe format)
/// - Falls back to basic HTML parsing if JSON-LD is not available
/// - Suggests archetypes based on recipe characteristics (time, title keywords)
@MainActor
final class BasicRecipeParser: RecipeParserProtocol, ObservableObject {

    // MARK: - Published Properties

    @Published var isLoading = false
    @Published var error: RecipeParserError?

    // MARK: - Private Properties

    private let urlSession: URLSession

    // MARK: - Initialization

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    // MARK: - RecipeParserProtocol

    func parse(url: URL) async throws -> ParsedRecipe {
        isLoading = true
        error = nil

        defer { isLoading = false }

        do {
            let (data, response) = try await urlSession.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                throw RecipeParserError.networkError(
                    NSError(domain: "HTTPError", code: (response as? HTTPURLResponse)?.statusCode ?? 0)
                )
            }

            guard let html = String(data: data, encoding: .utf8) else {
                throw RecipeParserError.parsingFailed
            }

            // Try to parse JSON-LD schema first
            if let recipe = try? parseJSONLD(from: html, sourceURL: url) {
                return recipe
            }

            // Fall back to basic HTML parsing
            if let recipe = try? parseBasicHTML(from: html, sourceURL: url) {
                return recipe
            }

            throw RecipeParserError.noRecipeFound

        } catch let parserError as RecipeParserError {
            self.error = parserError
            throw parserError
        } catch {
            let parserError = RecipeParserError.networkError(error)
            self.error = parserError
            throw parserError
        }
    }

    // MARK: - JSON-LD Parsing

    private func parseJSONLD(from html: String, sourceURL: URL) throws -> ParsedRecipe {
        // Find JSON-LD script tags
        let pattern = #"<script[^>]*type=["\']application/ld\+json["\'][^>]*>([\s\S]*?)</script>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            throw RecipeParserError.parsingFailed
        }

        let range = NSRange(html.startIndex..., in: html)
        let matches = regex.matches(in: html, options: [], range: range)

        for match in matches {
            guard let jsonRange = Range(match.range(at: 1), in: html) else { continue }
            let jsonString = String(html[jsonRange])

            guard let jsonData = jsonString.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: jsonData) else {
                continue
            }

            // Handle array of JSON-LD objects
            if let jsonArray = json as? [[String: Any]] {
                for obj in jsonArray {
                    if let recipe = parseRecipeFromJSON(obj, sourceURL: sourceURL) {
                        return recipe
                    }
                }
            }

            // Handle single JSON-LD object
            if let jsonDict = json as? [String: Any] {
                // Check for @graph array
                if let graph = jsonDict["@graph"] as? [[String: Any]] {
                    for obj in graph {
                        if let recipe = parseRecipeFromJSON(obj, sourceURL: sourceURL) {
                            return recipe
                        }
                    }
                }

                if let recipe = parseRecipeFromJSON(jsonDict, sourceURL: sourceURL) {
                    return recipe
                }
            }
        }

        throw RecipeParserError.noRecipeFound
    }

    private func parseRecipeFromJSON(_ json: [String: Any], sourceURL: URL) -> ParsedRecipe? {
        // Check if this is a Recipe type
        let typeValue = json["@type"]
        let isRecipe: Bool
        if let type = typeValue as? String {
            isRecipe = type.lowercased() == "recipe"
        } else if let types = typeValue as? [String] {
            isRecipe = types.contains { $0.lowercased() == "recipe" }
        } else {
            isRecipe = false
        }

        guard isRecipe else { return nil }

        let title = json["name"] as? String ?? "Untitled Recipe"
        let summary = json["description"] as? String

        // Parse servings
        var servings = 4
        if let yieldStr = json["recipeYield"] as? String {
            servings = parseServingsFromString(yieldStr)
        } else if let yieldArr = json["recipeYield"] as? [String], let first = yieldArr.first {
            servings = parseServingsFromString(first)
        } else if let yieldNum = json["recipeYield"] as? Int {
            servings = yieldNum
        }

        // Parse times
        let prepTime = parseDuration(json["prepTime"])
        let cookTime = parseDuration(json["cookTime"])

        // Parse ingredients
        var ingredients: [ParsedIngredient] = []
        if let ingredientStrings = json["recipeIngredient"] as? [String] {
            ingredients = ingredientStrings.map { parseIngredientString($0) }
        }

        // Parse instructions
        var instructions: [String] = []
        if let instructionStrings = json["recipeInstructions"] as? [String] {
            instructions = instructionStrings.filter { !$0.isEmpty }
        } else if let instructionObjects = json["recipeInstructions"] as? [[String: Any]] {
            instructions = instructionObjects.compactMap { step -> String? in
                if let text = step["text"] as? String {
                    return text
                }
                if let name = step["name"] as? String {
                    return name
                }
                return nil
            }
        }

        // Parse image URL
        var imageURL: URL?
        if let imageStr = json["image"] as? String {
            imageURL = URL(string: imageStr)
        } else if let imageObj = json["image"] as? [String: Any], let urlStr = imageObj["url"] as? String {
            imageURL = URL(string: urlStr)
        } else if let imageArr = json["image"] as? [String], let first = imageArr.first {
            imageURL = URL(string: first)
        } else if let imageArr = json["image"] as? [[String: Any]], let first = imageArr.first,
                  let urlStr = first["url"] as? String {
            imageURL = URL(string: urlStr)
        }

        // Suggest archetypes based on time and title
        let suggestedArchetypes = suggestArchetypes(
            prepTime: prepTime,
            cookTime: cookTime,
            title: title
        )

        return ParsedRecipe(
            title: title,
            summary: summary,
            sourceURL: sourceURL,
            servings: servings,
            prepTimeMinutes: prepTime,
            cookTimeMinutes: cookTime,
            ingredients: ingredients,
            instructions: instructions,
            imageURL: imageURL,
            suggestedArchetypes: suggestedArchetypes
        )
    }

    // MARK: - Basic HTML Parsing (Fallback)

    private func parseBasicHTML(from html: String, sourceURL: URL) throws -> ParsedRecipe {
        // Basic fallback - extract title from <title> tag
        var title = "Untitled Recipe"
        if let titleRange = html.range(of: #"<title[^>]*>(.*?)</title>"#, options: .regularExpression) {
            let titleHtml = String(html[titleRange])
            title = titleHtml
                .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return ParsedRecipe(
            title: title,
            sourceURL: sourceURL,
            servings: 4,
            ingredients: [],
            instructions: []
        )
    }

    // MARK: - Helper Methods

    private func parseServingsFromString(_ string: String) -> Int {
        let numbers = string.components(separatedBy: CharacterSet.decimalDigits.inverted)
            .filter { !$0.isEmpty }
            .compactMap { Int($0) }
        return numbers.first ?? 4
    }

    private func parseDuration(_ value: Any?) -> Int? {
        guard let durationStr = value as? String else { return nil }

        // Parse ISO 8601 duration (e.g., "PT30M", "PT1H30M")
        var minutes = 0

        if let hoursMatch = durationStr.range(of: #"(\d+)H"#, options: .regularExpression) {
            let hoursStr = durationStr[hoursMatch].dropLast()
            minutes += (Int(hoursStr) ?? 0) * 60
        }

        if let minsMatch = durationStr.range(of: #"(\d+)M"#, options: .regularExpression) {
            let minsStr = durationStr[minsMatch].dropLast()
            minutes += Int(minsStr) ?? 0
        }

        return minutes > 0 ? minutes : nil
    }

    private func parseIngredientString(_ string: String) -> ParsedIngredient {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)

        // Try to extract quantity and unit
        var quantity: Double = 1
        var unit: MeasurementUnit = .piece
        var name = trimmed
        var preparationNote: String?

        // Common patterns: "1 cup flour", "2 tablespoons butter", "1/2 teaspoon salt"
        let patterns: [(String, MeasurementUnit)] = [
            (#"^([\d./]+)\s*(?:cups?|c\.?)\s+"#, .cup),
            (#"^([\d./]+)\s*(?:tablespoons?|tbsp?\.?|T\.?)\s+"#, .tablespoon),
            (#"^([\d./]+)\s*(?:teaspoons?|tsp?\.?|t\.?)\s+"#, .teaspoon),
            (#"^([\d./]+)\s*(?:grams?|g\.?)\s+"#, .gram),
            (#"^([\d./]+)\s*(?:kg|kilograms?)\s+"#, .kilogram),
            (#"^([\d./]+)\s*(?:ml|milliliters?)\s+"#, .milliliter),
            (#"^([\d./]+)\s*(?:l|liters?)\s+"#, .liter),
            (#"^([\d./]+)\s*(?:pieces?|pcs?\.?)\s+"#, .piece),
            (#"^([\d./]+)\s*(?:slices?)\s+"#, .slice),
            (#"^([\d./]+)\s*(?:cloves?)\s+"#, .clove),
            (#"^([\d./]+)\s*(?:bunch(?:es)?)\s+"#, .bunch),
            (#"^([\d./]+)\s*(?:pinch(?:es)?)\s+"#, .pinch),
            (#"^([\d./]+)\s+"#, .piece) // Fallback for just a number
        ]

        for (pattern, matchedUnit) in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: trimmed, options: [], range: NSRange(trimmed.startIndex..., in: trimmed)) {

                if let quantityRange = Range(match.range(at: 1), in: trimmed) {
                    let quantityStr = String(trimmed[quantityRange])
                    quantity = parseFraction(quantityStr)
                }

                unit = matchedUnit
                name = String(trimmed[trimmed.index(trimmed.startIndex, offsetBy: match.range.length)...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }

        // Check for preparation notes (after comma)
        if let commaIndex = name.firstIndex(of: ",") {
            preparationNote = String(name[name.index(after: commaIndex)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            name = String(name[..<commaIndex])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Check if optional
        let isOptional = name.lowercased().contains("optional") ||
                         (preparationNote?.lowercased().contains("optional") ?? false)

        // Clean up name
        name = name.replacingOccurrences(of: "(optional)", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return ParsedIngredient(
            name: name,
            quantity: quantity,
            unit: unit,
            preparationNote: preparationNote,
            isOptional: isOptional,
            originalText: trimmed
        )
    }

    private func parseFraction(_ string: String) -> Double {
        // Handle fractions like "1/2", "1 1/2", etc.
        let components = string.components(separatedBy: " ")

        var total: Double = 0

        for component in components {
            if component.contains("/") {
                let fractionParts = component.components(separatedBy: "/")
                if fractionParts.count == 2,
                   let numerator = Double(fractionParts[0]),
                   let denominator = Double(fractionParts[1]),
                   denominator != 0 {
                    total += numerator / denominator
                }
            } else if let num = Double(component) {
                total += num
            }
        }

        return total > 0 ? total : 1
    }

    /// Suggests archetypes based on recipe characteristics.
    private func suggestArchetypes(
        prepTime: Int?,
        cookTime: Int?,
        title: String
    ) -> [ArchetypeType] {
        var archetypes: [ArchetypeType] = []

        // Total time-based suggestions
        let totalTime = (prepTime ?? 0) + (cookTime ?? 0)

        if totalTime > 0 && totalTime <= 30 {
            archetypes.append(.quickWeeknight)
        }

        if totalTime >= 120 || (cookTime ?? 0) >= 90 {
            archetypes.append(.slowCook)
        }

        // Title-based suggestions
        let lowercaseTitle = title.lowercased()

        if lowercaseTitle.contains("batch") || lowercaseTitle.contains("meal prep") {
            archetypes.append(.bigBatch)
        }

        if lowercaseTitle.contains("salad") || lowercaseTitle.contains("light") || lowercaseTitle.contains("fresh") {
            archetypes.append(.lightFresh)
        }

        if lowercaseTitle.contains("comfort") || lowercaseTitle.contains("classic") || lowercaseTitle.contains("homestyle") {
            archetypes.append(.comfort)
        }

        return archetypes
    }
}

// MARK: - Convenience Type Alias

/// Type alias for backward compatibility with existing code that may use RecipeParser name.
typealias RecipeParser = BasicRecipeParser
