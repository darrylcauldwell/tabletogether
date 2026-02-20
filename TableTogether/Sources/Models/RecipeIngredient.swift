import Foundation
import SwiftData

/// Junction model linking Ingredient to Recipe with quantity and preparation details.
/// Represents a specific usage of an ingredient within a recipe.
@Model
final class RecipeIngredient {
    /// Primary identifier
    @Attribute(.unique) var id: UUID

    /// Amount needed for the recipe
    var quantity: Double

    /// Unit for this usage (may differ from ingredient's default unit)
    var unit: MeasurementUnit

    /// Optional preparation note (e.g., "diced", "minced", "julienned")
    var preparationNote: String?

    /// Whether this ingredient is optional in the recipe
    var isOptional: Bool

    /// Display order in recipe ingredient list
    var order: Int

    /// Custom name for ingredients not linked to the ingredient database
    var customName: String?

    // MARK: - Relationships

    /// Reference to the base ingredient
    @Relationship
    var ingredient: Ingredient?

    /// The recipe this ingredient belongs to
    @Relationship
    var recipe: Recipe?

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        ingredient: Ingredient? = nil,
        quantity: Double,
        unit: MeasurementUnit,
        preparationNote: String? = nil,
        isOptional: Bool = false,
        order: Int = 0,
        customName: String? = nil
    ) {
        self.id = id
        self.ingredient = ingredient
        self.quantity = quantity
        self.unit = unit
        self.preparationNote = preparationNote
        self.isOptional = isOptional
        self.order = order
        self.customName = customName
    }

    // MARK: - Computed Properties

    /// The name to display for this ingredient (from linked ingredient or custom name)
    var displayName: String {
        ingredient?.name ?? customName ?? "Unknown Ingredient"
    }

    /// Display string for the ingredient line (e.g., "2 cups chicken breast, diced")
    var displayString: String {
        var result = "\(formattedQuantity) \(unit.abbreviation)"

        result += " \(displayName)"

        if let note = preparationNote, !note.isEmpty {
            result += ", \(note)"
        }

        if isOptional {
            result += " (optional)"
        }

        return result
    }

    /// Formatted quantity string (removes unnecessary decimal places)
    var formattedQuantity: String {
        if quantity.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", quantity)
        } else {
            return String(format: "%.2f", quantity).replacingOccurrences(of: "\\.?0+$", with: "", options: .regularExpression)
        }
    }

    /// Scales the quantity for a different serving size
    func scaledQuantity(originalServings: Int, newServings: Int) -> Double {
        guard originalServings > 0 else { return quantity }
        return quantity * Double(newServings) / Double(originalServings)
    }

    /// Returns formatted quantity scaled for different serving sizes
    func formattedScaledQuantity(for servings: Int, baseServings: Int) -> String {
        let scaled = scaledQuantity(originalServings: baseServings, newServings: servings)
        if scaled.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(scaled)) \(unit.abbreviation)"
        } else {
            return String(format: "%.1f", scaled) + " \(unit.abbreviation)"
        }
    }

    // MARK: - Macro Calculations

    /// Calculates calories for this recipe ingredient based on quantity
    /// Converts quantity to grams for calculation when possible
    var calculatedCalories: Double? {
        guard let ingredient = ingredient,
              let caloriesPer100g = ingredient.caloriesPer100g else {
            return nil
        }

        let gramsQuantity = convertToGrams()
        guard let grams = gramsQuantity else { return nil }

        return (caloriesPer100g * grams) / 100.0
    }

    /// Calculates protein for this recipe ingredient
    var calculatedProtein: Double? {
        guard let ingredient = ingredient,
              let proteinPer100g = ingredient.proteinPer100g else {
            return nil
        }

        let gramsQuantity = convertToGrams()
        guard let grams = gramsQuantity else { return nil }

        return (proteinPer100g * grams) / 100.0
    }

    /// Calculates carbs for this recipe ingredient
    var calculatedCarbs: Double? {
        guard let ingredient = ingredient,
              let carbsPer100g = ingredient.carbsPer100g else {
            return nil
        }

        let gramsQuantity = convertToGrams()
        guard let grams = gramsQuantity else { return nil }

        return (carbsPer100g * grams) / 100.0
    }

    /// Calculates fat for this recipe ingredient
    var calculatedFat: Double? {
        guard let ingredient = ingredient,
              let fatPer100g = ingredient.fatPer100g else {
            return nil
        }

        let gramsQuantity = convertToGrams()
        guard let grams = gramsQuantity else { return nil }

        return (fatPer100g * grams) / 100.0
    }

    /// Converts quantity to grams for macro calculation
    /// Returns nil if conversion is not possible for the unit type
    private func convertToGrams() -> Double? {
        switch unit {
        case .gram:
            return quantity
        case .kilogram:
            return quantity * 1000
        case .milliliter:
            // Approximate: assumes density similar to water
            return quantity
        case .liter:
            return quantity * 1000
        case .cup:
            // Approximate: 1 cup = 240ml
            return quantity * 240
        case .tablespoon:
            // Approximate: 1 tbsp = 15ml
            return quantity * 15
        case .teaspoon:
            // Approximate: 1 tsp = 5ml
            return quantity * 5
        case .piece, .slice, .clove, .bunch, .pinch, .toTaste:
            // Cannot reliably convert to grams
            return nil
        }
    }
}
