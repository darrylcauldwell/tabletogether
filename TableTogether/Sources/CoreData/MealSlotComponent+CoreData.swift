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
    /// `MealSlot.plannedMacros`). Delegates to `PlateItem` so plate-item macro
    /// math has exactly one implementation, shared by stored components and
    /// legacy-recipe synthesis.
    var macrosForOneSlotServing: MacroSummary? {
        PlateItem(component: self)?.macrosForOneSlotServing
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

    /// The id of the underlying entity for this component's kind (recipe /
    /// ingredient / foodItem), or nil for an empty/corrupt row. Used as the plate
    /// dedup key and for deterministic component ids.
    var entityID: UUID? {
        switch kind {
        case .recipe: return recipe?.id
        case .ingredient: return ingredient?.id
        case .foodItem: return foodItem?.id
        case .empty: return nil
        }
    }

    /// Deterministic component id keyed by (slot, kind, entity) — NOT order, so
    /// divergent legacy membership across devices can't fork the id. Used by
    /// migration and copy-week so re-creating the same logical component
    /// produces the same id (and read-side dedup collapses any stragglers).
    static func deterministicID(slotID: UUID, kind: Kind, entityID: UUID) -> UUID {
        let kindKey: String
        switch kind {
        case .recipe: kindKey = "recipe"
        case .ingredient: kindKey = "ingredient"
        case .foodItem: kindKey = "foodItem"
        case .empty: kindKey = "empty"
        }
        return UUID.deterministic(from: "component:\(slotID.uuidString):\(kindKey):\(entityID.uuidString)")
    }

    // MARK: - Copy

    /// Creates a deep copy of this component attached to another slot (for copy-week).
    /// Setting `slot` updates the inverse `components` relationship automatically.
    /// Uses a deterministic id so a repeated copy of the same source onto the same
    /// destination converges instead of accumulating duplicate rows.
    @discardableResult
    func copy(to destinationSlot: MealSlot, in context: NSManagedObjectContext) -> MealSlotComponent {
        let entity = NSEntityDescription.entity(forEntityName: "MealSlotComponent", in: context)!
        let copy = MealSlotComponent(entity: entity, insertInto: context)
        if let entityID = self.entityID {
            copy.id = MealSlotComponent.deterministicID(slotID: destinationSlot.id, kind: self.kind, entityID: entityID)
        } else {
            copy.id = UUID()
        }
        copy.slot = destinationSlot
        copy.recipe = self.recipe
        copy.ingredient = self.ingredient
        copy.foodItem = self.foodItem
        copy.portionScale = self.portionScale
        copy.quantity = self.quantity
        copy.unit = self.unit
        copy.portionLabel = self.portionLabel
        copy.order = self.order
        copy.createdAt = Date()
        copy.modifiedAt = Date()
        return copy
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
