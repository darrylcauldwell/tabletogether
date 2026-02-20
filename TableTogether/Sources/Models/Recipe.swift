import Foundation
import SwiftData
import UniformTypeIdentifiers
#if canImport(CoreTransferable)
import CoreTransferable
#endif

// MARK: - Recipe Model

/// A complete recipe with ingredients, instructions, and metadata.
/// Recipes belong to the shared household library.
@Model
final class Recipe {
    /// Primary identifier
    @Attribute(.unique) var id: UUID

    /// Recipe name
    var title: String

    /// Brief description of the recipe
    var summary: String?

    /// Original import source URL
    var sourceURL: URL?

    /// Default serving count
    var servings: Int

    /// Preparation time in minutes
    var prepTimeMinutes: Int?

    /// Cooking time in minutes
    var cookTimeMinutes: Int?

    /// Ordered list of instruction steps
    var instructions: [String]

    /// User-defined tags for organization
    var tags: [String]

    /// Which archetype types this recipe fits
    var suggestedArchetypes: [ArchetypeType]

    /// Optional recipe photo (stored externally for large images)
    @Attribute(.externalStorage)
    var imageData: Data?

    /// Whether this recipe is starred by the household
    var isFavorite: Bool

    /// Number of times this recipe has been cooked
    var timesCooked: Int

    /// Date when recipe was last cooked
    var lastCookedDate: Date?

    /// Creation timestamp
    var createdAt: Date

    /// Last modification timestamp
    var modifiedAt: Date

    // MARK: - Relationships

    /// Ingredients used in this recipe with quantities
    @Relationship(deleteRule: .cascade)
    var recipeIngredients: [RecipeIngredient] = []

    /// Meal slots where this recipe is assigned
    @Relationship(inverse: \MealSlot.recipes)
    var mealSlots: [MealSlot] = []

    // Note: Meal logs are stored in CloudKit private database (PrivateMealLog)
    // and reference this recipe by ID only - no SwiftData relationship needed.

    /// User who added this recipe to the library
    @Relationship
    var createdBy: User?

    /// Suggestion memory for this recipe
    @Relationship(inverse: \SuggestionMemory.recipe)
    var suggestionMemory: SuggestionMemory?

    /// Parent household for CloudKit sharing
    @Relationship
    var household: Household?

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        title: String,
        summary: String? = nil,
        sourceURL: URL? = nil,
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
        self.id = id
        self.title = title
        self.summary = summary
        self.sourceURL = sourceURL
        self.servings = servings
        self.prepTimeMinutes = prepTimeMinutes
        self.cookTimeMinutes = cookTimeMinutes
        self.instructions = instructions
        self.tags = tags
        self.suggestedArchetypes = suggestedArchetypes
        self.imageData = imageData
        self.isFavorite = isFavorite
        self.timesCooked = timesCooked
        self.lastCookedDate = lastCookedDate
        self.createdAt = Date()
        self.modifiedAt = Date()
        self.createdBy = createdBy
    }

    // MARK: - Computed Properties

    /// Combined prep and cook time in minutes
    var totalTimeMinutes: Int? {
        switch (prepTimeMinutes, cookTimeMinutes) {
        case let (prep?, cook?):
            return prep + cook
        case let (prep?, nil):
            return prep
        case let (nil, cook?):
            return cook
        case (nil, nil):
            return nil
        }
    }

    /// Formatted total time string for display
    var formattedTotalTime: String? {
        guard let total = totalTimeMinutes else { return nil }
        if total < 60 {
            return "\(total) min"
        } else {
            let hours = total / 60
            let minutes = total % 60
            if minutes == 0 {
                return "\(hours) hr"
            } else {
                return "\(hours) hr \(minutes) min"
            }
        }
    }

    /// Formatted prep time string
    var formattedPrepTime: String? {
        guard let prep = prepTimeMinutes else { return nil }
        return "\(prep) min prep"
    }

    /// Formatted cook time string
    var formattedCookTime: String? {
        guard let cook = cookTimeMinutes else { return nil }
        return "\(cook) min cook"
    }

    /// Sorted recipe ingredients by display order
    var sortedIngredients: [RecipeIngredient] {
        recipeIngredients.sorted { $0.order < $1.order }
    }

    // MARK: - Macro Calculations

    /// Total calories for the entire recipe (all servings)
    var totalCalories: Double? {
        calculateTotalMacro(\.caloriesPer100g)
    }

    /// Total protein for the entire recipe in grams
    var totalProtein: Double? {
        calculateTotalMacro(\.proteinPer100g)
    }

    /// Total carbohydrates for the entire recipe in grams
    var totalCarbs: Double? {
        calculateTotalMacro(\.carbsPer100g)
    }

    /// Total fat for the entire recipe in grams
    var totalFat: Double? {
        calculateTotalMacro(\.fatPer100g)
    }

    /// Macro summary per serving
    var macrosPerServing: MacroSummary? {
        guard servings > 0,
              let calories = totalCalories,
              let protein = totalProtein,
              let carbs = totalCarbs,
              let fat = totalFat else {
            return nil
        }

        return MacroSummary(
            calories: calories / Double(servings),
            protein: protein / Double(servings),
            carbs: carbs / Double(servings),
            fat: fat / Double(servings)
        )
    }

    /// Get macros for a specific serving count
    func macrosForServings(_ servingCount: Int) -> MacroSummary? {
        guard let perServing = macrosPerServing else { return nil }
        let multiplier = Double(servingCount)
        return MacroSummary(
            calories: (perServing.calories ?? 0) * multiplier,
            protein: (perServing.protein ?? 0) * multiplier,
            carbs: (perServing.carbs ?? 0) * multiplier,
            fat: (perServing.fat ?? 0) * multiplier
        )
    }

    private func calculateTotalMacro(_ keyPath: KeyPath<Ingredient, Double?>) -> Double? {
        var total: Double = 0
        var hasAnyData = false

        for recipeIngredient in recipeIngredients {
            guard let ingredient = recipeIngredient.ingredient,
                  let macroPer100g = ingredient[keyPath: keyPath] else {
                continue
            }

            hasAnyData = true
            let quantityInGrams = convertToGrams(
                quantity: recipeIngredient.quantity,
                unit: recipeIngredient.unit
            )
            total += (macroPer100g * quantityInGrams) / 100
        }

        return hasAnyData ? total : nil
    }

    private func convertToGrams(quantity: Double, unit: MeasurementUnit) -> Double {
        switch unit {
        case .gram:
            return quantity
        case .kilogram:
            return quantity * 1000
        case .milliliter:
            return quantity // Approximation: 1ml = 1g for water-based items
        case .liter:
            return quantity * 1000
        case .cup:
            return quantity * 240 // Approximation
        case .tablespoon:
            return quantity * 15
        case .teaspoon:
            return quantity * 5
        case .piece, .slice, .clove, .bunch, .pinch, .toTaste:
            return quantity * 50 // Rough approximation
        }
    }

    // MARK: - Methods

    /// Records that this recipe was cooked
    func markAsCooked() {
        timesCooked += 1
        lastCookedDate = Date()
        modifiedAt = Date()
    }

    /// Toggles the favorite status
    func toggleFavorite() {
        isFavorite.toggle()
        modifiedAt = Date()
    }

    /// Adds an ingredient to the recipe
    func addIngredient(_ recipeIngredient: RecipeIngredient) {
        recipeIngredient.order = recipeIngredients.count
        recipeIngredient.recipe = self
        recipeIngredients.append(recipeIngredient)
        modifiedAt = Date()
    }

    /// Removes an ingredient from the recipe
    func removeIngredient(_ recipeIngredient: RecipeIngredient) {
        recipeIngredients.removeAll { $0.id == recipeIngredient.id }
        // Reorder remaining ingredients
        for (index, ingredient) in recipeIngredients.sorted(by: { $0.order < $1.order }).enumerated() {
            ingredient.order = index
        }
        modifiedAt = Date()
    }

    /// Checks if recipe matches a given archetype
    func matchesArchetype(_ archetype: ArchetypeType) -> Bool {
        suggestedArchetypes.contains(archetype)
    }

    /// Checks if recipe fits "quick weeknight" criteria (30 min or less)
    var isQuickMeal: Bool {
        guard let totalTime = totalTimeMinutes else { return false }
        return totalTime <= 30
    }
}

// MARK: - Recipe Drag & Drop Support
// Note: SwiftData @Model types can't conform to Codable for CodableRepresentation.
// For drag and drop, use the recipe's UUID string instead.

extension UTType {
    static var recipe: UTType {
        UTType(exportedAs: "com.snap.app.recipe")
    }
}
