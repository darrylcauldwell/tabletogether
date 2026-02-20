import Foundation
import SwiftData

/// A shopping list item, either derived from meal plan recipes or manually added.
/// Supports aggregation of ingredients across multiple meals.
@Model
final class GroceryItem {
    /// Primary identifier
    @Attribute(.unique) var id: UUID

    /// Custom name for non-ingredient items (e.g., "Paper towels")
    var customName: String?

    /// Amount needed
    var quantity: Double

    /// Unit of measurement
    var unit: MeasurementUnit

    /// Category for grouping in list (matches store layout)
    var category: IngredientCategory

    /// Whether item has been purchased
    var isChecked: Bool

    /// Whether the user already has this item at home (pantry check)
    var isInPantry: Bool

    /// Whether this was manually added vs. derived from recipes
    var isManuallyAdded: Bool

    /// Whether this item has been through the pantry check process.
    /// Recipe-derived items start as false and only appear on the shopping list
    /// once pantry check is completed (individually or via "All remaining needed").
    /// Manual items start as true (they go straight to the shopping list).
    var pantryChecked: Bool = false

    /// Creation timestamp
    var createdAt: Date

    /// When the item was checked off
    var checkedAt: Date?

    // MARK: - Relationships

    /// Linked ingredient (nil for manual non-ingredient items)
    @Relationship
    var ingredient: Ingredient?

    /// Which meal slots need this item
    @Relationship
    var sourceSlots: [MealSlot] = []

    /// Parent week plan
    @Relationship
    var weekPlan: WeekPlan?

    /// User who checked this item off
    @Relationship
    var checkedBy: User?

    // MARK: - Initialization

    /// Creates a grocery item from an ingredient
    init(
        id: UUID = UUID(),
        ingredient: Ingredient,
        quantity: Double,
        unit: MeasurementUnit,
        weekPlan: WeekPlan? = nil
    ) {
        self.id = id
        self.ingredient = ingredient
        self.customName = nil
        self.quantity = quantity
        self.unit = unit
        self.category = ingredient.category
        self.isChecked = false
        self.isInPantry = false
        self.isManuallyAdded = false
        self.pantryChecked = false
        self.weekPlan = weekPlan
        self.createdAt = Date()
        self.checkedAt = nil
    }

    /// Creates a manually added grocery item
    init(
        id: UUID = UUID(),
        customName: String,
        quantity: Double = 1.0,
        unit: MeasurementUnit = .piece,
        category: IngredientCategory = .other,
        weekPlan: WeekPlan? = nil
    ) {
        self.id = id
        self.ingredient = nil
        self.customName = customName
        self.quantity = quantity
        self.unit = unit
        self.category = category
        self.isChecked = false
        self.isInPantry = false
        self.isManuallyAdded = true
        self.pantryChecked = true
        self.weekPlan = weekPlan
        self.createdAt = Date()
        self.checkedAt = nil
    }

    // MARK: - Computed Properties

    /// Display name (ingredient name or custom name)
    var displayName: String {
        if let ingredient = ingredient {
            return ingredient.name
        }
        return customName ?? "Unknown Item"
    }

    /// Formatted quantity string (removes unnecessary decimals)
    var formattedQuantity: String {
        if quantity.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", quantity)
        } else {
            return String(format: "%.2f", quantity)
                .replacingOccurrences(of: "\\.?0+$", with: "", options: .regularExpression)
        }
    }

    /// Full display string including quantity and unit
    var fullDisplayString: String {
        "\(formattedQuantity) \(unit.abbreviation) \(displayName)"
    }

    /// Number of meals that need this item
    var sourceMealsCount: Int {
        sourceSlots.count
    }

    /// Description of which meals need this item
    var sourceMealsDescription: String {
        guard !sourceSlots.isEmpty else { return "" }

        let mealDescriptions = sourceSlots.map { slot in
            "\(slot.dayOfWeek.shortName) \(slot.mealType.displayName)"
        }

        return mealDescriptions.joined(separator: ", ")
    }

    // MARK: - Methods

    /// Checks off this item
    func check(by user: User) {
        isChecked = true
        checkedAt = Date()
        checkedBy = user
    }

    /// Unchecks this item
    func uncheck() {
        isChecked = false
        checkedAt = nil
        checkedBy = nil
    }

    /// Toggles the checked state
    func toggleChecked(by user: User) {
        if isChecked {
            uncheck()
        } else {
            check(by: user)
        }
    }

    /// Marks this item as already in the pantry
    func markInPantry() {
        isInPantry = true
    }

    /// Removes the pantry mark from this item
    func unmarkFromPantry() {
        isInPantry = false
    }

    /// Toggles the pantry state
    func togglePantry() {
        isInPantry.toggle()
    }

    /// Adds quantity from another source
    func addQuantity(_ additionalQuantity: Double, from slot: MealSlot) {
        quantity += additionalQuantity
        if !sourceSlots.contains(where: { $0.id == slot.id }) {
            sourceSlots.append(slot)
        }
    }

    /// Updates quantity
    func updateQuantity(_ newQuantity: Double) {
        quantity = newQuantity
    }
}

// MARK: - Grocery List Generation

extension WeekPlan {
    /// Generates grocery items from all planned meals in this week.
    ///
    /// Uses an in-place update strategy: existing items are updated with new
    /// quantities rather than deleted and recreated. This preserves pantry/checked
    /// state and avoids SwiftData issues where `removeAll(where:)` on relationship
    /// arrays does not properly persist removals, and `modelContext.delete()` can
    /// crash SwiftUI when views still reference the deleted objects.
    func generateGroceryList() {
        // 1. Aggregate what's needed from planned recipes
        var neededIngredients: [UUID: (ingredient: Ingredient, quantity: Double, unit: MeasurementUnit, slots: [MealSlot])] = [:]

        for slot in plannedSlots {
            guard !slot.recipes.isEmpty else { continue }

            for recipe in slot.recipes {
                for recipeIngredient in recipe.recipeIngredients {
                    guard let ingredient = recipeIngredient.ingredient else { continue }

                    let scaledQuantity = recipeIngredient.scaledQuantity(
                        originalServings: recipe.servings,
                        newServings: slot.servingsPlanned
                    )

                    if var entry = neededIngredients[ingredient.id] {
                        entry.quantity += scaledQuantity
                        entry.slots.append(slot)
                        neededIngredients[ingredient.id] = entry
                    } else {
                        neededIngredients[ingredient.id] = (ingredient, scaledQuantity, recipeIngredient.unit, [slot])
                    }
                }
            }
        }

        // 2. Index existing derived items by ingredient; collect duplicates
        var existingByIngredient: [UUID: GroceryItem] = [:]
        var duplicates: [GroceryItem] = []
        for item in groceryItems where !item.isManuallyAdded {
            if let ingredientID = item.ingredient?.id {
                if existingByIngredient[ingredientID] == nil {
                    existingByIngredient[ingredientID] = item
                } else {
                    // Duplicate from a previous generation bug — mark for removal
                    duplicates.append(item)
                }
            }
        }

        // 3. Update existing items in-place or create new ones
        var keepIngredientIDs = Set<UUID>()
        for (ingredientID, info) in neededIngredients {
            keepIngredientIDs.insert(ingredientID)
            if let existingItem = existingByIngredient[ingredientID] {
                // Update in place — preserves isInPantry, isChecked, pantryChecked state
                existingItem.quantity = info.quantity
                existingItem.unit = info.unit
                existingItem.sourceSlots = info.slots
            } else {
                // Create new item
                let newItem = GroceryItem(
                    ingredient: info.ingredient,
                    quantity: info.quantity,
                    unit: info.unit
                )
                newItem.sourceSlots = info.slots
                newItem.weekPlan = self
                groceryItems.append(newItem)
            }
        }

        // 4. Collect items for ingredients no longer in any recipe
        for (ingredientID, item) in existingByIngredient where !keepIngredientIDs.contains(ingredientID) {
            duplicates.append(item)
        }

        // 5. Remove duplicates and obsolete items safely.
        //    Clear the inverse relationship first so they become orphans,
        //    then remove from the forward relationship array.
        for item in duplicates {
            item.weekPlan = nil
        }
        let duplicateIDs = Set(duplicates.map(\.id))
        groceryItems = groceryItems.filter { !duplicateIDs.contains($0.id) }

        modifiedAt = Date()
    }

    /// Removes orphaned grocery items (weekPlan == nil, not manually added)
    /// from the model context. Call from a view's .task or .onAppear for safe cleanup.
    func cleanupOrphanedGroceryItems(context: ModelContext) {
        let descriptor = FetchDescriptor<GroceryItem>()
        guard let allItems = try? context.fetch(descriptor) else { return }
        for item in allItems where item.weekPlan == nil && !item.isManuallyAdded {
            context.delete(item)
        }
    }

    /// Gets grocery items grouped by category
    var groceryItemsByCategory: [IngredientCategory: [GroceryItem]] {
        Dictionary(grouping: groceryItems) { $0.category }
    }

    /// Gets unchecked grocery items
    var uncheckedGroceryItems: [GroceryItem] {
        groceryItems.filter { !$0.isChecked }
    }

    /// Gets checked grocery items
    var checkedGroceryItems: [GroceryItem] {
        groceryItems.filter { $0.isChecked }
    }

    /// Progress of grocery shopping (0.0 to 1.0)
    var groceryProgress: Double {
        guard !groceryItems.isEmpty else { return 0.0 }
        return Double(checkedGroceryItems.count) / Double(groceryItems.count)
    }

    // MARK: - Pantry & Shopping List

    /// Recipe-derived items for the pantry check (excludes manually added)
    var pantryCheckItems: [GroceryItem] {
        groceryItems.filter { !$0.isManuallyAdded }
    }

    /// Items marked as already in pantry
    var inPantryItems: [GroceryItem] {
        groceryItems.filter { $0.isInPantry }
    }

    /// Items for the shopping list — only items that have been through pantry check
    /// (or manually added) and are not marked as already in pantry.
    var shoppingListItems: [GroceryItem] {
        groceryItems.filter { $0.pantryChecked && !$0.isInPantry }
    }

    /// Unpurchased shopping items (pantry-checked, not in pantry, not checked off)
    var unpurchasedShoppingItems: [GroceryItem] {
        groceryItems.filter { $0.pantryChecked && !$0.isInPantry && !$0.isChecked }
    }

    /// Progress of shopping (purchased / total shopping items, 0.0 to 1.0)
    var shoppingProgress: Double {
        let items = shoppingListItems
        guard !items.isEmpty else { return 0.0 }
        let purchased = items.filter { $0.isChecked }.count
        return Double(purchased) / Double(items.count)
    }

    /// Progress of pantry check (in-pantry / total pantry check items, 0.0 to 1.0)
    var pantryCheckProgress: Double {
        let items = pantryCheckItems
        guard !items.isEmpty else { return 0.0 }
        let inPantry = items.filter { $0.isInPantry }.count
        return Double(inPantry) / Double(items.count)
    }
}
