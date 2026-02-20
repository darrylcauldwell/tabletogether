//
//  SuggestionEngine.swift
//  TableTogether
//
//  The Level 2 Intelligence System for recipe suggestions.
//  Suggests recipes based on archetype match, familiarity, recency, and user preferences.
//

import Foundation
import Observation

// MARK: - Suggestion Result

/// The result of a suggestion query, containing both familiar and new recipe suggestions.
struct SuggestionResult {
    /// Recipes the household has cooked before - "Your go-tos"
    let familiarSuggestions: [Recipe]
    /// New recipes to try - "Try something new"
    let newSuggestions: [Recipe]
}

// MARK: - Suggestion Engine

/// Level 2 Intelligence system that suggests recipes based on household patterns.
///
/// The engine prioritizes familiar recipes (80%) while surfacing occasional new options (20%).
/// It considers archetype match, familiarity level, recency, decline history, and favorites.
@Observable
final class SuggestionEngine {

    // MARK: - Scoring Constants

    private enum ScoringConstants {
        static let archetypeMatchBonus: Double = 30
        static let stapleFamiliarityBonus: Double = 25
        static let familiarFamiliarityBonus: Double = 20
        static let triedFamiliarityBonus: Double = 10
        static let favoriteBonus: Double = 15
        static let recentlyUsedPenalty7Days: Double = -20
        static let recentlyUsedPenalty14Days: Double = -10
        static let declinePenaltyMultiplier: Double = 5
        static let declineThreshold: Int = 2

        static let familiarSuggestionsCount = 6
        static let newSuggestionsCount = 2
    }

    // MARK: - Public Methods

    /// Suggests recipes for a given meal slot based on household patterns and preferences.
    ///
    /// - Parameters:
    ///   - slot: The meal slot to suggest recipes for
    ///   - weekPlan: The current week's plan (to avoid already-planned recipes)
    ///   - allRecipes: The complete recipe library
    ///   - memory: Suggestion memory containing familiarity and history data
    /// - Returns: A `SuggestionResult` with familiar and new recipe suggestions
    func suggestRecipes(
        for slot: MealSlot,
        in weekPlan: WeekPlan,
        allRecipes: [Recipe],
        memory: [SuggestionMemory]
    ) -> SuggestionResult {

        // Get IDs of recipes already planned this week
        let plannedRecipeIDs = Set(weekPlan.slots.flatMap { $0.recipes.map(\.id) })

        // Filter out already-planned recipes
        let candidates = allRecipes.filter { recipe in
            !plannedRecipeIDs.contains(recipe.id)
        }

        // Score each candidate recipe
        let scored = candidates.map { recipe -> (recipe: Recipe, score: Double) in
            let score = calculateScore(
                for: recipe,
                slot: slot,
                memory: memory
            )
            return (recipe, score)
        }

        // Sort by score descending
        let sorted = scored.sorted { $0.score > $1.score }

        // Separate familiar from new recipes
        let familiarRecipes = sorted
            .filter { scoredRecipe in
                let familiarity = findMemory(for: scoredRecipe.recipe, in: memory)?.householdFamiliarity
                return familiarity != nil && familiarity != .new
            }
            .prefix(ScoringConstants.familiarSuggestionsCount)
            .map { $0.recipe }

        let newRecipes = sorted
            .filter { scoredRecipe in
                let familiarity = findMemory(for: scoredRecipe.recipe, in: memory)?.householdFamiliarity
                return familiarity == nil || familiarity == .new
            }
            .prefix(ScoringConstants.newSuggestionsCount)
            .map { $0.recipe }

        return SuggestionResult(
            familiarSuggestions: Array(familiarRecipes),
            newSuggestions: Array(newRecipes)
        )
    }

    /// Suggests recipes without a specific slot context (for general suggestions).
    /// Returns familiar and new recipes based on the recipe library and memory.
    func suggestRecipes(
        allRecipes: [Recipe],
        weekPlan: WeekPlan?,
        memory: [SuggestionMemory]
    ) -> SuggestionResult {
        // Get IDs of recipes already planned this week
        let plannedRecipeIDs = Set(weekPlan?.slots.flatMap { $0.recipes.map(\.id) } ?? [])

        // Filter out already-planned recipes
        let candidates = allRecipes.filter { recipe in
            !plannedRecipeIDs.contains(recipe.id)
        }

        // Score each candidate recipe (without slot context)
        let scored = candidates.map { recipe -> (recipe: Recipe, score: Double) in
            let score = calculateGeneralScore(for: recipe, memory: memory)
            return (recipe, score)
        }

        // Sort by score descending
        let sorted = scored.sorted { $0.score > $1.score }

        // Separate familiar from new recipes
        let familiarRecipes = sorted
            .filter { scoredRecipe in
                let familiarity = findMemory(for: scoredRecipe.recipe, in: memory)?.householdFamiliarity
                return familiarity != nil && familiarity != .new
            }
            .prefix(ScoringConstants.familiarSuggestionsCount)
            .map { $0.recipe }

        let newRecipes = sorted
            .filter { scoredRecipe in
                let familiarity = findMemory(for: scoredRecipe.recipe, in: memory)?.householdFamiliarity
                return familiarity == nil || familiarity == .new
            }
            .prefix(ScoringConstants.newSuggestionsCount)
            .map { $0.recipe }

        return SuggestionResult(
            familiarSuggestions: Array(familiarRecipes),
            newSuggestions: Array(newRecipes)
        )
    }

    // MARK: - Private Methods

    /// Calculates a general score without slot context
    private func calculateGeneralScore(
        for recipe: Recipe,
        memory: [SuggestionMemory]
    ) -> Double {
        var score: Double = 0
        let recipeMemory = findMemory(for: recipe, in: memory)

        // Familiarity bonus (prefer familiar recipes - 80/20 rule)
        switch recipeMemory?.householdFamiliarity {
        case .staple:
            score += ScoringConstants.stapleFamiliarityBonus
        case .familiar:
            score += ScoringConstants.familiarFamiliarityBonus
        case .tried:
            score += ScoringConstants.triedFamiliarityBonus
        case .new, .none:
            break
        }

        // Favorite bonus
        if recipe.isFavorite {
            score += ScoringConstants.favoriteBonus
        }

        // Recency penalty
        if let lastCooked = recipe.lastCookedDate {
            let daysSince = Calendar.current.dateComponents([.day], from: lastCooked, to: Date()).day ?? 0
            if daysSince < 7 {
                score += ScoringConstants.recentlyUsedPenalty7Days
            } else if daysSince < 14 {
                score += ScoringConstants.recentlyUsedPenalty14Days
            }
        }

        // Decline penalty
        if let suggestionDeclined = recipeMemory?.suggestionDeclined, suggestionDeclined >= ScoringConstants.declineThreshold {
            score -= Double(suggestionDeclined) * ScoringConstants.declinePenaltyMultiplier
        }

        return score
    }

    /// Calculates the suggestion score for a recipe.
    private func calculateScore(
        for recipe: Recipe,
        slot: MealSlot,
        memory: [SuggestionMemory]
    ) -> Double {
        var score: Double = 0
        let recipeMemory = findMemory(for: recipe, in: memory)

        // Archetype match bonus
        if let archetype = slot.archetype?.systemType,
           recipe.suggestedArchetypes.contains(archetype) {
            score += ScoringConstants.archetypeMatchBonus
        }

        // Familiarity bonus (prefer familiar recipes - 80/20 rule)
        switch recipeMemory?.householdFamiliarity {
        case .staple:
            score += ScoringConstants.stapleFamiliarityBonus
        case .familiar:
            score += ScoringConstants.familiarFamiliarityBonus
        case .tried:
            score += ScoringConstants.triedFamiliarityBonus
        case .new, .none:
            // Neutral - not penalized, just no bonus
            break
        }

        // Recency penalty (avoid repeats)
        if let lastCooked = recipeMemory?.lastCookedDate {
            let daysSince = Calendar.current.dateComponents(
                [.day],
                from: lastCooked,
                to: Date()
            ).day ?? 0

            if daysSince < 7 {
                score += ScoringConstants.recentlyUsedPenalty7Days
            } else if daysSince < 14 {
                score += ScoringConstants.recentlyUsedPenalty14Days
            }
        }

        // Decline penalty (respect user's "not now" choices)
        if let declines = recipeMemory?.suggestionDeclined,
           declines > ScoringConstants.declineThreshold {
            score -= Double(declines) * ScoringConstants.declinePenaltyMultiplier
        }

        // Favorite bonus
        if recipe.isFavorite {
            score += ScoringConstants.favoriteBonus
        }

        return score
    }

    /// Finds the suggestion memory for a given recipe.
    private func findMemory(
        for recipe: Recipe,
        in memory: [SuggestionMemory]
    ) -> SuggestionMemory? {
        memory.first { $0.recipe?.id == recipe.id }
    }
}
