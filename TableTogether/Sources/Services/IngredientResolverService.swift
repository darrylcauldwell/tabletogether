import Foundation
import SwiftData

/// Resolves parsed ingredients against the food database and calculates macros.
///
/// Resolution pipeline for each MealParsedIngredient:
/// 1. Search local FoodItem cache (SwiftData) by normalizedName and userAliases
/// 2. If no strong match and online, query USDA API and cache the result
/// 3. Rank matches by StringSimilarity score and dataType priority
/// 4. Calculate macros via GramConversionService
/// 5. Offline fallback: MealEstimatorService food database
@MainActor
final class IngredientResolverService: ObservableObject {

    private let estimator = MealEstimatorService()

    // MARK: - Public API

    /// Resolves an array of parsed ingredients into resolved ingredients with macros.
    func resolve(
        ingredients: [MealParsedIngredient],
        context: ModelContext,
        household: Household?
    ) async -> [ResolvedIngredient] {
        var resolved: [ResolvedIngredient] = []

        for ingredient in ingredients {
            let result = await resolveOne(ingredient, context: context, household: household)
            resolved.append(result)
        }

        return resolved
    }

    // MARK: - Single Ingredient Resolution

    private func resolveOne(
        _ ingredient: MealParsedIngredient,
        context: ModelContext,
        household: Household?
    ) async -> ResolvedIngredient {
        let query = ingredient.name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // Step 1: Search local FoodItem cache
        let localMatches = searchLocalCache(query: query, context: context)

        if let bestLocal = localMatches.first, bestLocal.score >= 0.8 {
            AppLogger.nutrition.debug("Local cache hit for '\(query)' (score: \(bestLocal.score))")
            return buildResolved(
                parsed: ingredient,
                foodItem: bestLocal.foodItem,
                alternates: Array(localMatches.dropFirst().prefix(3)),
                source: .localCache
            )
        }

        // Step 2: USDA query if online
        if NetworkMonitor.shared.isConnected {
            do {
                let usdaResults = try await USDAFoodService.shared.search(query: query)

                if let bestUSDA = usdaResults.first {
                    // Create FoodItem from USDA result and cache it
                    let foodItem = createFoodItem(from: bestUSDA, context: context, household: household)

                    // Build alternate matches from remaining USDA results
                    let alternates: [FoodItemMatch] = usdaResults.dropFirst().prefix(3).map { result in
                        let altFoodItem = createFoodItem(from: result, context: context, household: household)
                        let score = StringSimilarity.combinedScore(query, altFoodItem.normalizedName)
                        return FoodItemMatch(foodItem: altFoodItem, score: score)
                    }

                    context.saveWithLogging(context: "USDA food cache")

                    AppLogger.nutrition.info("USDA lookup for '\(query)' → \(foodItem.displayName)")

                    return buildResolved(
                        parsed: ingredient,
                        foodItem: foodItem,
                        alternates: alternates,
                        source: .usdaLookup
                    )
                }
            } catch {
                AppLogger.nutrition.warning("USDA search failed for '\(query)': \(error.localizedDescription)")
            }
        }

        // Step 3: Use local cache even with lower score
        if let bestLocal = localMatches.first {
            AppLogger.nutrition.debug("Using lower-confidence local match for '\(query)' (score: \(bestLocal.score))")
            return buildResolved(
                parsed: ingredient,
                foodItem: bestLocal.foodItem,
                alternates: Array(localMatches.dropFirst().prefix(3)),
                source: .localCache
            )
        }

        // Step 4: Fallback to MealEstimatorService
        AppLogger.nutrition.debug("Falling back to MealEstimatorService for '\(query)'")
        return buildFallbackResolved(parsed: ingredient)
    }

    // MARK: - Local Cache Search

    private func searchLocalCache(query: String, context: ModelContext) -> [FoodItemMatch] {
        let descriptor = FetchDescriptor<FoodItem>()
        guard let allItems = try? context.fetch(descriptor) else { return [] }

        var matches: [FoodItemMatch] = []

        for item in allItems {
            // Score against normalized name
            let nameScore = StringSimilarity.combinedScore(query, item.normalizedName)

            // Score against user aliases
            let aliasScore = item.userAliases.map { StringSimilarity.combinedScore(query, $0) }.max() ?? 0

            // Score against USDA description
            let descScore = StringSimilarity.combinedScore(query, item.usdaDescription.lowercased()) * 0.8

            let bestScore = max(nameScore, aliasScore, descScore)

            if bestScore > 0.3 {
                matches.append(FoodItemMatch(foodItem: item, score: bestScore))
            }
        }

        // Sort by score descending, then by dataType priority
        matches.sort { a, b in
            if abs(a.score - b.score) > 0.05 {
                return a.score > b.score
            }
            return a.foodItem.dataTypePriority > b.foodItem.dataTypePriority
        }

        return matches
    }

    // MARK: - FoodItem Creation from USDA

    @discardableResult
    private func createFoodItem(
        from result: USDAFoodResult,
        context: ModelContext,
        household: Household?
    ) -> FoodItem {
        // Check if already cached by fdcId
        let fdcId = result.fdcId
        let descriptor = FetchDescriptor<FoodItem>(
            predicate: #Predicate<FoodItem> { $0.fdcId == fdcId }
        )

        if let existing = try? context.fetch(descriptor).first {
            return existing
        }

        // Build common portions from USDA measures
        let portions: [CommonPortion] = result.foodMeasures?.compactMap { $0.asCommonPortion } ?? []

        let foodItem = FoodItem(
            fdcId: result.fdcId,
            usdaDescription: result.description,
            displayName: result.cleanDisplayName,
            dataType: result.dataType ?? "Branded",
            brandOwner: result.brandOwner,
            caloriesPer100g: result.caloriesPer100g,
            proteinPer100g: result.proteinPer100g,
            carbsPer100g: result.carbsPer100g,
            fatPer100g: result.fatPer100g,
            fiberPer100g: result.fiberPer100g,
            sugarPer100g: result.sugarPer100g,
            sodiumMgPer100g: result.sodiumMgPer100g,
            commonPortions: portions
        )
        foodItem.household = household
        context.insert(foodItem)

        return foodItem
    }

    // MARK: - Build ResolvedIngredient

    private func buildResolved(
        parsed: MealParsedIngredient,
        foodItem: FoodItem,
        alternates: [FoodItemMatch],
        source: ResolutionSource
    ) -> ResolvedIngredient {
        let grams = GramConversionService.convertToGrams(
            quantity: parsed.quantity,
            unit: parsed.unit,
            foodName: foodItem.normalizedName,
            foodItem: foodItem
        )

        let macros: MacroSummary
        if let g = grams {
            macros = foodItem.macros(forGrams: g)
        } else {
            // Try common portion, then default to 100g
            if let portion = foodItem.commonPortions.first {
                let qty = parsed.quantity ?? 1.0
                macros = foodItem.macros(forGrams: qty * portion.gramWeight)
            } else {
                macros = foodItem.macros(forGrams: 100)
            }
        }

        return ResolvedIngredient(
            parsed: parsed,
            foodItem: foodItem,
            quantityInGrams: grams,
            macros: macros,
            alternates: alternates,
            source: source
        )
    }

    // MARK: - Fallback Resolution

    private func buildFallbackResolved(parsed: MealParsedIngredient) -> ResolvedIngredient {
        // Try MealEstimatorService for a macro estimate
        if let estimate = estimator.estimate(description: parsed.name),
           let component = estimate.components.first {
            return ResolvedIngredient(
                parsed: parsed,
                foodItem: nil,
                quantityInGrams: nil,
                macros: component.macros,
                alternates: [],
                source: .fallback
            )
        }

        // Absolute fallback — unknown food, no macros
        return ResolvedIngredient(
            parsed: parsed,
            foodItem: nil,
            quantityInGrams: nil,
            macros: MacroSummary.empty,
            alternates: [],
            source: .fallback
        )
    }
}
