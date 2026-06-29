//
//  GroceryListGenerator.swift
//  TableTogether
//
//  Generates a grocery list from a week plan by aggregating ingredients
//  across all planned meals, combining duplicates, and grouping by category.
//

import Foundation
import CoreData
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
    func generateGroceryList(from weekPlan: WeekPlan, context: NSManagedObjectContext) -> [GroceryItem] {
        // Collect all recipe ingredients from planned slots.
        // Keyed by (ingredient, unit): the same ingredient measured in different units
        // (e.g. grams in one recipe, tablespoons in another) must stay as separate line
        // items, since there is no unit-conversion table to combine them honestly.
        var ingredientAggregation: [AggregationKey: IngredientAggregation] = [:]

        for slot in weekPlan.slotsArray {
            // Skip slots without recipes or that are explicitly skipped
            guard !slot.isSkipped, !slot.recipesArray.isEmpty else {
                continue
            }

            for recipe in slot.recipesArray {
                // Calculate serving multiplier
                let servingMultiplier = Double(slot.servingsPlanned) / Double(max(recipe.servings, 1))

                // Process each recipe ingredient
                for recipeIngredient in recipe.recipeIngredientsArray {
                    // Prefer the linked Ingredient master; fall back to the free-text
                    // customName so unlinked rows aren't silently dropped from the list.
                    let ingredient = recipeIngredient.ingredient
                    guard let identity = Self.identity(ingredient: ingredient, name: recipeIngredient.customName) else {
                        continue
                    }

                    let key = AggregationKey(identity: identity, unit: recipeIngredient.unit)
                    let adjustedQuantity = recipeIngredient.quantity * servingMultiplier

                    if var existing = ingredientAggregation[key] {
                        // Combine with existing entry (same ingredient AND same unit)
                        existing.totalQuantity += adjustedQuantity
                        existing.sourceSlots.append(slot)
                        ingredientAggregation[key] = existing
                    } else {
                        // Create new aggregation entry
                        ingredientAggregation[key] = IngredientAggregation(
                            ingredient: ingredient,
                            fallbackName: ingredient == nil
                                ? recipeIngredient.customName?.trimmingCharacters(in: .whitespacesAndNewlines)
                                : nil,
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
            guard let ingredient = aggregation.ingredient else {
                // Unlinked ingredient — recipe-derived item from its free-text name.
                let item = GroceryItem(
                    context: context,
                    customName: aggregation.fallbackName ?? "Unknown Item",
                    quantity: aggregation.totalQuantity,
                    unit: aggregation.unit,
                    category: .other,
                    weekPlan: weekPlan
                )
                item.isManuallyAdded = false
                item.pantryChecked = false
                item.sourceSlots = NSSet(array: aggregation.sourceSlots)
                return item
            }
            let item = GroceryItem(
                context: context,
                ingredient: ingredient,
                quantity: aggregation.totalQuantity,
                unit: aggregation.unit,
                weekPlan: weekPlan
            )
            // Add source slots for tracking which meals need this item
            item.sourceSlots = NSSet(array: aggregation.sourceSlots)
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

    /// Aggregation identity for a recipe ingredient: the linked master's id when
    /// present, otherwise its normalised free-text name. Returns nil when there is
    /// neither — nothing to put on the list.
    fileprivate static func identity(ingredient: Ingredient?, name: String?) -> String? {
        if let ingredient { return ingredient.id.uuidString }
        let trimmed = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : "name:" + trimmed.lowercased()
    }
}

// MARK: - Private Types

/// Composite key for grocery aggregation: quantities only combine when both the
/// ingredient identity and its unit match, so mismatched units aren't silently
/// summed. Identity is the linked master's id, or the free-text name when unlinked.
private struct AggregationKey: Hashable {
    let identity: String
    let unit: MeasurementUnit
}

/// Internal type for aggregating ingredient quantities. `ingredient` is nil for
/// unlinked rows, in which case `fallbackName` carries the free-text name.
private struct IngredientAggregation {
    let ingredient: Ingredient?
    let fallbackName: String?
    var totalQuantity: Double
    let unit: MeasurementUnit
    var sourceSlots: [MealSlot]
}

// Note: IngredientCategory.sortOrder and displayName are defined in Enums.swift
// Note: GroceryItem.displayName and formattedQuantity are defined in GroceryItem.swift
// Note: MeasurementUnit.displayName and abbreviation are defined in Enums.swift
