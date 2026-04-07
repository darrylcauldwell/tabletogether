import CoreData
import Foundation

/// One thing on a plate. A `MealSlot` aggregates one or more `MealSlotComponent`s
/// and each component is exactly one of:
///
/// - **Recipe**: a substantial home-cooked dish, with `portionScale` controlling
///   how many servings of that recipe are on the plate (`1.0` = a full serving).
/// - **Ingredient**: a simple side or staple — basmati rice, naan, butter,
///   instant noodles. Quantity is given in `quantity` + `unit`.
/// - **FoodItem**: a branded or restaurant food — Big Mac, Pot Noodle, Pret
///   wrap. `portionLabel` looks up a named portion in `FoodItem.commonPortionsData`,
///   or `quantity` (in grams) is used directly as a fallback.
///
/// The XOR rule (exactly one of recipe/ingredient/foodItem must be set) is
/// enforced by the convenience initializers, not by Core Data. Cores are
/// optional in the model so older clients can still read the entity.
///
/// Macro aggregation walks all components on a `MealSlot` and sums them via
/// `macrosForOneSlotServing` — see `MealSlot.plannedMacros`.
@objc(MealSlotComponent)
public class MealSlotComponent: NSManagedObject {

    @NSManaged public var id: UUID
    @NSManaged public var portionScale: Double
    @NSManaged public var quantity: NSNumber?
    @NSManaged public var unit: String?
    @NSManaged public var portionLabel: String?
    @NSManaged public var order: Int32
    @NSManaged public var createdAt: Date
    @NSManaged public var modifiedAt: Date

    // MARK: - Relationships

    @NSManaged public var slot: MealSlot?
    @NSManaged public var recipe: Recipe?
    @NSManaged public var ingredient: Ingredient?
    @NSManaged public var foodItem: FoodItem?

    // MARK: - Computed Properties

    /// Which kind of component this is, derived from which relationship is set.
    /// Returns `.empty` if none are set (a corrupted row); the macro aggregator
    /// will skip such rows.
    var kind: Kind {
        if recipe != nil { return .recipe }
        if ingredient != nil { return .ingredient }
        if foodItem != nil { return .foodItem }
        return .empty
    }

    enum Kind {
        case recipe
        case ingredient
        case foodItem
        case empty
    }

    /// User-facing display name for this component, regardless of kind.
    var displayName: String {
        switch kind {
        case .recipe: return recipe?.title ?? "Untitled recipe"
        case .ingredient: return ingredient?.name ?? "Untitled ingredient"
        case .foodItem: return foodItem?.displayName ?? "Untitled food"
        case .empty: return "(empty component)"
        }
    }

    /// Macros contributed by this component for ONE serving of the parent meal
    /// slot (the slot's `servingsPlanned` multiplier is applied later, in
    /// `MealSlot.plannedMacros`).
    ///
    /// Returns `nil` if there is no usable macro data — e.g. an ingredient with
    /// no calorie data, or a foodItem with no quantity. The aggregator skips
    /// nil contributions.
    var macrosForOneSlotServing: MacroSummary? {
        switch kind {
        case .recipe:
            guard let recipe, let perServing = recipe.macrosPerServing else { return nil }
            // portionScale = 1.0 means one full serving of the recipe per slot serving
            return MacroSummary(
                calories: perServing.calories.map { $0 * portionScale },
                protein:  perServing.protein.map  { $0 * portionScale },
                carbs:    perServing.carbs.map    { $0 * portionScale },
                fat:      perServing.fat.map      { $0 * portionScale }
            )

        case .ingredient:
            guard let ingredient,
                  let cal = ingredient.caloriesPer100g?.doubleValue
            else { return nil }
            let grams = gramsForCurrentQuantity()
            guard grams > 0 else { return nil }
            let factor = grams / 100.0
            return MacroSummary(
                calories: cal * factor,
                protein:  (ingredient.proteinPer100g?.doubleValue).map { $0 * factor },
                carbs:    (ingredient.carbsPer100g?.doubleValue).map   { $0 * factor },
                fat:      (ingredient.fatPer100g?.doubleValue).map     { $0 * factor }
            )

        case .foodItem:
            guard let foodItem else { return nil }
            let grams = gramsForCurrentQuantity()
            guard grams > 0 else { return nil }
            let factor = grams / 100.0
            return MacroSummary(
                calories: foodItem.caloriesPer100g * factor,
                protein:  foodItem.proteinPer100g * factor,
                carbs:    foodItem.carbsPer100g * factor,
                fat:      foodItem.fatPer100g * factor
            )

        case .empty:
            return nil
        }
    }

    /// Convert this component's quantity into grams for ingredient / foodItem
    /// macro math. Returns 0 if the quantity is missing or zero.
    func gramsForCurrentQuantity() -> Double {
        guard let qty = quantity?.doubleValue, qty > 0 else { return 0 }
        let unitEnum = MeasurementUnit(rawValue: unit ?? "gram") ?? .gram
        return Self.convertToGrams(quantity: qty, unit: unitEnum)
    }

    private static func convertToGrams(quantity: Double, unit: MeasurementUnit) -> Double {
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

    // MARK: - Convenience Initializers

    /// Create a recipe component (a portion of a recipe on the plate).
    @discardableResult
    convenience init(
        context: NSManagedObjectContext,
        slot: MealSlot,
        recipe: Recipe,
        portionScale: Double = 1.0,
        order: Int = 0
    ) {
        let entity = NSEntityDescription.entity(forEntityName: "MealSlotComponent", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        self.slot = slot
        self.recipe = recipe
        self.portionScale = portionScale
        self.order = Int32(order)
        self.createdAt = Date()
        self.modifiedAt = Date()
    }

    /// Create an ingredient component (a side / staple / fast food at home).
    @discardableResult
    convenience init(
        context: NSManagedObjectContext,
        slot: MealSlot,
        ingredient: Ingredient,
        quantity: Double,
        unit: MeasurementUnit,
        order: Int = 0
    ) {
        let entity = NSEntityDescription.entity(forEntityName: "MealSlotComponent", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        self.slot = slot
        self.ingredient = ingredient
        self.quantity = NSNumber(value: quantity)
        self.unit = unit.rawValue
        self.portionScale = 1.0
        self.order = Int32(order)
        self.createdAt = Date()
        self.modifiedAt = Date()
    }

    /// Create a foodItem component (a branded / packaged / restaurant food).
    @discardableResult
    convenience init(
        context: NSManagedObjectContext,
        slot: MealSlot,
        foodItem: FoodItem,
        quantity: Double,
        unit: MeasurementUnit = .gram,
        portionLabel: String? = nil,
        order: Int = 0
    ) {
        let entity = NSEntityDescription.entity(forEntityName: "MealSlotComponent", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        self.slot = slot
        self.foodItem = foodItem
        self.quantity = NSNumber(value: quantity)
        self.unit = unit.rawValue
        self.portionLabel = portionLabel
        self.portionScale = 1.0
        self.order = Int32(order)
        self.createdAt = Date()
        self.modifiedAt = Date()
    }
}
