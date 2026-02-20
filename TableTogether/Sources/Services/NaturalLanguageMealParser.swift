import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Parses natural language meal descriptions into structured ingredients.
///
/// Primary: Apple Intelligence via Foundation Models framework (iOS 26+)
/// Fallback: Regex-based parsing (splits on "with"/"and"/commas, matches quantities and units)
@MainActor
final class NaturalLanguageMealParser: ObservableObject {

    // MARK: - Public API

    /// Parses a meal description into individual ingredients.
    func parse(description: String) async -> MealParseResult {
        let input = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else {
            return MealParseResult(originalDescription: description, ingredients: [], isAIParsed: false)
        }

        // Try Apple Intelligence first (iOS 26+ / macOS 26+)
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            if let aiResult = await parseWithAppleIntelligence(input) {
                return aiResult
            }
        }
        #endif

        // Regex fallback
        let ingredients = parseWithRegex(input)
        return MealParseResult(
            originalDescription: description,
            ingredients: ingredients,
            isAIParsed: false
        )
    }

    // MARK: - Apple Intelligence Parsing

    #if canImport(FoundationModels)
    @available(iOS 26.0, macOS 26.0, *)
    private func parseWithAppleIntelligence(_ input: String) async -> MealParseResult? {
        do {
            let session = LanguageModelSession()

            let prompt = """
            You are a food ingredient parser. Given a meal description, extract individual food components.

            Rules:
            - Output ONLY valid JSON matching the schema below. No prose, no markdown.
            - Separate composite meals into individual ingredients (e.g., "chicken sandwich" -> bread, chicken, butter).
            - Use plain food names: "chicken breast" not "grilled boneless skinless chicken breast."
            - For whole items (banana, egg, apple), use unit "piece".
            - Set quantity to null when not stated or ambiguous.
            - Set confidence to "high" when both food and quantity are clear.
            - Set confidence to "medium" when food is clear but quantity is assumed.
            - Set confidence to "low" when food identification is uncertain.
            - Default to typical single-serving portions when quantity is not given.
            - Do not invent foods not mentioned in the description.

            Schema:
            {"ingredients":[{"name":"string","quantity":"number or null","unit":"gram|kilogram|milliliter|liter|cup|tablespoon|teaspoon|piece|slice|clove|bunch|pinch|null","confidence":"high|medium|low"}]}

            Meal description: \(input)
            """

            let response = try await session.respond(to: prompt)
            let text = response.content

            // Parse the JSON response
            guard let jsonData = text.data(using: .utf8) else { return nil }
            let decoded = try JSONDecoder().decode(AIParseResponse.self, from: jsonData)

            let ingredients = decoded.ingredients.map { item -> MealParsedIngredient in
                let unit: MeasurementUnit? = item.unit.flatMap { MeasurementUnit(rawValue: $0) }
                let confidence: ParseConfidence = ParseConfidence(rawValue: item.confidence) ?? .medium

                return MealParsedIngredient(
                    name: item.name,
                    quantity: item.quantity,
                    unit: unit,
                    confidence: confidence,
                    originalText: input
                )
            }

            AppLogger.nutrition.info("Apple Intelligence parsed \(ingredients.count) ingredients")
            return MealParseResult(
                originalDescription: input,
                ingredients: ingredients,
                isAIParsed: true
            )
        } catch {
            AppLogger.nutrition.warning("Apple Intelligence parsing failed: \(error.localizedDescription)")
            return nil
        }
    }
    #endif

    // MARK: - Regex Fallback Parsing

    private func parseWithRegex(_ input: String) -> [MealParsedIngredient] {
        let lowered = input.lowercased()

        // Split on separators: "with", "and", commas, plus signs
        let segments = splitIntoSegments(lowered)

        var ingredients: [MealParsedIngredient] = []

        for segment in segments {
            let trimmed = segment.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let parsed = parseSegment(trimmed, originalText: input)
            ingredients.append(parsed)
        }

        return ingredients
    }

    /// Splits input into individual ingredient segments.
    private func splitIntoSegments(_ input: String) -> [String] {
        // Replace common separators with a delimiter
        var normalized = input

        // Handle "with" as a separator (but not inside words like "withhold")
        normalized = normalized.replacingOccurrences(
            of: "\\bwith\\b",
            with: "|||",
            options: .regularExpression
        )

        // Handle "and" as a separator (but not inside words)
        normalized = normalized.replacingOccurrences(
            of: "\\band\\b",
            with: "|||",
            options: .regularExpression
        )

        // Handle commas
        normalized = normalized.replacingOccurrences(of: ",", with: "|||")

        // Handle plus signs
        normalized = normalized.replacingOccurrences(of: "+", with: "|||")

        let segments = normalized.components(separatedBy: "|||")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return segments
    }

    /// Parses a single segment into a MealParsedIngredient.
    private func parseSegment(_ segment: String, originalText: String) -> MealParsedIngredient {
        // Pattern: optional quantity + optional unit + food name
        // Examples: "2 cups rice", "200g chicken breast", "3 eggs", "broccoli"
        let pattern = #"^(\d+(?:\.\d+)?(?:\s*/\s*\d+)?)\s*([a-z]+)?\s+(.+)$"#

        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: segment, range: NSRange(segment.startIndex..., in: segment)),
           match.numberOfRanges >= 4 {

            let quantityStr = match.range(at: 1).location != NSNotFound
                ? String(segment[Range(match.range(at: 1), in: segment)!])
                : nil

            let unitStr = match.range(at: 2).location != NSNotFound
                ? String(segment[Range(match.range(at: 2), in: segment)!])
                : nil

            let name = match.range(at: 3).location != NSNotFound
                ? String(segment[Range(match.range(at: 3), in: segment)!])
                : segment

            let quantity = quantityStr.flatMap { parseQuantity($0) }
            let unit = unitStr.flatMap { parseUnit($0) }

            // If unitStr matched but wasn't a recognized unit, it's part of the food name
            let finalName: String
            if unitStr != nil && unit == nil {
                finalName = "\(unitStr!) \(name)"
            } else {
                finalName = name
            }

            let confidence: ParseConfidence
            if quantity != nil && unit != nil {
                confidence = .high
            } else if quantity != nil {
                confidence = .medium
            } else {
                confidence = .medium
            }

            return MealParsedIngredient(
                name: cleanFoodName(finalName),
                quantity: quantity,
                unit: unit,
                confidence: confidence,
                originalText: originalText
            )
        }

        // No pattern match — try just a leading number
        let numberPattern = #"^(\d+(?:\.\d+)?)\s+(.+)$"#
        if let regex = try? NSRegularExpression(pattern: numberPattern),
           let match = regex.firstMatch(in: segment, range: NSRange(segment.startIndex..., in: segment)),
           match.numberOfRanges >= 3 {

            let quantityStr = String(segment[Range(match.range(at: 1), in: segment)!])
            let name = String(segment[Range(match.range(at: 2), in: segment)!])
            let quantity = parseQuantity(quantityStr)

            return MealParsedIngredient(
                name: cleanFoodName(name),
                quantity: quantity,
                unit: nil,
                confidence: .medium,
                originalText: originalText
            )
        }

        // Plain food name, no quantity or unit
        return MealParsedIngredient(
            name: cleanFoodName(segment),
            quantity: nil,
            unit: nil,
            confidence: .medium,
            originalText: originalText
        )
    }

    // MARK: - Quantity Parsing

    private func parseQuantity(_ str: String) -> Double? {
        // Handle fractions like "1/2"
        if str.contains("/") {
            let parts = str.split(separator: "/")
            if parts.count == 2,
               let num = Double(parts[0].trimmingCharacters(in: .whitespaces)),
               let den = Double(parts[1].trimmingCharacters(in: .whitespaces)),
               den > 0 {
                return num / den
            }
        }
        return Double(str)
    }

    // MARK: - Unit Parsing

    private static let unitMap: [(patterns: [String], unit: MeasurementUnit)] = [
        (["g", "gram", "grams"], .gram),
        (["kg", "kilogram", "kilograms", "kilo", "kilos"], .kilogram),
        (["ml", "milliliter", "milliliters", "millilitre", "millilitres"], .milliliter),
        (["l", "liter", "liters", "litre", "litres"], .liter),
        (["cup", "cups"], .cup),
        (["tbsp", "tablespoon", "tablespoons"], .tablespoon),
        (["tsp", "teaspoon", "teaspoons"], .teaspoon),
        (["pc", "pcs", "piece", "pieces"], .piece),
        (["slice", "slices"], .slice),
        (["clove", "cloves"], .clove),
        (["bunch", "bunches"], .bunch),
        (["pinch", "pinches"], .pinch),
    ]

    private func parseUnit(_ str: String) -> MeasurementUnit? {
        let lowered = str.lowercased()
        for entry in Self.unitMap {
            if entry.patterns.contains(lowered) {
                return entry.unit
            }
        }
        return nil
    }

    // MARK: - Name Cleaning

    /// Removes prep methods and modifiers from food names.
    private func cleanFoodName(_ name: String) -> String {
        var cleaned = name
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove common prep words at the start
        let prepPrefixes = ["grilled ", "steamed ", "fried ", "baked ", "boiled ",
                           "roasted ", "sauteed ", "sautéed ", "raw ", "fresh ",
                           "chopped ", "diced ", "sliced ", "minced ", "shredded ",
                           "cooked ", "dried ", "frozen ", "canned ", "tinned "]
        for prefix in prepPrefixes {
            if cleaned.hasPrefix(prefix) {
                cleaned = String(cleaned.dropFirst(prefix.count))
            }
        }

        // Remove trailing prep notes
        let prepSuffixes = [", chopped", ", diced", ", sliced", ", minced",
                           ", shredded", ", cooked", ", raw", ", fresh"]
        for suffix in prepSuffixes {
            if cleaned.hasSuffix(suffix) {
                cleaned = String(cleaned.dropLast(suffix.count))
            }
        }

        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - AI Parse Response (JSON Schema)

private struct AIParseResponse: Codable {
    let ingredients: [AIIngredient]
}

private struct AIIngredient: Codable {
    let name: String
    let quantity: Double?
    let unit: String?
    let confidence: String
}
