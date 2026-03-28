import CoreData

// All Core Data entities have a UUID `id` property.
// Conform them to Identifiable so SwiftUI ForEach works.

extension Household: Identifiable {}
extension User: Identifiable {}
extension Recipe: Identifiable {}
extension RecipeIngredient: Identifiable {}
extension Ingredient: Identifiable {}
extension FoodItem: Identifiable {}
extension MealSlot: Identifiable {}
extension WeekPlan: Identifiable {}
extension MealArchetype: Identifiable {}
extension GroceryItem: Identifiable {}
extension SuggestionMemory: Identifiable {}
