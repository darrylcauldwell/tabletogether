//
//  GroceryListGenerator.swift
//  TableTogether
//
//  Generates a grocery list from a week plan by aggregating ingredients
//  across all planned meals, combining duplicates, and grouping by category.
//

import Foundation
import Observation

// MARK: - Grocery List Generator

/// Generates grocery lists from week plans by aggregating and organizing ingredients.
///
/// The generator:
/// - Aggregates ingredients across all planned meals
/// - Combines duplicate ingredients with summed quantities
/// - Groups items by category for easy shopping
@Observable
final class GroceryListGenerator {

    // MARK: - Public Methods

    /// Generates a grocery list from a week plan.
    ///
    /// - Parameter weekPlan: The week plan to generate the grocery list from
    /// - Returns: An array of `GroceryItem` objects grouped by category
    func generateGroceryList(from weekPlan: WeekPlan) -> [GroceryItem] {
        // Collect all recipe ingredients from planned slots
        var ingredientAggregation: [UUID: IngredientAggregation] = [:]

        for slot in weekPlan.slots {
            // Skip slots without recipes or that are explicitly skipped
            guard !slot.isSkipped, !slot.recipes.isEmpty else {
                continue
            }

            for recipe in slot.recipes {
                // Calculate serving multiplier
                let servingMultiplier = Double(slot.servingsPlanned) / Double(max(recipe.servings, 1))

                // Process each recipe ingredient
                for recipeIngredient in recipe.recipeIngredients {
                    // Skip if ingredient is nil
                    guard let ingredient = recipeIngredient.ingredient else { continue }

                    let ingredientID = ingredient.id
                    let adjustedQuantity = recipeIngredient.quantity * servingMultiplier

                    if var existing = ingredientAggregation[ingredientID] {
                        // Combine with existing entry
                        existing.totalQuantity += adjustedQuantity
                        existing.sourceSlots.append(slot)
                        ingredientAggregation[ingredientID] = existing
                    } else {
                        // Create new aggregation entry
                        ingredientAggregation[ingredientID] = IngredientAggregation(
                            ingredient: ingredient,
                            totalQuantity: adjustedQuantity,
                            unit: recipeIngredient.unit,
                            sourceSlots: [slot]
                        )
                    }
                }
            }
        }

        // Convert aggregations to GroceryItems
        var groceryItems = ingredientAggregation.values.map { aggregation -> GroceryItem in
            let item = GroceryItem(
                ingredient: aggregation.ingredient,
                quantity: aggregation.totalQuantity,
                unit: aggregation.unit,
                weekPlan: weekPlan
            )
            // Add source slots for tracking which meals need this item
            item.sourceSlots = aggregation.sourceSlots
            return item
        }

        // Sort by category for organized shopping
        groceryItems.sort { item1, item2 in
            if item1.category.sortOrder != item2.category.sortOrder {
                return item1.category.sortOrder < item2.category.sortOrder
            }
            // Within same category, sort alphabetically
            let name1 = item1.displayName
            let name2 = item2.displayName
            return name1.localizedCaseInsensitiveCompare(name2) == .orderedAscending
        }

        return groceryItems
    }

    /// Groups grocery items by category.
    ///
    /// - Parameter items: The grocery items to group
    /// - Returns: A dictionary mapping categories to their items
    func groupByCategory(_ items: [GroceryItem]) -> [IngredientCategory: [GroceryItem]] {
        Dictionary(grouping: items) { $0.category }
    }

    /// Returns grocery items sorted by category with category headers.
    ///
    /// - Parameter items: The grocery items to organize
    /// - Returns: An array of tuples containing category and its items
    func organizedByCategory(_ items: [GroceryItem]) -> [(category: IngredientCategory, items: [GroceryItem])] {
        let grouped = groupByCategory(items)

        return IngredientCategory.allCases
            .compactMap { category -> (IngredientCategory, [GroceryItem])? in
                guard let categoryItems = grouped[category], !categoryItems.isEmpty else {
                    return nil
                }
                return (category, categoryItems)
            }
            .sorted { $0.0.sortOrder < $1.0.sortOrder }
    }
}

// MARK: - Private Types

/// Internal type for aggregating ingredient quantities.
private struct IngredientAggregation {
    let ingredient: Ingredient
    var totalQuantity: Double
    let unit: MeasurementUnit
    var sourceSlots: [MealSlot]
}

// Note: IngredientCategory.sortOrder and displayName are defined in Enums.swift
// Note: GroceryItem.displayName and formattedQuantity are defined in GroceryItem.swift
// Note: MeasurementUnit.displayName and abbreviation are defined in Enums.swift
