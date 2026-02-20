import Foundation
import SwiftData

// MARK: - Ingredient Model

/// The foundational unit representing a food ingredient with optional macro data.
/// Ingredients are structured objects, not text strings.
@Model
final class Ingredient {
    /// Primary identifier
    @Attribute(.unique) var id: UUID

    /// Display name (e.g., "Chicken Breast")
    var name: String

    /// Lowercase, trimmed for matching
    var normalizedName: String

    /// Category for grouping (produce, protein, dairy, etc.)
    var category: IngredientCategory

    /// Preferred unit for this ingredient
    var defaultUnit: MeasurementUnit

    /// Optional macro data - calories per 100 grams
    var caloriesPer100g: Double?

    /// Optional macro data - protein per 100 grams
    var proteinPer100g: Double?

    /// Optional macro data - carbohydrates per 100 grams
    var carbsPer100g: Double?

    /// Optional macro data - fat per 100 grams
    var fatPer100g: Double?

    /// Distinguishes custom vs. system ingredients
    var isUserCreated: Bool

    /// Creation timestamp
    var createdAt: Date

    /// Last modification timestamp
    var modifiedAt: Date

    // MARK: - Relationships

    /// Recipe ingredients that use this ingredient
    @Relationship(inverse: \RecipeIngredient.ingredient)
    var recipeIngredients: [RecipeIngredient] = []

    /// Grocery items derived from this ingredient
    @Relationship(inverse: \GroceryItem.ingredient)
    var groceryItems: [GroceryItem] = []

    /// Parent household for CloudKit sharing
    @Relationship
    var household: Household?

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        name: String,
        category: IngredientCategory = .other,
        defaultUnit: MeasurementUnit = .gram,
        caloriesPer100g: Double? = nil,
        proteinPer100g: Double? = nil,
        carbsPer100g: Double? = nil,
        fatPer100g: Double? = nil,
        isUserCreated: Bool = true
    ) {
        self.id = id
        self.name = name
        self.normalizedName = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        self.category = category
        self.defaultUnit = defaultUnit
        self.caloriesPer100g = caloriesPer100g
        self.proteinPer100g = proteinPer100g
        self.carbsPer100g = carbsPer100g
        self.fatPer100g = fatPer100g
        self.isUserCreated = isUserCreated
        self.createdAt = Date()
        self.modifiedAt = Date()
    }

    // MARK: - Methods

    /// Updates the normalized name when the display name changes
    func updateName(_ newName: String) {
        self.name = newName
        self.normalizedName = newName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        self.modifiedAt = Date()
    }

    /// Check if ingredient has complete macro data
    var hasMacroData: Bool {
        caloriesPer100g != nil &&
        proteinPer100g != nil &&
        carbsPer100g != nil &&
        fatPer100g != nil
    }
}
