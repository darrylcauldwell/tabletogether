import CoreData
import Foundation

/// One item on a meal-slot plate, as a **value struct** — the single read model
/// for what a `MealSlot` contains, whether authored as a `MealSlotComponent` or
/// as a legacy `recipes` relationship entry.
///
/// Why a struct and not `MealSlotComponent`:
/// - Legacy slots have no component rows; synthesising a *transient*
///   `MealSlotComponent(insertInto: nil)` and setting `.recipe` would mutate the
///   persisted `Recipe`'s inverse across a nil/foreign context (crash/UB). A
///   plain struct that only *reads* properties off persisted objects avoids that.
/// - Reads reconcile stored components with un-migrated legacy recipes (see
///   `MealSlot.plateItems`) and dedupe by entity id, so duplicate component rows
///   (which CloudKit can create — `MealSlotComponent` is dedup-excluded) never
///   double-count.
///
/// `PlateItem` is intentionally **non-Sendable**: it carries managed-object
/// references and must only be used on the context/queue those objects belong to
/// (today every consumer is @MainActor / view-context).
struct PlateItem: Identifiable {
    enum Kind { case recipe, ingredient, foodItem }

    /// Dedup identity — one plate entry per underlying entity per slot.
    let id: String
    let kind: Kind
    let order: Int
    let recipe: Recipe?
    let ingredient: Ingredient?
    let foodItem: FoodItem?
    let portionScale: Double
    let quantity: Double?
    let unit: MeasurementUnit?
    let portionLabel: String?

    // MARK: - Construction

    /// From a persisted `MealSlotComponent`.
    init?(component: MealSlotComponent) {
        switch component.kind {
        case .recipe:
            guard let recipe = component.recipe else { return nil }
            self.id = "recipe:\(recipe.id.uuidString)"
            self.kind = .recipe
            self.recipe = recipe
            self.ingredient = nil
            self.foodItem = nil
        case .ingredient:
            guard let ingredient = component.ingredient else { return nil }
            self.id = "ingredient:\(ingredient.id.uuidString)"
            self.kind = .ingredient
            self.recipe = nil
            self.ingredient = ingredient
            self.foodItem = nil
        case .foodItem:
            guard let foodItem = component.foodItem else { return nil }
            self.id = "foodItem:\(foodItem.id.uuidString)"
            self.kind = .foodItem
            self.recipe = nil
            self.ingredient = nil
            self.foodItem = foodItem
        case .empty:
            return nil
        }
        self.order = Int(component.order)
        self.portionScale = component.portionScale
        self.quantity = component.quantity?.doubleValue
        self.unit = component.unit.flatMap { MeasurementUnit(rawValue: $0) }
        self.portionLabel = component.portionLabel
    }

    /// A recipe entry synthesised from a legacy `recipes` relationship entry
    /// (one full serving on the plate).
    init(legacyRecipe recipe: Recipe, order: Int) {
        self.id = "recipe:\(recipe.id.uuidString)"
        self.kind = .recipe
        self.order = order
        self.recipe = recipe
        self.ingredient = nil
        self.foodItem = nil
        self.portionScale = 1.0
        self.quantity = nil
        self.unit = nil
        self.portionLabel = nil
    }

    // MARK: - Read surface

    var displayName: String {
        switch kind {
        case .recipe: return recipe?.title ?? "Untitled recipe"
        case .ingredient: return ingredient?.name ?? "Untitled ingredient"
        case .foodItem: return foodItem?.displayName ?? "Untitled food"
        }
    }

    /// Macros contributed for ONE serving of the parent slot. `nil` when there is
    /// no usable macro data. `MealSlot.plannedMacros` multiplies by
    /// `servingsPlanned`. This is the single source of plate-item macro math —
    /// `MealSlotComponent.macrosForOneSlotServing` delegates here.
    var macrosForOneSlotServing: MacroSummary? {
        switch kind {
        case .recipe:
            guard let recipe, let perServing = recipe.macrosPerServing else { return nil }
            return MacroSummary(
                calories: perServing.calories.map { $0 * portionScale },
                protein: perServing.protein.map { $0 * portionScale },
                carbs: perServing.carbs.map { $0 * portionScale },
                fat: perServing.fat.map { $0 * portionScale }
            )
        case .ingredient:
            guard let ingredient, let cal = ingredient.caloriesPer100g?.doubleValue else { return nil }
            let grams = gramsForQuantity()
            guard grams > 0 else { return nil }
            let factor = grams / 100.0
            return MacroSummary(
                calories: cal * factor,
                protein: (ingredient.proteinPer100g?.doubleValue).map { $0 * factor },
                carbs: (ingredient.carbsPer100g?.doubleValue).map { $0 * factor },
                fat: (ingredient.fatPer100g?.doubleValue).map { $0 * factor }
            )
        case .foodItem:
            guard let foodItem else { return nil }
            let grams = gramsForQuantity()
            guard grams > 0 else { return nil }
            let factor = grams / 100.0
            return MacroSummary(
                calories: foodItem.caloriesPer100g * factor,
                protein: foodItem.proteinPer100g * factor,
                carbs: foodItem.carbsPer100g * factor,
                fat: foodItem.fatPer100g * factor
            )
        }
    }

    private func gramsForQuantity() -> Double {
        guard let qty = quantity, qty > 0 else { return 0 }
        return Self.convertToGrams(quantity: qty, unit: unit ?? .gram)
    }

    static func convertToGrams(quantity: Double, unit: MeasurementUnit) -> Double {
        switch unit {
        case .gram: return quantity
        case .kilogram: return quantity * 1000
        case .milliliter: return quantity
        case .liter: return quantity * 1000
        case .cup: return quantity * 240
        case .tablespoon: return quantity * 15
        case .teaspoon: return quantity * 5
        case .piece, .slice, .clove, .bunch, .pinch, .toTaste: return quantity * 50
        }
    }
}
