import Foundation
import SwiftData

// MARK: - MealSlot Model

/// A single planned meal within a week.
/// Can contain a recipe, custom meal name, or be left empty/skipped.
@Model
final class MealSlot {
    /// Primary identifier
    @Attribute(.unique) var id: UUID

    /// Day of the week for this slot
    var dayOfWeek: DayOfWeek

    /// Type of meal (breakfast, lunch, dinner, snack)
    var mealType: MealType

    /// Custom meal name for non-recipe meals (e.g., "Eating out", "Leftovers")
    var customMealName: String?

    /// Number of servings planned for this meal
    var servingsPlanned: Int

    /// Household notes for this meal slot
    var notes: String?

    /// Whether this slot is explicitly marked as skip
    var isSkipped: Bool

    /// Creation timestamp
    var createdAt: Date

    /// Last modification timestamp
    var modifiedAt: Date

    // MARK: - Relationships

    /// Parent week plan
    @Relationship
    var weekPlan: WeekPlan?

    /// Optional archetype assignment for this slot
    @Relationship
    var archetype: MealArchetype?

    /// Assigned recipes (empty = unplanned or custom meal)
    @Relationship
    var recipes: [Recipe] = []

    /// Users assigned to eat this meal
    @Relationship
    var assignedTo: [User] = []

    /// User who last modified this slot (for conflict resolution)
    @Relationship
    var modifiedBy: User?

    // Note: Meal logs are stored in CloudKit private database (PrivateMealLog)
    // and reference this slot by ID only - no SwiftData relationship needed.

    /// Grocery items derived from this slot
    @Relationship(inverse: \GroceryItem.sourceSlots)
    var groceryItems: [GroceryItem] = []

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        dayOfWeek: DayOfWeek,
        mealType: MealType,
        servingsPlanned: Int = 2,
        archetype: MealArchetype? = nil,
        recipes: [Recipe] = [],
        customMealName: String? = nil,
        notes: String? = nil,
        isSkipped: Bool = false
    ) {
        self.id = id
        self.dayOfWeek = dayOfWeek
        self.mealType = mealType
        self.servingsPlanned = servingsPlanned
        self.archetype = archetype
        self.recipes = recipes
        self.customMealName = customMealName
        self.notes = notes
        self.isSkipped = isSkipped
        self.createdAt = Date()
        self.modifiedAt = Date()
    }

    // MARK: - Computed Properties

    /// Display title for the meal slot
    var displayTitle: String {
        if isSkipped {
            return "Skipped"
        }
        if !recipes.isEmpty {
            return recipes.map(\.title).joined(separator: " & ")
        }
        if let customName = customMealName, !customName.isEmpty {
            return customName
        }
        return "Unplanned"
    }

    /// Whether this slot has a meal assigned (recipe or custom)
    var isPlanned: Bool {
        !isSkipped && (!recipes.isEmpty || customMealName?.isEmpty == false)
    }

    /// Whether this slot is empty (no recipe, no custom name, not skipped)
    var isEmpty: Bool {
        !isSkipped && recipes.isEmpty && (customMealName?.isEmpty ?? true)
    }

    /// Macros for this slot based on assigned recipes and servings
    var plannedMacros: MacroSummary? {
        guard !recipes.isEmpty else { return nil }

        let multiplier = Double(servingsPlanned)
        var totalCalories: Double = 0
        var totalProtein: Double = 0
        var totalCarbs: Double = 0
        var totalFat: Double = 0
        var hasMacros = false

        for recipe in recipes {
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

    /// Formatted day and meal type display
    var slotDescription: String {
        "\(dayOfWeek.fullName) \(mealType.displayName)"
    }

    // MARK: - Methods

    /// Adds a recipe to this slot (appends to existing recipes)
    func addRecipe(_ recipe: Recipe, by user: User) {
        self.recipes.append(recipe)
        self.customMealName = nil
        self.isSkipped = false
        self.modifiedAt = Date()
        self.modifiedBy = user
    }

    /// Removes a specific recipe from this slot
    func removeRecipe(_ recipe: Recipe, by user: User) {
        self.recipes.removeAll { $0.id == recipe.id }
        self.modifiedAt = Date()
        self.modifiedBy = user
    }

    /// Sets a custom meal name (clears any assigned recipes)
    func setCustomMeal(_ name: String, by user: User) {
        self.customMealName = name
        self.recipes = []
        self.isSkipped = false
        self.modifiedAt = Date()
        self.modifiedBy = user
    }

    /// Marks this slot as skipped
    func skip(by user: User) {
        self.isSkipped = true
        self.recipes = []
        self.customMealName = nil
        self.modifiedAt = Date()
        self.modifiedBy = user
    }

    /// Clears this slot (makes it unplanned)
    func clear(by user: User) {
        self.recipes = []
        self.customMealName = nil
        self.isSkipped = false
        self.modifiedAt = Date()
        self.modifiedBy = user
    }

    /// Assigns users to this meal
    func assignUsers(_ users: [User], by modifier: User) {
        self.assignedTo = users
        self.modifiedAt = Date()
        self.modifiedBy = modifier
    }
}
