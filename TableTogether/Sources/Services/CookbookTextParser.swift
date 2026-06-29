//
//  CookbookTextParser.swift
//  TableTogether
//
//  Segments raw OCR text from cookbook scans into structured recipe components:
//  title, ingredients, and instructions. Uses section header detection and
//  quantity-pattern heuristics to classify lines.
//

import Foundation

struct CookbookTextParser {

    // MARK: - Parse Result

    struct ParseResult {
        var title: String
        var ingredients: [ParsedIngredient]
        var instructions: [String]
        var rawText: String
    }

    // MARK: - Public API

    static func parse(_ text: String) -> ParseResult {
        let rawText = text
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else {
            return ParseResult(title: "Untitled Recipe", ingredients: [], instructions: [], rawText: rawText)
        }

        // Try section-header-based parsing first
        if let result = parseWithHeaders(lines: lines, rawText: rawText) {
            return result
        }

        // Fall back to heuristic parsing
        return parseWithHeuristics(lines: lines, rawText: rawText)
    }

    // MARK: - Section Header Parsing

    private static func parseWithHeaders(lines: [String], rawText: String) -> ParseResult? {
        var ingredientHeaderIndex: Int?
        var instructionHeaderIndex: Int?

        for (index, line) in lines.enumerated() {
            if isSectionHeader(line, keywords: ["ingredients"]) {
                ingredientHeaderIndex = index
            } else if isSectionHeader(line, keywords: ["method", "directions", "instructions", "steps", "preparation"]) {
                instructionHeaderIndex = index
            }
        }

        // Need at least one section header to use this strategy
        guard ingredientHeaderIndex != nil || instructionHeaderIndex != nil else {
            return nil
        }

        let ingStart = ingredientHeaderIndex ?? 0
        let insStart = instructionHeaderIndex ?? lines.count

        // Title: everything before the first section header
        let firstHeader = min(ingStart, insStart)
        let titleLines = Array(lines[0..<firstHeader])
            .filter { !isServesLine($0) }
        let title = titleLines.first ?? "Untitled Recipe"

        // Ingredients: between ingredient header and instruction header (or end)
        var ingredientLines: [String] = []
        if let ingIdx = ingredientHeaderIndex {
            let end = instructionHeaderIndex ?? lines.count
            if ingIdx < end {
                ingredientLines = Array(lines[(ingIdx + 1)..<end])
                    .filter { !isSectionHeader($0) && !isServesLine($0) }
            }
        }

        // Instructions: after instruction header (or remaining lines)
        var instructionLines: [String] = []
        if let insIdx = instructionHeaderIndex {
            instructionLines = Array(lines[(insIdx + 1)..<lines.count])
                .filter { !isSectionHeader($0) }
        }

        let ingredients = ingredientLines.compactMap { parseIngredientLine($0) }
        let instructions = instructionLines.map { cleanInstructionLine($0) }
            .filter { !$0.isEmpty }

        return ParseResult(
            title: title,
            ingredients: ingredients,
            instructions: instructions,
            rawText: rawText
        )
    }

    // MARK: - Heuristic Parsing

    private static func parseWithHeuristics(lines: [String], rawText: String) -> ParseResult {
        // Title: first short line
        let title = lines.first(where: { $0.count < 60 }) ?? lines[0]
        let titleIndex = lines.firstIndex(of: title) ?? 0

        var ingredientLines: [String] = []
        var instructionLines: [String] = []

        for (index, line) in lines.enumerated() {
            if index <= titleIndex { continue }
            if isServesLine(line) { continue }

            if isIngredientLine(line) {
                ingredientLines.append(line)
            } else {
                instructionLines.append(line)
            }
        }

        let ingredients = ingredientLines.compactMap { parseIngredientLine($0) }
        let instructions = instructionLines.map { cleanInstructionLine($0) }
            .filter { !$0.isEmpty }

        return ParseResult(
            title: title,
            ingredients: ingredients,
            instructions: instructions,
            rawText: rawText
        )
    }

    // MARK: - Line Classification

    static func isIngredientLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        // Lines starting with a number or fraction are likely ingredients
        let quantityPattern = #"^[\d½¼¾⅓⅔⅛]"#
        if trimmed.range(of: quantityPattern, options: .regularExpression) != nil {
            // But not if it looks like a numbered instruction step
            let numberedStep = #"^\d+[\.\)]\s+"#
            if trimmed.range(of: numberedStep, options: .regularExpression) != nil {
                return false
            }
            return true
        }

        // Lines mentioning common units are likely ingredients
        let unitPattern = #"(?i)\b(cups?|tbsp|tsp|tablespoons?|teaspoons?|grams?|kg|oz|ounces?|lbs?|pounds?|ml|liters?|cloves?|pinch|bunch)\b"#
        if trimmed.range(of: unitPattern, options: .regularExpression) != nil {
            return true
        }

        return false
    }

    private static func isSectionHeader(_ line: String, keywords: [String]? = nil) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces).lowercased()
        let cleaned = trimmed.replacingOccurrences(of: ":", with: "")
            .trimmingCharacters(in: .whitespaces)

        let allKeywords = keywords ?? [
            "ingredients", "method", "directions", "instructions",
            "steps", "preparation", "for the", "to serve"
        ]

        return allKeywords.contains(where: { cleaned == $0 || cleaned.hasPrefix($0) })
            && cleaned.count < 40
    }

    private static func isServesLine(_ line: String) -> Bool {
        let lower = line.lowercased().trimmingCharacters(in: .whitespaces)
        return lower.hasPrefix("serves") || lower.hasPrefix("yield") || lower.hasPrefix("servings")
    }

    // MARK: - Ingredient Parsing

    static func parseIngredientLine(_ line: String) -> ParsedIngredient? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Shared tokenizer: normalizes unicode fractions, converts imperial weights to
        // metric, and disambiguates the single-letter T/t (tablespoon vs teaspoon).
        let (quantity, unit, remainder) = ParserUtilities.parseLeadingQuantityAndUnit(trimmed)
        var name = remainder
        var preparationNote: String?

        // Extract preparation note after comma
        if let commaIndex = name.firstIndex(of: ",") {
            preparationNote = String(name[name.index(after: commaIndex)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            name = String(name[..<commaIndex])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Detect optional
        let isOptional = name.lowercased().contains("optional") ||
                         (preparationNote?.lowercased().contains("optional") ?? false)
        name = name.replacingOccurrences(of: "(optional)", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !name.isEmpty else { return nil }

        return ParsedIngredient(
            name: name,
            quantity: quantity,
            unit: unit,
            preparationNote: preparationNote,
            isOptional: isOptional,
            originalText: line
        )
    }

    // MARK: - Helpers

    private static func cleanInstructionLine(_ line: String) -> String {
        var cleaned = line.trimmingCharacters(in: .whitespacesAndNewlines)
        // Remove leading step numbers like "1.", "2)", "Step 1:"
        let stepPattern = #"^(?:step\s*)?\d+[\.\):\-]\s*"#
        if let regex = try? NSRegularExpression(pattern: stepPattern, options: .caseInsensitive) {
            cleaned = regex.stringByReplacingMatches(
                in: cleaned,
                range: NSRange(cleaned.startIndex..., in: cleaned),
                withTemplate: ""
            )
        }
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
