import Foundation

/// Shared helpers for the recipe/ingredient text parsers. Extracted so unicode-fraction
/// normalization, imperial-weight conversion, and single-letter unit handling stay
/// consistent across BasicRecipeParser, CookbookTextParser and IngredientParser instead
/// of drifting per-parser (the divergence was the root of several quantity bugs).
enum ParserUtilities {

    // Imperial weights have no dedicated MeasurementUnit case, so the *quantity* is
    // converted to the metric unit (e.g. 4 oz -> 113.4 g) rather than aliasing the
    // token to a wrong-magnitude unit. Aliasing oz->gram / lb->kg 1:1 silently
    // produced 28x / 2.2x macro errors.
    static let gramsPerOunce = 28.349523
    static let kilogramsPerPound = 0.45359237

    /// Converts unicode fraction glyphs (½, ¼, ⅓ …) to ASCII ("1/2", "1/4", "1/3" …)
    /// so the numeric parsers — which only match `[\d./]` — don't lose them.
    static func normalizeUnicodeFractions(_ text: String) -> String {
        var result = text
        let replacements: [(String, String)] = [
            ("½", "1/2"), ("¼", "1/4"), ("¾", "3/4"),
            ("⅓", "1/3"), ("⅔", "2/3"), ("⅛", "1/8"),
            ("⅜", "3/8"), ("⅝", "5/8"), ("⅞", "7/8"),
        ]
        for (unicode, ascii) in replacements {
            result = result.replacingOccurrences(of: unicode, with: ascii)
        }
        return result
    }

    /// Sums a quantity string that may be an integer, decimal, simple fraction
    /// ("1/2") or mixed number ("1 1/2"). Returns 1 when nothing parses, matching
    /// the parsers' "assume one" default.
    static func parseFraction(_ string: String) -> Double {
        let components = string.trimmingCharacters(in: .whitespaces)
            .components(separatedBy: " ")
            .filter { !$0.isEmpty }

        var total: Double = 0
        for component in components {
            if component.contains("/") {
                let parts = component.components(separatedBy: "/")
                if parts.count == 2,
                   let num = Double(parts[0]),
                   let denom = Double(parts[1]),
                   denom != 0 {
                    total += num / denom
                }
            } else if let num = Double(component) {
                total += num
            }
        }
        return total > 0 ? total : 1
    }

    /// A leading-quantity-and-unit pattern: the regex (anchored at the start, capturing
    /// the quantity in group 1), the unit it maps to, a quantity multiplier (for imperial
    /// weight conversion), and whether the regex must be matched case-sensitively.
    ///
    /// Single-letter abbreviations are case-SENSITIVE so `T` (tablespoon) and `t`
    /// (teaspoon) don't collide. Matching them case-insensitively — the previous
    /// behaviour — made "1 t salt" parse as a tablespoon, a 3x error.
    private struct UnitPattern {
        let pattern: String
        let unit: MeasurementUnit
        let multiplier: Double
        let caseSensitive: Bool

        init(_ pattern: String, _ unit: MeasurementUnit, _ multiplier: Double = 1, caseSensitive: Bool = false) {
            self.pattern = pattern
            self.unit = unit
            self.multiplier = multiplier
            self.caseSensitive = caseSensitive
        }
    }

    private static let unitPatterns: [UnitPattern] = [
        UnitPattern(#"^([\d./]+\s*[\d./]*)\s*(?:cups?|c\.?)\s+"#, .cup),
        UnitPattern(#"^([\d./]+\s*[\d./]*)\s*(?:tablespoons?|tbsp?\.?)\s+"#, .tablespoon),
        UnitPattern(#"^([\d./]+\s*[\d./]*)\s*(?:teaspoons?|tsp?\.?)\s+"#, .teaspoon),
        UnitPattern(#"^([\d./]+\s*[\d./]*)\s*T\.?\s+"#, .tablespoon, caseSensitive: true),
        UnitPattern(#"^([\d./]+\s*[\d./]*)\s*t\.?\s+"#, .teaspoon, caseSensitive: true),
        UnitPattern(#"^([\d./]+\s*[\d./]*)\s*(?:grams?|g\.?)\s+"#, .gram),
        UnitPattern(#"^([\d./]+\s*[\d./]*)\s*(?:kg|kilograms?)\s+"#, .kilogram),
        UnitPattern(#"^([\d./]+\s*[\d./]*)\s*(?:ml|milliliters?|millilitres?)\s+"#, .milliliter),
        UnitPattern(#"^([\d./]+\s*[\d./]*)\s*(?:l|liters?|litres?)\s+"#, .liter),
        UnitPattern(#"^([\d./]+\s*[\d./]*)\s*(?:oz|ounces?)\s+"#, .gram, gramsPerOunce),
        UnitPattern(#"^([\d./]+\s*[\d./]*)\s*(?:lbs?|pounds?)\s+"#, .kilogram, kilogramsPerPound),
        UnitPattern(#"^([\d./]+\s*[\d./]*)\s*(?:pieces?|pcs?\.?)\s+"#, .piece),
        UnitPattern(#"^([\d./]+\s*[\d./]*)\s*(?:slices?)\s+"#, .slice),
        UnitPattern(#"^([\d./]+\s*[\d./]*)\s*(?:cloves?)\s+"#, .clove),
        UnitPattern(#"^([\d./]+\s*[\d./]*)\s*(?:bunch(?:es)?)\s+"#, .bunch),
        UnitPattern(#"^([\d./]+\s*[\d./]*)\s*(?:pinch(?:es)?)\s+"#, .pinch),
        UnitPattern(#"^([\d./]+\s*[\d./]*)\s+"#, .piece), // Fallback: a leading number with no unit
    ]

    /// Parses a leading quantity + unit from an ingredient line. Unicode fractions are
    /// normalized first; imperial weights are converted to metric by scaling the quantity.
    /// Returns the quantity, the unit, and the remaining text (the ingredient name).
    /// When nothing matches, returns (1, .piece, normalized-input).
    static func parseLeadingQuantityAndUnit(_ rawText: String) -> (quantity: Double, unit: MeasurementUnit, remainder: String) {
        let text = normalizeUnicodeFractions(rawText.trimmingCharacters(in: .whitespacesAndNewlines))

        for entry in unitPatterns {
            let options: NSRegularExpression.Options = entry.caseSensitive ? [] : [.caseInsensitive]
            guard let regex = try? NSRegularExpression(pattern: entry.pattern, options: options),
                  let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)) else {
                continue
            }

            var quantity: Double = 1
            if match.numberOfRanges > 1, let quantityRange = Range(match.range(at: 1), in: text) {
                quantity = parseFraction(String(text[quantityRange])) * entry.multiplier
            }
            let remainder = String(text[text.index(text.startIndex, offsetBy: match.range.length)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (quantity, entry.unit, remainder)
        }

        return (1, .piece, text)
    }
}
