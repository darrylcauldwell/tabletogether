import CoreData

/// Container for a week's meal slots.
/// Each week plan starts on Monday and contains all meal slots for that week.
@objc(WeekPlan)
public class WeekPlan: NSManagedObject {

    @NSManaged public var id: UUID
    @NSManaged public var weekStartDate: Date
    @NSManaged public var householdNote: String?
    @NSManaged public var statusRaw: String
    @NSManaged public var createdAt: Date
    @NSManaged public var modifiedAt: Date

    // MARK: - Relationships

    @NSManaged public var slots: NSSet?
    @NSManaged public var groceryItems: NSSet?
    @NSManaged public var household: Household?

    // MARK: - Enum Wrapper

    var status: WeekPlanStatus {
        get { WeekPlanStatus(rawValue: statusRaw) ?? .draft }
        set { statusRaw = newValue.rawValue }
    }

    // MARK: - Typed Accessors

    var slotsArray: [MealSlot] {
        (slots?.allObjects as? [MealSlot]) ?? []
    }

    var groceryItemsArray: [GroceryItem] {
        (groceryItems?.allObjects as? [GroceryItem]) ?? []
    }

    // MARK: - Computed Properties

    var weekEndDate: Date {
        Calendar.current.date(byAdding: .day, value: 6, to: weekStartDate) ?? weekStartDate
    }

    var weekRangeDisplay: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        let start = formatter.string(from: weekStartDate)
        let yearFormatter = DateFormatter()
        yearFormatter.dateFormat = "d, yyyy"
        let end = yearFormatter.string(from: weekEndDate)
        return "\(start) - \(end)"
    }

    var shortWeekDisplay: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return "Week of \(formatter.string(from: weekStartDate))"
    }

    var plannedSlots: [MealSlot] { slotsArray.filter { $0.isPlanned } }
    var emptySlots: [MealSlot] { slotsArray.filter { $0.isEmpty } }

    var planningProgress: Double {
        let allSlots = slotsArray
        guard !allSlots.isEmpty else { return 0.0 }
        let nonSkipped = allSlots.filter { !$0.isSkipped }
        guard !nonSkipped.isEmpty else { return 1.0 }
        return Double(plannedSlots.count) / Double(nonSkipped.count)
    }

    var plannedMealsCount: Int { plannedSlots.count }
    var activeSlotsCount: Int { slotsArray.filter { !$0.isSkipped }.count }

    var isCurrentWeek: Bool {
        Calendar.current.isDate(Date(), equalTo: weekStartDate, toGranularity: .weekOfYear)
    }

    var uniqueRecipes: [Recipe] {
        Array(Set(slotsArray.flatMap { $0.recipesArray }))
    }

    // MARK: - Methods

    static func normalizeToMonday(_ date: Date) -> Date {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        components.weekday = 2
        return calendar.date(from: components) ?? date
    }

    func slots(for day: DayOfWeek) -> [MealSlot] {
        slotsArray.filter { $0.dayOfWeek == day }
            .sorted { $0.mealType.rawValue < $1.mealType.rawValue }
    }

    func slot(for day: DayOfWeek, mealType: MealType) -> MealSlot? {
        slotsArray.first { $0.dayOfWeek == day && $0.mealType == mealType }
    }

    func createDefaultSlots(context: NSManagedObjectContext, mealTypes: [MealType] = MealType.defaultPlannedMeals) {
        for day in DayOfWeek.allCases {
            for mealType in mealTypes {
                let slotID = MealSlot.deterministicID(
                    weekStartDate: weekStartDate,
                    dayOfWeek: day,
                    mealType: mealType
                )
                let slot = MealSlot(context: context, id: slotID, dayOfWeek: day, mealType: mealType)
                slot.weekPlan = self
                addToSlots(slot)
            }
        }
        modifiedAt = Date()
    }

    func activate() {
        status = .active
        modifiedAt = Date()
    }

    func complete() {
        status = .completed
        modifiedAt = Date()
    }

    func copyFrom(_ otherPlan: WeekPlan, by user: User) {
        for otherSlot in otherPlan.slotsArray {
            if let matchingSlot = slot(for: otherSlot.dayOfWeek, mealType: otherSlot.mealType) {
                if !otherSlot.recipesArray.isEmpty {
                    matchingSlot.recipes = otherSlot.recipes
                    matchingSlot.customMealName = nil
                    matchingSlot.isSkipped = false
                    matchingSlot.modifiedAt = Date()
                    matchingSlot.modifiedBy = user
                } else if let customName = otherSlot.customMealName {
                    matchingSlot.setCustomMeal(customName, by: user)
                }
                matchingSlot.servingsPlanned = otherSlot.servingsPlanned
                matchingSlot.archetype = otherSlot.archetype
            }
        }
        modifiedAt = Date()
    }

    func clearAll(by user: User) {
        for slot in slotsArray {
            slot.clear(by: user)
        }
        modifiedAt = Date()
    }

    func date(for day: DayOfWeek) -> Date {
        let daysToAdd = day.rawValue - 1
        return Calendar.current.date(byAdding: .day, value: daysToAdd, to: weekStartDate) ?? weekStartDate
    }

    // MARK: - Grocery List & Pantry

    var groceryItemsByCategory: [IngredientCategory: [GroceryItem]] {
        Dictionary(grouping: groceryItemsArray) { $0.category }
    }

    var uncheckedGroceryItems: [GroceryItem] { groceryItemsArray.filter { !$0.isChecked } }
    var checkedGroceryItems: [GroceryItem] { groceryItemsArray.filter { $0.isChecked } }

    var groceryProgress: Double {
        let items = groceryItemsArray
        guard !items.isEmpty else { return 0.0 }
        return Double(items.filter { $0.isChecked }.count) / Double(items.count)
    }

    var pantryCheckItems: [GroceryItem] { groceryItemsArray.filter { !$0.isManuallyAdded } }
    var inPantryItems: [GroceryItem] { groceryItemsArray.filter { $0.isInPantry } }
    var shoppingListItems: [GroceryItem] { groceryItemsArray.filter { $0.pantryChecked && !$0.isInPantry } }
    var unpurchasedShoppingItems: [GroceryItem] { groceryItemsArray.filter { $0.pantryChecked && !$0.isInPantry && !$0.isChecked } }

    var shoppingProgress: Double {
        let items = shoppingListItems
        guard !items.isEmpty else { return 0.0 }
        return Double(items.filter { $0.isChecked }.count) / Double(items.count)
    }

    var pantryCheckProgress: Double {
        let items = pantryCheckItems
        guard !items.isEmpty else { return 0.0 }
        return Double(items.filter { $0.isInPantry }.count) / Double(items.count)
    }

    // MARK: - Grocery List Generation

    func generateGroceryList(context: NSManagedObjectContext) {
        var neededIngredients: [UUID: (ingredient: Ingredient, quantity: Double, unit: MeasurementUnit, slots: [MealSlot])] = [:]

        for slot in plannedSlots {
            for recipe in slot.recipesArray {
                for ri in recipe.recipeIngredientsArray {
                    guard let ingredient = ri.ingredient else { continue }
                    let scaled = ri.scaledQuantity(originalServings: Int(recipe.servings), newServings: Int(slot.servingsPlanned))
                    if var entry = neededIngredients[ingredient.id] {
                        entry.quantity += scaled
                        entry.slots.append(slot)
                        neededIngredients[ingredient.id] = entry
                    } else {
                        neededIngredients[ingredient.id] = (ingredient, scaled, ri.unit, [slot])
                    }
                }
            }
        }

        // Index existing derived items
        var existingByIngredient: [UUID: GroceryItem] = [:]
        var duplicates: [GroceryItem] = []
        for item in groceryItemsArray where !item.isManuallyAdded {
            if let ingredientID = item.ingredient?.id {
                if existingByIngredient[ingredientID] == nil {
                    existingByIngredient[ingredientID] = item
                } else {
                    duplicates.append(item)
                }
            }
        }

        // Update existing or create new
        var keepIDs = Set<UUID>()
        for (ingredientID, info) in neededIngredients {
            keepIDs.insert(ingredientID)
            if let existing = existingByIngredient[ingredientID] {
                existing.quantity = info.quantity
                existing.unit = info.unit
                existing.sourceSlots = NSSet(array: info.slots)
            } else {
                let newItem = GroceryItem(context: context, ingredient: info.ingredient, quantity: info.quantity, unit: info.unit)
                newItem.sourceSlots = NSSet(array: info.slots)
                newItem.weekPlan = self
                addToGroceryItems(newItem)
            }
        }

        // Remove obsolete
        for (ingredientID, item) in existingByIngredient where !keepIDs.contains(ingredientID) {
            duplicates.append(item)
        }
        for item in duplicates {
            item.weekPlan = nil
            removeFromGroceryItems(item)
            context.delete(item)
        }

        modifiedAt = Date()
    }

    func cleanupOrphanedGroceryItems(context: NSManagedObjectContext) {
        let request = NSFetchRequest<GroceryItem>(entityName: "GroceryItem")
        request.predicate = NSPredicate(format: "weekPlan == nil AND isManuallyAdded == NO")
        if let orphans = try? context.fetch(request) {
            for item in orphans {
                context.delete(item)
            }
        }
    }

    // MARK: - NSSet Accessors

    @objc(addSlotsObject:)
    @NSManaged func addToSlots(_ value: MealSlot)

    @objc(removeSlotsObject:)
    @NSManaged func removeFromSlots(_ value: MealSlot)

    @objc(addGroceryItemsObject:)
    @NSManaged func addToGroceryItems(_ value: GroceryItem)

    @objc(removeGroceryItemsObject:)
    @NSManaged func removeFromGroceryItems(_ value: GroceryItem)

    // MARK: - Convenience Initializer

    /// Deterministic ID for a week plan, derived from its normalized start date.
    /// Ensures all devices generate the same UUID for the same week.
    static func deterministicID(for weekStartDate: Date) -> UUID {
        let normalized = Self.normalizeToMonday(weekStartDate)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return UUID.deterministic(from: "weekplan:\(formatter.string(from: normalized))")
    }

    @discardableResult
    convenience init(
        context: NSManagedObjectContext,
        id: UUID? = nil,
        weekStartDate: Date,
        householdNote: String? = nil,
        status: WeekPlanStatus = .draft
    ) {
        let entity = NSEntityDescription.entity(forEntityName: "WeekPlan", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = id ?? Self.deterministicID(for: weekStartDate)
        self.weekStartDate = Self.normalizeToMonday(weekStartDate)
        self.householdNote = householdNote
        self.statusRaw = status.rawValue
        self.createdAt = Date()
        self.modifiedAt = Date()
    }
}
