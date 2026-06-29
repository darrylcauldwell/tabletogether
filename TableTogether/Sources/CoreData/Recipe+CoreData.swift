import CoreData
import UniformTypeIdentifiers

/// A complete recipe with ingredients, instructions, and metadata.
/// Recipes belong to the shared household library.
@objc(Recipe)
public class Recipe: NSManagedObject {

    @NSManaged public var id: UUID
    @NSManaged public var title: String
    @NSManaged public var summary: String?
    @NSManaged public var sourceURL: URL?
    @NSManaged public var cookbook: String?
    @NSManaged public var imageURL: URL?
    @NSManaged public var servings: Int32
    @NSManaged public var prepTimeMinutes: Int32
    @NSManaged public var cookTimeMinutes: Int32
    @NSManaged public var imageData: Data?
    @NSManaged public var isFavorite: Bool
    @NSManaged public var timesCooked: Int32
    @NSManaged public var lastCookedDate: Date?
    @NSManaged public var createdAt: Date
    @NSManaged public var modifiedAt: Date

    // Stored as Transformable [String] via NSSecureUnarchiveFromDataTransformer
    @NSManaged public var instructions: [String]?
    @NSManaged public var tags: [String]?
    @NSManaged public var suggestedArchetypesRaw: [String]?

    // MARK: - Relationships

    @NSManaged public var recipeIngredients: NSSet?
    @NSManaged public var mealSlots: NSSet?
    @NSManaged public var mealSlotComponents: NSSet?
    @NSManaged public var createdBy: User?
    @NSManaged public var suggestionMemory: SuggestionMemory?
    @NSManaged public var household: Household?

    // MARK: - Enum Wrapper

    var suggestedArchetypes: [ArchetypeType] {
        get { (suggestedArchetypesRaw ?? []).compactMap { ArchetypeType(rawValue: $0) } }
        set { suggestedArchetypesRaw = newValue.map(\.rawValue) }
    }

    // MARK: - Safe Accessors for Instructions/Tags

    var instructionsList: [String] {
        get { instructions ?? [] }
        set { instructions = newValue }
    }

    var tagsList: [String] {
        get { tags ?? [] }
        set { tags = newValue }
    }

    // MARK: - Typed Accessors

    var recipeIngredientsArray: [RecipeIngredient] {
        (recipeIngredients?.allObjects as? [RecipeIngredient])?.sorted { $0.order < $1.order } ?? []
    }

    var sortedIngredients: [RecipeIngredient] { recipeIngredientsArray }

    var mealSlotsArray: [MealSlot] {
        (mealSlots?.allObjects as? [MealSlot]) ?? []
    }

    // MARK: - Optional Int Accessors (0 means nil for display)

    var prepTimeMinutesOptional: Int? {
        prepTimeMinutes > 0 ? Int(prepTimeMinutes) : nil
    }

    var cookTimeMinutesOptional: Int? {
        cookTimeMinutes > 0 ? Int(cookTimeMinutes) : nil
    }

    // MARK: - Computed Properties

    var totalTimeMinutes: Int? {
        let prep = prepTimeMinutesOptional
        let cook = cookTimeMinutesOptional
        switch (prep, cook) {
        case let (p?, c?): return p + c
        case let (p?, nil): return p
        case let (nil, c?): return c
        case (nil, nil): return nil
        }
    }

    var formattedTotalTime: String? {
        guard let total = totalTimeMinutes else { return nil }
        if total < 60 {
            return "\(total) min"
        } else {
            let hours = total / 60
            let minutes = total % 60
            return minutes == 0 ? "\(hours) hr" : "\(hours) hr \(minutes) min"
        }
    }

    var formattedPrepTime: String? {
        guard let prep = prepTimeMinutesOptional else { return nil }
        return "\(prep) min prep"
    }

    var formattedCookTime: String? {
        guard let cook = cookTimeMinutesOptional else { return nil }
        return "\(cook) min cook"
    }

    // MARK: - Macro Calculations

    var totalCalories: Double? { calculateTotalMacro(\.caloriesPer100g) }
    var totalProtein: Double? { calculateTotalMacro(\.proteinPer100g) }
    var totalCarbs: Double? { calculateTotalMacro(\.carbsPer100g) }
    var totalFat: Double? { calculateTotalMacro(\.fatPer100g) }

    var macrosPerServing: MacroSummary? {
        guard servings > 0,
              let calories = totalCalories,
              let protein = totalProtein,
              let carbs = totalCarbs,
              let fat = totalFat else { return nil }
        let s = Double(servings)
        return MacroSummary(calories: calories / s, protein: protein / s, carbs: carbs / s, fat: fat / s)
    }

    func macrosForServings(_ servingCount: Int) -> MacroSummary? {
        guard let perServing = macrosPerServing else { return nil }
        let m = Double(servingCount)
        return MacroSummary(
            calories: (perServing.calories ?? 0) * m,
            protein: (perServing.protein ?? 0) * m,
            carbs: (perServing.carbs ?? 0) * m,
            fat: (perServing.fat ?? 0) * m
        )
    }

    private func calculateTotalMacro(_ keyPath: KeyPath<Ingredient, NSNumber?>) -> Double? {
        var total: Double = 0
        var hasAnyData = false
        for ri in recipeIngredientsArray {
            guard let ingredient = ri.ingredient,
                  let macroPer100g = ingredient[keyPath: keyPath]?.doubleValue else { continue }
            hasAnyData = true
            let grams = convertToGrams(quantity: ri.quantity, unit: ri.unit)
            total += (macroPer100g * grams) / 100
        }
        return hasAnyData ? total : nil
    }

    private func convertToGrams(quantity: Double, unit: MeasurementUnit) -> Double {
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

    // MARK: - Methods

    func markAsCooked() {
        timesCooked += 1
        lastCookedDate = Date()
        modifiedAt = Date()
        // Record into the suggestion-intelligence layer. The SuggestionEngine reads
        // SuggestionMemory (not Recipe.timesCooked), so without this the familiarity
        // gradient and the "Your go-tos" tray stay permanently empty.
        if let context = managedObjectContext {
            SuggestionMemory.findOrCreate(for: self, in: context).recordCooking()
        }
    }

    func toggleFavorite() {
        isFavorite.toggle()
        modifiedAt = Date()
    }

    func addIngredient(_ recipeIngredient: RecipeIngredient) {
        recipeIngredient.order = Int32(recipeIngredientsArray.count)
        recipeIngredient.recipe = self
        addToRecipeIngredients(recipeIngredient)
        modifiedAt = Date()
    }

    func removeIngredient(_ recipeIngredient: RecipeIngredient) {
        removeFromRecipeIngredients(recipeIngredient)
        for (index, ri) in recipeIngredientsArray.enumerated() {
            ri.order = Int32(index)
        }
        modifiedAt = Date()
    }

    func matchesArchetype(_ archetype: ArchetypeType) -> Bool {
        suggestedArchetypes.contains(archetype)
    }

    var isQuickMeal: Bool {
        guard let totalTime = totalTimeMinutes else { return false }
        return totalTime <= 30
    }

    // MARK: - NSSet Accessors

    @objc(addRecipeIngredientsObject:)
    @NSManaged func addToRecipeIngredients(_ value: RecipeIngredient)

    @objc(removeRecipeIngredientsObject:)
    @NSManaged func removeFromRecipeIngredients(_ value: RecipeIngredient)

    @objc(addMealSlotsObject:)
    @NSManaged func addToMealSlots(_ value: MealSlot)

    @objc(removeMealSlotsObject:)
    @NSManaged func removeFromMealSlots(_ value: MealSlot)

    // MARK: - Convenience Initializer

    @discardableResult
    convenience init(
        context: NSManagedObjectContext,
        id: UUID = UUID(),
        title: String,
        summary: String? = nil,
        sourceURL: URL? = nil,
        cookbook: String? = nil,
        imageURL: URL? = nil,
        servings: Int = 4,
        prepTimeMinutes: Int? = nil,
        cookTimeMinutes: Int? = nil,
        instructions: [String] = [],
        tags: [String] = [],
        suggestedArchetypes: [ArchetypeType] = [],
        imageData: Data? = nil,
        isFavorite: Bool = false,
        timesCooked: Int = 0,
        lastCookedDate: Date? = nil,
        createdBy: User? = nil
    ) {
        let entity = NSEntityDescription.entity(forEntityName: "Recipe", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = id
        self.title = title
        self.summary = summary
        self.sourceURL = sourceURL
        self.cookbook = cookbook
        self.imageURL = imageURL
        self.servings = Int32(servings)
        self.prepTimeMinutes = Int32(prepTimeMinutes ?? 0)
        self.cookTimeMinutes = Int32(cookTimeMinutes ?? 0)
        self.instructions = instructions
        self.tags = tags
        self.suggestedArchetypesRaw = suggestedArchetypes.map(\.rawValue)
        self.imageData = imageData
        self.isFavorite = isFavorite
        self.timesCooked = Int32(timesCooked)
        self.lastCookedDate = lastCookedDate
        self.createdAt = Date()
        self.modifiedAt = Date()
        self.createdBy = createdBy
    }
}

// MARK: - UTType Extension

extension UTType {
    static var recipe: UTType {
        UTType(exportedAs: "com.snap.app.recipe")
    }
}
