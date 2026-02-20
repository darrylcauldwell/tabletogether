import Foundation
import SwiftData

/// A cached food item with USDA nutritional data.
/// Shared via Household — nutrition facts are objective data, not personal.
/// All household members benefit from cached lookups.
///
/// FoodItem is immutable after creation (only `userAliases` is appendable).
/// Conflict resolution: last-write-wins, same as all shared models.
@Model
final class FoodItem {
    /// Primary identifier
    @Attribute(.unique) var id: UUID

    /// USDA FoodData Central ID
    var fdcId: Int

    /// Original USDA description text
    var usdaDescription: String

    /// Clean short display name
    var displayName: String

    /// Lowercase normalized name for matching
    var normalizedName: String

    /// USDA data type: "Foundation", "SR Legacy", "Survey (FNDDS)", "Branded"
    var dataType: String

    /// Brand owner (only for branded items)
    var brandOwner: String?

    // MARK: - Nutrition per 100g

    /// Calories per 100g (Nutrient 1008)
    var caloriesPer100g: Double

    /// Protein per 100g in grams (Nutrient 1003)
    var proteinPer100g: Double

    /// Carbohydrates per 100g in grams (Nutrient 1005)
    var carbsPer100g: Double

    /// Fat per 100g in grams (Nutrient 1004)
    var fatPer100g: Double

    /// Fiber per 100g in grams (Nutrient 1079)
    var fiberPer100g: Double?

    /// Sugar per 100g in grams (Nutrient 2000)
    var sugarPer100g: Double?

    /// Sodium per 100g in mg (Nutrient 1093)
    var sodiumMgPer100g: Double?

    /// JSON-encoded common portions: [{name, gramWeight}]
    var commonPortionsData: Data?

    /// User-added aliases for household correction (appendable)
    var userAliases: [String]

    /// When this item was cached
    var createdAt: Date

    // MARK: - Relationships

    /// Household this food item belongs to (shared)
    var household: Household?

    // MARK: - Initialization

    init(
        fdcId: Int,
        usdaDescription: String,
        displayName: String,
        dataType: String,
        brandOwner: String? = nil,
        caloriesPer100g: Double,
        proteinPer100g: Double,
        carbsPer100g: Double,
        fatPer100g: Double,
        fiberPer100g: Double? = nil,
        sugarPer100g: Double? = nil,
        sodiumMgPer100g: Double? = nil,
        commonPortions: [CommonPortion] = [],
        userAliases: [String] = []
    ) {
        self.id = UUID()
        self.fdcId = fdcId
        self.usdaDescription = usdaDescription
        self.displayName = displayName
        self.normalizedName = displayName.lowercased()
        self.dataType = dataType
        self.brandOwner = brandOwner
        self.caloriesPer100g = caloriesPer100g
        self.proteinPer100g = proteinPer100g
        self.carbsPer100g = carbsPer100g
        self.fatPer100g = fatPer100g
        self.fiberPer100g = fiberPer100g
        self.sugarPer100g = sugarPer100g
        self.sodiumMgPer100g = sodiumMgPer100g
        self.userAliases = userAliases
        self.createdAt = Date()

        if !commonPortions.isEmpty {
            self.commonPortionsData = try? JSONEncoder().encode(commonPortions)
        }
    }

    // MARK: - Common Portions

    /// Decoded common portions from stored JSON data
    var commonPortions: [CommonPortion] {
        guard let data = commonPortionsData else { return [] }
        return (try? JSONDecoder().decode([CommonPortion].self, from: data)) ?? []
    }

    /// Add an alias for household correction
    func addAlias(_ alias: String) {
        let normalized = alias.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, !userAliases.contains(normalized) else { return }
        userAliases.append(normalized)
    }

    /// Macros per 100g as a MacroSummary
    var macrosPer100g: MacroSummary {
        MacroSummary(
            calories: caloriesPer100g,
            protein: proteinPer100g,
            carbs: carbsPer100g,
            fat: fatPer100g
        )
    }

    /// Calculate macros for a given weight in grams
    func macros(forGrams grams: Double) -> MacroSummary {
        let factor = grams / 100.0
        return macrosPer100g.scaled(by: factor)
    }

    /// Data type priority for ranking (higher = preferred)
    var dataTypePriority: Int {
        switch dataType {
        case "Foundation": return 3
        case "SR Legacy": return 2
        case "Survey (FNDDS)": return 1
        default: return 0 // Branded and others
        }
    }
}

// MARK: - CommonPortion

/// A standard portion size with a name and gram weight.
struct CommonPortion: Codable, Hashable, Sendable {
    /// Display name for the portion (e.g., "1 cup", "1 medium")
    let name: String

    /// Weight in grams for this portion
    let gramWeight: Double
}
