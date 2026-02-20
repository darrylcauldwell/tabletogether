import SwiftUI
import Charts

/// Summary card showing weekly eating patterns with calm, positive language
/// Features a sparkline chart for 7-day calorie trend and macro distribution ring
struct WeeklyTrendCard: View {
    let mealLogs: [PrivateMealLog]
    let recipeLookup: RecipeMacroLookup
    let onTap: () -> Void

    private func caloriesFor(_ log: PrivateMealLog) -> Int? {
        if let cal = log.quickLogCalories { return cal }
        if let recipeID = log.recipeID,
           let macros = recipeLookup.macrosPerServing(for: recipeID),
           let cal = macros.calories {
            return Int(cal * log.servingsConsumed)
        }
        return nil
    }

    private func proteinFor(_ log: PrivateMealLog) -> Int? {
        if let prot = log.quickLogProtein { return prot }
        if let recipeID = log.recipeID,
           let macros = recipeLookup.macrosPerServing(for: recipeID),
           let prot = macros.protein {
            return Int(prot * log.servingsConsumed)
        }
        return nil
    }

    private func carbsFor(_ log: PrivateMealLog) -> Int? {
        if let carbs = log.quickLogCarbs { return carbs }
        if let recipeID = log.recipeID,
           let macros = recipeLookup.macrosPerServing(for: recipeID),
           let carbs = macros.carbs {
            return Int(carbs * log.servingsConsumed)
        }
        return nil
    }

    private func fatFor(_ log: PrivateMealLog) -> Int? {
        if let fat = log.quickLogFat { return fat }
        if let recipeID = log.recipeID,
           let macros = recipeLookup.macrosPerServing(for: recipeID),
           let fat = macros.fat {
            return Int(fat * log.servingsConsumed)
        }
        return nil
    }

    private var dailyCalories: [DailyCalorieData] {
        let calendar = Calendar.current
        let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())) ?? Date()

        var dailyData: [Date: Int] = [:]

        // Initialize all days of the week
        for dayOffset in 0..<7 {
            if let date = calendar.date(byAdding: .day, value: dayOffset, to: startOfWeek) {
                dailyData[calendar.startOfDay(for: date)] = 0
            }
        }

        // Sum calories by day
        for log in mealLogs {
            let day = calendar.startOfDay(for: log.date)
            if let calories = caloriesFor(log) {
                dailyData[day, default: 0] += calories
            }
        }

        return dailyData.map { DailyCalorieData(date: $0.key, calories: $0.value) }
            .sorted { $0.date < $1.date }
    }

    private var averageCalories: Int {
        let daysWithData = dailyCalories.filter { $0.calories > 0 }
        guard !daysWithData.isEmpty else { return 0 }
        return daysWithData.map(\.calories).reduce(0, +) / daysWithData.count
    }

    private var macroDistribution: MacroDistribution {
        var totalProtein = 0
        var totalCarbs = 0
        var totalFat = 0

        for log in mealLogs {
            totalProtein += proteinFor(log) ?? 0
            totalCarbs += carbsFor(log) ?? 0
            totalFat += fatFor(log) ?? 0
        }

        let total = totalProtein + totalCarbs + totalFat
        guard total > 0 else {
            return MacroDistribution(proteinPercent: 0, carbsPercent: 0, fatPercent: 0)
        }

        return MacroDistribution(
            proteinPercent: Double(totalProtein) / Double(total) * 100,
            carbsPercent: Double(totalCarbs) / Double(total) * 100,
            fatPercent: Double(totalFat) / Double(total) * 100
        )
    }

    private var positiveObservation: String {
        WeeklyObservationGenerator.generatePositiveObservation(
            dailyCalories: dailyCalories,
            macroDistribution: macroDistribution,
            mealCount: mealLogs.count,
            uniqueRecipeCount: Set(mealLogs.compactMap { $0.recipeID }).count
        )
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 16) {
                // Header with calm tone
                Text("This week's eating")
                    .font(.headline)
                    .foregroundStyle(Color.charcoal)

                if !mealLogs.isEmpty {
                    HStack(alignment: .top, spacing: 20) {
                        // Sparkline chart
                        VStack(alignment: .leading, spacing: 8) {
                            CalorieSparklineChart(data: dailyCalories)
                                .frame(height: 60)

                            if averageCalories > 0 {
                                Text("Avg: ~\(averageCalories) cal/day")
                                    .font(.caption)
                                    .foregroundStyle(Color.slateGray)
                            }
                        }
                        .frame(maxWidth: .infinity)

                        // Macro distribution ring
                        MacroDistributionRing(distribution: macroDistribution)
                            .frame(width: 100, height: 100)
                    }

                    // Positive observation
                    HStack(spacing: 8) {
                        Image(systemName: "text.bubble")
                            .foregroundStyle(Color.sageGreen)

                        Text(positiveObservation)
                            .font(.subheadline)
                            .foregroundStyle(Color.charcoal)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 4)

                    // Tap hint
                    HStack {
                        Spacer()
                        Text("See daily breakdown")
                            .font(.caption)
                            .foregroundStyle(Color.slateGray)
                        Image(systemName: "chevron.down")
                            .font(.caption)
                            .foregroundStyle(Color.slateGray)
                    }
                } else {
                    // Empty state within card
                    VStack(spacing: 8) {
                        Text("No meals logged yet this week")
                            .font(.subheadline)
                            .foregroundStyle(Color.slateGray)

                        Text("Tap the + button to log your first meal")
                            .font(.caption)
                            .foregroundStyle(Color.slateGray)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.offWhite)
                    .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(weeklyTrendAccessibilityLabel)
        .accessibilityHint("Double tap to see daily breakdown")
    }

    private var weeklyTrendAccessibilityLabel: String {
        var parts: [String] = ["This week's eating summary"]

        if !mealLogs.isEmpty {
            if averageCalories > 0 {
                parts.append("Average \(averageCalories) calories per day")
            }

            if macroDistribution.hasData {
                parts.append("Macros: \(Int(macroDistribution.proteinPercent))% protein, \(Int(macroDistribution.carbsPercent))% carbs, \(Int(macroDistribution.fatPercent))% fat")
            }

            parts.append(positiveObservation)
        } else {
            parts.append("No meals logged yet this week")
        }

        return parts.joined(separator: ". ")
    }
}

// MARK: - Supporting Types

struct DailyCalorieData: Identifiable {
    let id = UUID()
    let date: Date
    let calories: Int

    var dayAbbreviation: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }
}

struct MacroDistribution {
    let proteinPercent: Double
    let carbsPercent: Double
    let fatPercent: Double

    var hasData: Bool {
        proteinPercent > 0 || carbsPercent > 0 || fatPercent > 0
    }
}

// MARK: - Calorie Sparkline Chart

struct CalorieSparklineChart: View {
    let data: [DailyCalorieData]

    private var maxCalories: Int {
        data.map(\.calories).max() ?? 1
    }

    var body: some View {
        Chart(data) { item in
            LineMark(
                x: .value("Day", item.date, unit: .day),
                y: .value("Calories", item.calories)
            )
            .foregroundStyle(Color.sageGreen)
            .interpolationMethod(.catmullRom)

            AreaMark(
                x: .value("Day", item.date, unit: .day),
                y: .value("Calories", item.calories)
            )
            .foregroundStyle(
                LinearGradient(
                    colors: [Color.sageGreen.opacity(0.3), Color.sageGreen.opacity(0.05)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .interpolationMethod(.catmullRom)
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { value in
                if let date = value.as(Date.self) {
                    AxisValueLabel {
                        Text(dayAbbreviation(for: date))
                            .font(.caption2)
                            .foregroundStyle(Color.slateGray)
                    }
                }
            }
        }
        .chartYAxis(.hidden)
        .chartYScale(domain: 0...max(maxCalories, 1))
    }

    private func dayAbbreviation(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return String(formatter.string(from: date).prefix(1))
    }
}

// MARK: - Observation Generator

struct WeeklyObservationGenerator {
    /// Generates a positive, calm observation about the week's eating patterns
    static func generatePositiveObservation(
        dailyCalories: [DailyCalorieData],
        macroDistribution: MacroDistribution,
        mealCount: Int,
        uniqueRecipeCount: Int
    ) -> String {
        let observations: [String] = [
            checkProteinConsistency(macroDistribution),
            checkCaloriePattern(dailyCalories),
            checkMealVariety(uniqueRecipeCount),
            checkLoggingConsistency(dailyCalories)
        ].compactMap { $0 }

        return observations.first ?? "Keep enjoying your meals"
    }

    private static func checkProteinConsistency(_ distribution: MacroDistribution) -> String? {
        if distribution.proteinPercent >= 25 && distribution.proteinPercent <= 35 {
            return "Steady protein intake this week"
        } else if distribution.proteinPercent > 35 {
            return "Protein-rich eating this week"
        }
        return nil
    }

    private static func checkCaloriePattern(_ dailyCalories: [DailyCalorieData]) -> String? {
        let daysWithData = dailyCalories.filter { $0.calories > 0 }
        guard daysWithData.count >= 3 else { return nil }

        let calories = daysWithData.map(\.calories)
        let average = calories.reduce(0, +) / calories.count
        let variance = calories.map { abs($0 - average) }.reduce(0, +) / calories.count

        if Double(variance) / Double(average) < 0.2 {
            return "Steady patterns this week"
        } else {
            return "Varied eating this week"
        }
    }

    private static func checkMealVariety(_ uniqueRecipeCount: Int) -> String? {
        if uniqueRecipeCount >= 5 {
            return "Nice variety in your meals"
        }
        return nil
    }

    private static func checkLoggingConsistency(_ dailyCalories: [DailyCalorieData]) -> String? {
        let daysWithData = dailyCalories.filter { $0.calories > 0 }.count
        let today = Calendar.current.component(.weekday, from: Date())
        let daysIntoWeek = today == 1 ? 7 : today - 1

        if daysWithData >= daysIntoWeek - 1 && daysWithData > 0 {
            return "Consistent logging this week"
        }
        return nil
    }
}

#Preview {
    VStack {
        WeeklyTrendCard(
            mealLogs: [],
            recipeLookup: EmptyRecipeLookup(),
            onTap: {}
        )
        .padding()
    }
    .background(Color.gray.opacity(0.1))
}

/// Empty recipe lookup for previews
private struct EmptyRecipeLookup: RecipeMacroLookup {
    func macrosPerServing(for recipeID: UUID) -> MacroSummary? { nil }
}
