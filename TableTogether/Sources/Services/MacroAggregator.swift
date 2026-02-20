//
//  MacroAggregator.swift
//  TableTogether
//
//  Aggregates macro nutritional data from meal logs and generates insights.
//  Uses positive, calm language following the app's tone guidelines.
//

import Foundation
import Observation

// MARK: - Aggregated Macro Result

/// Result of macro aggregation for a period, including meal count.
struct AggregatedMacroResult: Equatable, Sendable {
    let macros: MacroSummary
    let mealsLogged: Int

    /// Returns true if no macros were logged.
    var isEmpty: Bool {
        macros.isEmpty && mealsLogged == 0
    }

    /// Creates an empty result with zero values.
    static var empty: AggregatedMacroResult {
        AggregatedMacroResult(macros: .zero, mealsLogged: 0)
    }
}

// MARK: - Recipe Macro Lookup

/// Protocol for looking up recipe macro data by ID.
/// Used to calculate macros for meal logs that reference recipes.
protocol RecipeMacroLookup {
    func macrosPerServing(for recipeID: UUID) -> MacroSummary?
    func recipeName(for recipeID: UUID) -> String?
}

extension RecipeMacroLookup {
    func recipeName(for recipeID: UUID) -> String? { nil }
}

// MARK: - Macro Aggregator

/// Aggregates macro nutritional data from meal logs and generates user-friendly insights.
///
/// The aggregator follows the app's tone guidelines:
/// - Positive language always
/// - No judgmental terms like "deficit", "excess", "inconsistent"
/// - Progressive disclosure (summary first, detail on demand)
@Observable
final class MacroAggregator {

    // MARK: - Public Methods

    /// Aggregates macros for a single day from private meal logs.
    ///
    /// - Parameters:
    ///   - date: The date to aggregate
    ///   - logs: Private meal logs (already filtered to current user)
    ///   - recipeLookup: Lookup for recipe macro data
    /// - Returns: An `AggregatedMacroResult` for the specified day
    func aggregateDailyMacros(
        on date: Date,
        logs: [PrivateMealLog],
        recipeLookup: RecipeMacroLookup? = nil
    ) -> AggregatedMacroResult {
        let calendar = Calendar.current

        // Filter logs for the specific date
        let dayLogs = logs.filter { log in
            calendar.isDate(log.date, inSameDayAs: date)
        }

        return aggregateLogs(dayLogs, recipeLookup: recipeLookup)
    }

    /// Aggregates macros for an entire week, returning a dictionary keyed by date.
    ///
    /// - Parameters:
    ///   - weekStart: The start date of the week (typically Monday)
    ///   - logs: Private meal logs (already filtered to current user)
    ///   - recipeLookup: Lookup for recipe macro data
    /// - Returns: A dictionary mapping each day to its `AggregatedMacroResult`
    func aggregateWeeklyMacros(
        weekStart: Date,
        logs: [PrivateMealLog],
        recipeLookup: RecipeMacroLookup? = nil
    ) -> [Date: AggregatedMacroResult] {
        let calendar = Calendar.current
        var result: [Date: AggregatedMacroResult] = [:]

        // Iterate through 7 days starting from weekStart
        for dayOffset in 0..<7 {
            guard let date = calendar.date(byAdding: .day, value: dayOffset, to: weekStart) else {
                continue
            }

            let normalizedDate = calendar.startOfDay(for: date)
            let summary = aggregateDailyMacros(on: date, logs: logs, recipeLookup: recipeLookup)
            result[normalizedDate] = summary
        }

        return result
    }

    /// Generates positive, calm insight text from weekly macro data.
    ///
    /// The generated text follows the app's tone guidelines:
    /// - Never says "deficit", "excess", "failed", "inconsistent"
    /// - Uses phrases like "light day", "hearty day", "steady patterns", "varied week"
    ///
    /// - Parameter weeklyData: The weekly macro data to analyze
    /// - Returns: A user-friendly insight string
    func generateInsightText(from weeklyData: [Date: AggregatedMacroResult]) -> String {
        guard !weeklyData.isEmpty else {
            return "Start logging meals to see your eating patterns here."
        }

        let summaries = Array(weeklyData.values)
        let daysWithData = summaries.filter { $0.mealsLogged > 0 }

        guard !daysWithData.isEmpty else {
            return "Start logging meals to see your eating patterns here."
        }

        var insights: [String] = []

        // Calculate averages
        let totalCalories = daysWithData.compactMap { $0.macros.calories }.reduce(0, +)
        let totalProtein = daysWithData.compactMap { $0.macros.protein }.reduce(0, +)
        let avgCalories = totalCalories / Double(daysWithData.count)
        let avgProtein = totalProtein / Double(daysWithData.count)
        let totalMealsLogged = summaries.reduce(0) { $0 + $1.mealsLogged }

        // Consistency insight
        let calorieValues = daysWithData.compactMap { $0.macros.calories }
        if isConsistent(values: calorieValues) {
            insights.append("Steady eating patterns this week")
        } else {
            insights.append("Varied eating this week")
        }

        // Protein insight
        if avgProtein > 0 && avgCalories > 0 {
            let proteinPercentage = calculateProteinPercentage(protein: avgProtein, calories: avgCalories)
            if proteinPercentage >= 25 {
                insights.append("Protein-rich choices")
            } else if proteinPercentage >= 15 {
                insights.append("Balanced protein intake")
            }
        }

        // Logging frequency insight (positive framing)
        if totalMealsLogged >= 14 {
            insights.append("Great logging consistency")
        } else if totalMealsLogged >= 7 {
            insights.append("\(totalMealsLogged) meals logged this week")
        } else if totalMealsLogged > 0 {
            insights.append("Some meals not logged")
        }

        // Combine insights with calm, positive tone
        if insights.isEmpty {
            return "This week's eating patterns are taking shape."
        }

        return insights.joined(separator: ". ") + "."
    }

    // MARK: - Private Methods

    /// Aggregates a collection of private meal logs into a single result.
    private func aggregateLogs(
        _ logs: [PrivateMealLog],
        recipeLookup: RecipeMacroLookup?
    ) -> AggregatedMacroResult {
        var totalMacros = MacroSummary.zero

        for log in logs {
            let macros = calculateMacros(for: log, recipeLookup: recipeLookup)
            totalMacros = totalMacros + macros
        }

        return AggregatedMacroResult(
            macros: totalMacros,
            mealsLogged: logs.count
        )
    }

    /// Calculates macros for a single meal log.
    private func calculateMacros(
        for log: PrivateMealLog,
        recipeLookup: RecipeMacroLookup?
    ) -> MacroSummary {
        // Check for quick log values first
        if log.isQuickLog {
            return MacroSummary(
                calories: log.quickLogCalories.map { Double($0) },
                protein: log.quickLogProtein.map { Double($0) },
                carbs: log.quickLogCarbs.map { Double($0) },
                fat: log.quickLogFat.map { Double($0) }
            )
        }

        // Look up recipe macros if available
        if let recipeID = log.recipeID,
           let recipeMacros = recipeLookup?.macrosPerServing(for: recipeID) {
            // Scale by servings consumed
            return MacroSummary(
                calories: recipeMacros.calories.map { $0 * log.servingsConsumed },
                protein: recipeMacros.protein.map { $0 * log.servingsConsumed },
                carbs: recipeMacros.carbs.map { $0 * log.servingsConsumed },
                fat: recipeMacros.fat.map { $0 * log.servingsConsumed }
            )
        }

        return .zero
    }

    /// Determines if a set of values is consistent (low variance).
    private func isConsistent(values: [Double]) -> Bool {
        guard values.count >= 2 else { return true }

        let nonZeroValues = values.filter { $0 > 0 }
        guard nonZeroValues.count >= 2 else { return true }

        let average = nonZeroValues.reduce(0, +) / Double(nonZeroValues.count)
        guard average > 0 else { return true }

        // Calculate coefficient of variation
        let squaredDifferences = nonZeroValues.map { pow($0 - average, 2) }
        let variance = squaredDifferences.reduce(0, +) / Double(nonZeroValues.count)
        let standardDeviation = sqrt(variance)
        let coefficientOfVariation = standardDeviation / average

        // Consider "consistent" if CV is less than 25%
        return coefficientOfVariation < 0.25
    }

    /// Calculates the protein percentage of total calories.
    private func calculateProteinPercentage(protein: Double, calories: Double) -> Double {
        guard calories > 0 else { return 0 }

        // Protein has 4 calories per gram
        let proteinCalories = protein * 4
        return (proteinCalories / calories) * 100
    }
}
