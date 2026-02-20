import Foundation

// MARK: - Confidence Level

/// Confidence in parsing accuracy
enum ParseConfidence: String, Codable, Hashable, Sendable {
    /// Both food and quantity are clear
    case high
    /// Food is clear but quantity is assumed
    case medium
    /// Food identification is uncertain
    case low
}

// MARK: - Resolution Source

/// Where a resolved ingredient came from
enum ResolutionSource: String, Codable, Hashable, Sendable {
    /// Matched from local FoodItem cache
    case localCache
    /// Looked up from USDA API and cached
    case usdaLookup
    /// Fell back to MealEstimatorService database
    case fallback
}

// MARK: - MealParsedIngredient

/// A single ingredient extracted from natural language input.
struct MealParsedIngredient: Identifiable, Hashable, Sendable {
    let id = UUID()

    /// Plain food name (no quantities, units, or prep methods)
    let name: String

    /// Parsed quantity (nil when ambiguous)
    let quantity: Double?

    /// Measurement unit (nil when not specified)
    let unit: MeasurementUnit?

    /// Confidence in this parse
    let confidence: ParseConfidence

    /// The original text segment this was parsed from
    let originalText: String

    static func == (lhs: MealParsedIngredient, rhs: MealParsedIngredient) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - FoodItemMatch

/// A potential FoodItem match with a similarity score.
struct FoodItemMatch: Identifiable, Hashable {
    let id = UUID()

    /// The matched food item
    let foodItem: FoodItem

    /// Similarity score (0.0 to 1.0, higher = better match)
    let score: Double

    static func == (lhs: FoodItemMatch, rhs: FoodItemMatch) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - ResolvedIngredient

/// A parsed ingredient resolved against the food database with calculated macros.
struct ResolvedIngredient: Identifiable, Hashable {
    let id = UUID()

    /// The original parsed ingredient
    let parsed: MealParsedIngredient

    /// Best-match food item (nil if unresolved)
    let foodItem: FoodItem?

    /// Quantity converted to grams (nil if unconvertible)
    let quantityInGrams: Double?

    /// Calculated macros for this ingredient
    let macros: MacroSummary

    /// Alternative food item matches (2-3 options)
    let alternates: [FoodItemMatch]

    /// Where this resolution came from
    let source: ResolutionSource

    /// Display name for the ingredient
    var displayName: String {
        foodItem?.displayName ?? parsed.name.capitalized
    }

    /// Quantity description for display
    var quantityDescription: String {
        if let q = parsed.quantity, let u = parsed.unit {
            let formatted = q == floor(q) ? "\(Int(q))" : String(format: "%.1f", q)
            return "\(formatted) \(u.abbreviation)"
        } else if let q = parsed.quantity {
            let formatted = q == floor(q) ? "\(Int(q))" : String(format: "%.1f", q)
            return formatted
        } else if let grams = quantityInGrams {
            return "\(Int(grams.rounded()))g"
        }
        return "1 serving"
    }

    /// Whether this resolution has low confidence and used defaults
    var isEstimated: Bool {
        parsed.confidence != .high || quantityInGrams == nil
    }

    /// Description of assumptions made for "How did we estimate?"
    var assumptionDescription: String {
        var parts: [String] = []

        switch source {
        case .localCache:
            parts.append("Matched from saved foods")
        case .usdaLookup:
            parts.append("Looked up from USDA database")
        case .fallback:
            parts.append("Estimated from built-in database")
        }

        if parsed.quantity == nil {
            parts.append("Assumed typical single serving")
        }

        if quantityInGrams == nil {
            parts.append("Using 100g default weight")
        } else if let grams = quantityInGrams {
            parts.append("\(Int(grams.rounded()))g used for calculation")
        }

        switch parsed.confidence {
        case .high:
            parts.append("High confidence")
        case .medium:
            parts.append("Medium confidence")
        case .low:
            parts.append("Low confidence")
        }

        return parts.joined(separator: " · ")
    }

    static func == (lhs: ResolvedIngredient, rhs: ResolvedIngredient) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - MealParseResult

/// Result of parsing a meal description into structured ingredients.
struct MealParseResult: Sendable {
    /// The original user input
    let originalDescription: String

    /// Extracted ingredients
    let ingredients: [MealParsedIngredient]

    /// Whether Apple Intelligence was used for parsing
    let isAIParsed: Bool
}
