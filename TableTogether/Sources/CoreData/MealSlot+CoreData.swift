import CoreData

/// A single planned meal within a week.
/// Can contain recipes, a custom meal name, or be left empty/skipped.
@objc(MealSlot)
public class MealSlot: NSManagedObject {

    @NSManaged public var id: UUID
    @NSManaged public var dayOfWeekRaw: Int16
    @NSManaged public var mealTypeRaw: String
    @NSManaged public var customMealName: String?
    @NSManaged public var servingsPlanned: Int32
    @NSManaged public var notes: String?
    @NSManaged public var isSkipped: Bool
    @NSManaged public var createdAt: Date
    @NSManaged public var modifiedAt: Date

    // MARK: - Relationships

    @NSManaged public var weekPlan: WeekPlan?
    @NSManaged public var archetype: MealArchetype?
    @NSManaged public var recipes: NSSet?
    @NSManaged public var components: NSSet?
    @NSManaged public var assignedTo: NSSet?
    @NSManaged public var modifiedBy: User?
    @NSManaged public var groceryItems: NSSet?

    // MARK: - Enum Wrappers

    var dayOfWeek: DayOfWeek {
        get { DayOfWeek(rawValue: Int(dayOfWeekRaw)) ?? .monday }
        set { dayOfWeekRaw = Int16(newValue.rawValue) }
    }

    var mealType: MealType {
        get { MealType(rawValue: mealTypeRaw) ?? .dinner }
        set { mealTypeRaw = newValue.rawValue }
    }

    // MARK: - Typed Accessors

    var recipesArray: [Recipe] {
        (recipes?.allObjects as? [Recipe])?.sorted { $0.title < $1.title } ?? []
    }

    /// Stored MealSlotComponent rows for this slot, sorted by `order`.
    /// May be empty during the transition period — use `componentsArray` for the
    /// effective list which falls back to synthesised components from the legacy
    /// `recipes` relationship when this is empty.
    var storedComponents: [MealSlotComponent] {
        (components?.allObjects as? [MealSlotComponent])?
            .sorted { $0.order < $1.order } ?? []
    }

    var assignedToArray: [User] {
        (assignedTo?.allObjects as? [User])?.sorted { $0.displayName < $1.displayName } ?? []
    }

    var groceryItemsArray: [GroceryItem] {
        (groceryItems?.allObjects as? [GroceryItem]) ?? []
    }

    // MARK: - Computed Properties

    var displayTitle: String {
        if isSkipped { return "Skipped" }
        if !recipesArray.isEmpty {
            return recipesArray.map(\.title).joined(separator: " & ")
        }
        if let customName = customMealName, !customName.isEmpty {
            return customName
        }
        return "Unplanned"
    }

    var isPlanned: Bool {
        !isSkipped && (!recipesArray.isEmpty || customMealName?.isEmpty == false)
    }

    var isEmpty: Bool {
        !isSkipped && recipesArray.isEmpty && (customMealName?.isEmpty ?? true)
    }

    /// Aggregated macros for this meal slot — sums across all components (or legacy
    /// recipes during the transition period) and scales by `servingsPlanned`.
    /// Returns `nil` if there is no usable macro data, which the personal nutrition
    /// view should render as plain "no data" without judgement.
    var plannedMacros: MacroSummary? {
        let multiplier = Double(servingsPlanned)
        let stored = storedComponents
        if !stored.isEmpty {
            return aggregateMacros(from: stored, multiplier: multiplier)
        }
        // Legacy fallback: if no MealSlotComponent rows exist yet, walk the
        // legacy `recipes` relationship. This synthesises an equivalent
        // aggregation without persisting any new rows, so reads work for
        // CloudKit data created on older clients.
        return aggregateMacrosFromLegacyRecipes(multiplier: multiplier)
    }

    private func aggregateMacros(from components: [MealSlotComponent], multiplier: Double) -> MacroSummary? {
        var totalCalories: Double = 0
        var totalProtein: Double = 0
        var totalCarbs: Double = 0
        var totalFat: Double = 0
        var hasMacros = false

        for component in components {
            if let macros = component.macrosForOneSlotServing {
                hasMacros = true
                if let cal = macros.calories { totalCalories += cal * multiplier }
                if let prot = macros.protein { totalProtein += prot * multiplier }
                if let carb = macros.carbs { totalCarbs += carb * multiplier }
                if let f = macros.fat { totalFat += f * multiplier }
            }
        }
        guard hasMacros else { return nil }
        return MacroSummary(
            calories: totalCalories > 0 ? totalCalories : nil,
            protein: totalProtein > 0 ? totalProtein : nil,
            carbs: totalCarbs > 0 ? totalCarbs : nil,
            fat: totalFat > 0 ? totalFat : nil
        )
    }

    private func aggregateMacrosFromLegacyRecipes(multiplier: Double) -> MacroSummary? {
        let allRecipes = recipesArray
        guard !allRecipes.isEmpty else { return nil }
        var totalCalories: Double = 0
        var totalProtein: Double = 0
        var totalCarbs: Double = 0
        var totalFat: Double = 0
        var hasMacros = false
        for recipe in allRecipes {
            if let perServing = recipe.macrosPerServing {
                hasMacros = true
                if let cal = perServing.calories { totalCalories += cal * multiplier }
                if let prot = perServing.protein { totalProtein += prot * multiplier }
                if let carb = perServing.carbs { totalCarbs += carb * multiplier }
                if let f = perServing.fat { totalFat += f * multiplier }
            }
        }
        guard hasMacros else { return nil }
        return MacroSummary(
            calories: totalCalories > 0 ? totalCalories : nil,
            protein: totalProtein > 0 ? totalProtein : nil,
            carbs: totalCarbs > 0 ? totalCarbs : nil,
            fat: totalFat > 0 ? totalFat : nil
        )
    }

    var slotDescription: String {
        "\(dayOfWeek.fullName) \(mealType.displayName)"
    }

    // MARK: - Methods

    func addRecipe(_ recipe: Recipe, by user: User) {
        addToRecipes(recipe)
        self.customMealName = nil
        self.isSkipped = false
        self.modifiedAt = Date()
        self.modifiedBy = user
    }

    func removeRecipe(_ recipe: Recipe, by user: User) {
        removeFromRecipes(recipe)
        self.modifiedAt = Date()
        self.modifiedBy = user
    }

    func setCustomMeal(_ name: String, by user: User) {
        self.customMealName = name
        self.recipes = NSSet()
        self.isSkipped = false
        self.modifiedAt = Date()
        self.modifiedBy = user
    }

    func skip(by user: User) {
        self.isSkipped = true
        self.recipes = NSSet()
        self.customMealName = nil
        self.modifiedAt = Date()
        self.modifiedBy = user
    }

    func clear(by user: User) {
        self.recipes = NSSet()
        self.customMealName = nil
        self.isSkipped = false
        // Delete any plate components too, otherwise they're orphaned but still shown.
        for component in storedComponents {
            managedObjectContext?.delete(component)
        }
        self.components = NSSet()
        self.modifiedAt = Date()
        self.modifiedBy = user
    }

    func assignUsers(_ users: [User], by modifier: User) {
        self.assignedTo = NSSet(array: users)
        self.modifiedAt = Date()
        self.modifiedBy = modifier
    }

    // MARK: - NSSet Accessors

    @objc(addRecipesObject:)
    @NSManaged func addToRecipes(_ value: Recipe)

    @objc(removeRecipesObject:)
    @NSManaged func removeFromRecipes(_ value: Recipe)

    @objc(addAssignedToObject:)
    @NSManaged func addToAssignedTo(_ value: User)

    @objc(removeAssignedToObject:)
    @NSManaged func removeFromAssignedTo(_ value: User)

    @objc(addGroceryItemsObject:)
    @NSManaged func addToGroceryItems(_ value: GroceryItem)

    @objc(removeGroceryItemsObject:)
    @NSManaged func removeFromGroceryItems(_ value: GroceryItem)

    // MARK: - Convenience Initializer

    /// Deterministic ID for a meal slot within a week, derived from the
    /// canonical ISO week key plus the day and meal type. Matches the
    /// WeekPlan deterministic-ID approach — string-based, no Date or
    /// timezone arithmetic in the hash input.
    static func deterministicID(weekStartDate: Date, dayOfWeek: DayOfWeek, mealType: MealType) -> UUID {
        let weekKey = WeekPlan.isoWeekKey(for: weekStartDate)
        return UUID.deterministic(from: "mealslot:\(weekKey):\(dayOfWeek.rawValue):\(mealType.rawValue)")
    }

    @discardableResult
    convenience init(
        context: NSManagedObjectContext,
        id: UUID = UUID(),
        dayOfWeek: DayOfWeek,
        mealType: MealType,
        servingsPlanned: Int = 2,
        archetype: MealArchetype? = nil,
        customMealName: String? = nil,
        notes: String? = nil,
        isSkipped: Bool = false
    ) {
        let entity = NSEntityDescription.entity(forEntityName: "MealSlot", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = id
        self.dayOfWeekRaw = Int16(dayOfWeek.rawValue)
        self.mealTypeRaw = mealType.rawValue
        self.servingsPlanned = Int32(servingsPlanned)
        self.archetype = archetype
        self.customMealName = customMealName
        self.notes = notes
        self.isSkipped = isSkipped
        self.createdAt = Date()
        self.modifiedAt = Date()
    }
}
