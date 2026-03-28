import CoreData

/// A shopping list item, either derived from meal plan recipes or manually added.
@objc(GroceryItem)
public class GroceryItem: NSManagedObject {

    @NSManaged public var id: UUID
    @NSManaged public var customName: String?
    @NSManaged public var quantity: Double
    @NSManaged public var unitRaw: String
    @NSManaged public var categoryRaw: String
    @NSManaged public var isChecked: Bool
    @NSManaged public var isInPantry: Bool
    @NSManaged public var isManuallyAdded: Bool
    @NSManaged public var pantryChecked: Bool
    @NSManaged public var createdAt: Date
    @NSManaged public var checkedAt: Date?

    // MARK: - Relationships

    @NSManaged public var ingredient: Ingredient?
    @NSManaged public var sourceSlots: NSSet?
    @NSManaged public var weekPlan: WeekPlan?
    @NSManaged public var checkedBy: User?

    // MARK: - Enum Wrappers

    var unit: MeasurementUnit {
        get { MeasurementUnit(rawValue: unitRaw) ?? .piece }
        set { unitRaw = newValue.rawValue }
    }

    var category: IngredientCategory {
        get { IngredientCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    // MARK: - Typed Accessors

    var sourceSlotsArray: [MealSlot] {
        (sourceSlots?.allObjects as? [MealSlot]) ?? []
    }

    // MARK: - Computed Properties

    var displayName: String {
        ingredient?.name ?? customName ?? "Unknown Item"
    }

    var formattedQuantity: String {
        if quantity.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", quantity)
        } else {
            return String(format: "%.2f", quantity)
                .replacingOccurrences(of: "\\.?0+$", with: "", options: .regularExpression)
        }
    }

    var fullDisplayString: String {
        "\(formattedQuantity) \(unit.abbreviation) \(displayName)"
    }

    var sourceMealsCount: Int { sourceSlotsArray.count }

    var sourceMealsDescription: String {
        guard !sourceSlotsArray.isEmpty else { return "" }
        return sourceSlotsArray.map { "\($0.dayOfWeek.shortName) \($0.mealType.displayName)" }.joined(separator: ", ")
    }

    // MARK: - Methods

    func check(by user: User) {
        isChecked = true
        checkedAt = Date()
        checkedBy = user
    }

    func uncheck() {
        isChecked = false
        checkedAt = nil
        checkedBy = nil
    }

    func toggleChecked(by user: User) {
        if isChecked { uncheck() } else { check(by: user) }
    }

    func markInPantry() { isInPantry = true }
    func unmarkFromPantry() { isInPantry = false }
    func togglePantry() { isInPantry.toggle() }

    func addQuantity(_ additionalQuantity: Double, from slot: MealSlot) {
        quantity += additionalQuantity
        let existing = sourceSlotsArray
        if !existing.contains(where: { $0.id == slot.id }) {
            addToSourceSlots(slot)
        }
    }

    func updateQuantity(_ newQuantity: Double) {
        quantity = newQuantity
    }

    // MARK: - NSSet Accessors

    @objc(addSourceSlotsObject:)
    @NSManaged func addToSourceSlots(_ value: MealSlot)

    @objc(removeSourceSlotsObject:)
    @NSManaged func removeFromSourceSlots(_ value: MealSlot)

    // MARK: - Convenience Initializers

    /// Creates a grocery item from an ingredient.
    @discardableResult
    convenience init(
        context: NSManagedObjectContext,
        id: UUID = UUID(),
        ingredient: Ingredient,
        quantity: Double,
        unit: MeasurementUnit,
        weekPlan: WeekPlan? = nil
    ) {
        let entity = NSEntityDescription.entity(forEntityName: "GroceryItem", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = id
        self.ingredient = ingredient
        self.customName = nil
        self.quantity = quantity
        self.unitRaw = unit.rawValue
        self.categoryRaw = ingredient.category.rawValue
        self.isChecked = false
        self.isInPantry = false
        self.isManuallyAdded = false
        self.pantryChecked = false
        self.weekPlan = weekPlan
        self.createdAt = Date()
    }

    /// Creates a manually added grocery item.
    @discardableResult
    convenience init(
        context: NSManagedObjectContext,
        id: UUID = UUID(),
        customName: String,
        quantity: Double = 1.0,
        unit: MeasurementUnit = .piece,
        category: IngredientCategory = .other,
        weekPlan: WeekPlan? = nil
    ) {
        let entity = NSEntityDescription.entity(forEntityName: "GroceryItem", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = id
        self.ingredient = nil
        self.customName = customName
        self.quantity = quantity
        self.unitRaw = unit.rawValue
        self.categoryRaw = category.rawValue
        self.isChecked = false
        self.isInPantry = false
        self.isManuallyAdded = true
        self.pantryChecked = true
        self.weekPlan = weekPlan
        self.createdAt = Date()
    }
}
