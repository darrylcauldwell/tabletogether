import Foundation
import SwiftData

/// The shared root entity for a household.
/// All collaborative data (recipes, meal plans, groceries, etc.) belongs to a Household.
/// When shared via CloudKit, all related records sync to all participants.
///
/// There are no roles or hierarchy — all household members are equal.
@Model
final class Household {
    /// Primary identifier
    @Attribute(.unique) var id: UUID

    /// Display name for the household
    var name: String

    /// Creation timestamp
    var createdAt: Date

    // MARK: - Inverse Relationships

    @Relationship(inverse: \Recipe.household)
    var recipes: [Recipe] = []

    @Relationship(inverse: \Ingredient.household)
    var ingredients: [Ingredient] = []

    @Relationship(inverse: \WeekPlan.household)
    var weekPlans: [WeekPlan] = []

    @Relationship(inverse: \User.household)
    var users: [User] = []

    @Relationship(inverse: \MealArchetype.household)
    var archetypes: [MealArchetype] = []

    @Relationship(inverse: \SuggestionMemory.household)
    var memories: [SuggestionMemory] = []

    @Relationship(inverse: \FoodItem.household)
    var foodItems: [FoodItem] = []

    // MARK: - Initialization

    init(name: String = "My Household") {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
    }
}
