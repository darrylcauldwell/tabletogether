import Foundation
import CoreData

/// A portable, Codable representation of a `FoodItem` for JSON export/import.
///
/// Mirrors `CodableRecipe` in spirit — the JSON shape is intended to be hand-curated
/// or programmatically generated, then imported via `FoodItemImporter`. All
/// nutrition fields are required because the value of pre-seeding a food item is
/// to have authoritative macros from day one.
///
/// **Example JSON:**
/// ```json
/// {
///   "displayName": "Chicken breast (raw)",
///   "dataType": "Foundation",
///   "caloriesPer100g": 120,
///   "proteinPer100g": 22.5,
///   "carbsPer100g": 0,
///   "fatPer100g": 2.6,
///   "userAliases": ["chicken breast", "chicken fillet"],
///   "fdcId": 174616
/// }
/// ```
///
/// **Required fields:** `displayName`, `caloriesPer100g`, `proteinPer100g`,
/// `carbsPer100g`, `fatPer100g`. Everything else is optional and defaults to
/// sensible values described in `toFoodItem(...)`.
struct CodableFoodItem: Codable {
    var displayName: String
    var dataType: String?           // "Foundation", "SR Legacy", "Survey (FNDDS)", "Branded", or custom
    var brandOwner: String?
    var fdcId: Int?                 // USDA Food Data Central ID; 0 / nil for custom entries
    var usdaDescription: String?    // Original USDA description; falls back to displayName

    var caloriesPer100g: Double
    var proteinPer100g: Double
    var carbsPer100g: Double
    var fatPer100g: Double
    var fiberPer100g: Double?
    var sugarPer100g: Double?
    var sodiumMgPer100g: Double?

    var userAliases: [String]?

    /// Round-trip from a Core Data `FoodItem`. Used to support future
    /// "Export Food Items" affordances symmetric with the recipe export.
    init(from foodItem: FoodItem) {
        self.displayName = foodItem.displayName
        self.dataType = foodItem.dataType
        self.brandOwner = foodItem.brandOwner
        self.fdcId = Int(foodItem.fdcId)
        self.usdaDescription = foodItem.usdaDescription
        self.caloriesPer100g = foodItem.caloriesPer100g
        self.proteinPer100g = foodItem.proteinPer100g
        self.carbsPer100g = foodItem.carbsPer100g
        self.fatPer100g = foodItem.fatPer100g
        self.fiberPer100g = foodItem.fiberPer100g?.doubleValue
        self.sugarPer100g = foodItem.sugarPer100g?.doubleValue
        self.sodiumMgPer100g = foodItem.sodiumMgPer100g?.doubleValue
        self.userAliases = foodItem.userAliasesList.isEmpty ? nil : foodItem.userAliasesList
    }

    /// Create a Core Data `FoodItem` from this portable representation.
    /// Caller is responsible for assigning `household` and saving the context.
    @discardableResult
    func toFoodItem(context: NSManagedObjectContext) -> FoodItem {
        let foodItem = FoodItem(
            context: context,
            fdcId: fdcId ?? 0,
            usdaDescription: usdaDescription ?? displayName,
            displayName: displayName,
            dataType: dataType ?? "Custom",
            brandOwner: brandOwner,
            caloriesPer100g: caloriesPer100g,
            proteinPer100g: proteinPer100g,
            carbsPer100g: carbsPer100g,
            fatPer100g: fatPer100g,
            fiberPer100g: fiberPer100g,
            sugarPer100g: sugarPer100g,
            sodiumMgPer100g: sodiumMgPer100g,
            userAliases: userAliases ?? []
        )
        return foodItem
    }
}
