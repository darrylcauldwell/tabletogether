import SwiftUI

/// Expanded daily view card showing per-meal breakdown for a single day
/// Uses calm, positive language throughout
struct DayDetailCard: View {
    let date: Date
    let mealLogs: [PrivateMealLog]
    let recipeLookup: RecipeMacroLookup

    private var sortedLogs: [PrivateMealLog] {
        mealLogs.sorted { log1, log2 in
            mealTypeOrder(log1.mealType) < mealTypeOrder(log2.mealType)
        }
    }

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

    private var dayTotals: DayTotals {
        var calories = 0
        var protein = 0
        var carbs = 0
        var fat = 0

        for log in mealLogs {
            calories += caloriesFor(log) ?? 0
            protein += proteinFor(log) ?? 0
            carbs += carbsFor(log) ?? 0
            fat += fatFor(log) ?? 0
        }

        return DayTotals(
            calories: calories,
            protein: protein,
            carbs: carbs,
            fat: fat
        )
    }

    private var dayDescription: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date)
    }

    private var daySubtitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }

    private func mealTypeOrder(_ type: MealType) -> Int {
        switch type {
        case .breakfast: return 0
        case .lunch: return 1
        case .dinner: return 2
        case .snack: return 3
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Day header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(dayDescription)
                        .font(.headline)
                        .foregroundStyle(Color.charcoal)

                    Text(daySubtitle)
                        .font(.caption)
                        .foregroundStyle(Color.slateGray)
                }

                Spacer()

                // Day character badge
                DayCharacterBadge(totals: dayTotals)
            }

            Divider()
                .background(Color.slateGray.opacity(0.3))

            // Meal logs
            if sortedLogs.isEmpty {
                Text("No meals logged")
                    .font(.subheadline)
                    .foregroundStyle(Color.slateGray)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 8) {
                    ForEach(sortedLogs, id: \.id) { log in
                        MealLogRow(
                            log: log,
                            calories: caloriesFor(log),
                            protein: proteinFor(log),
                            recipeLookup: recipeLookup
                        )
                    }
                }
            }

            // Day totals (only if there are logs)
            if !sortedLogs.isEmpty {
                Divider()
                    .background(Color.slateGray.opacity(0.3))

                DayTotalsRow(totals: dayTotals)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.offWhite)
                .shadow(color: .black.opacity(0.03), radius: 4, x: 0, y: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(dayAccessibilityLabel)
    }

    private var dayAccessibilityLabel: String {
        var parts: [String] = [dayDescription, daySubtitle]

        if sortedLogs.isEmpty {
            parts.append("No meals logged")
        } else {
            parts.append("\(sortedLogs.count) meals logged")
            if dayTotals.calories > 0 {
                parts.append("Total \(dayTotals.calories) calories")
            }
        }

        return parts.joined(separator: ". ")
    }
}

// MARK: - Meal Log Row

struct MealLogRow: View {
    let log: PrivateMealLog
    let calories: Int?
    let protein: Int?
    let recipeLookup: RecipeMacroLookup

    private var mealName: String {
        if let recipeID = log.recipeID,
           let name = recipeLookup.recipeName(for: recipeID) {
            return name
        } else if let quickName = log.quickLogName {
            return quickName
        } else {
            return "Meal"
        }
    }

    private var mealTypeIcon: String {
        switch log.mealType {
        case .breakfast: return "sunrise"
        case .lunch: return "sun.max"
        case .dinner: return "moon.stars"
        case .snack: return "leaf"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            // Meal type icon
            Image(systemName: mealTypeIcon)
                .font(.system(size: 14))
                .foregroundStyle(Color.sageGreen)
                .frame(width: 24)

            // Meal name
            VStack(alignment: .leading, spacing: 2) {
                Text(mealName)
                    .font(.subheadline)
                    .foregroundStyle(Color.charcoal)
                    .lineLimit(1)

                Text(log.mealType.rawValue.capitalized)
                    .font(.caption2)
                    .foregroundStyle(Color.slateGray)
            }

            Spacer()

            // Macro chips
            HStack(spacing: 8) {
                if let cal = calories, cal > 0 {
                    CompactMacroChip(value: cal, unit: "cal", color: Color.warmOrange)
                }

                if let prot = protein, prot > 0 {
                    CompactMacroChip(value: prot, unit: "g", label: "P", color: Color.softBlue)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(mealLogAccessibilityLabel)
    }

    private var mealLogAccessibilityLabel: String {
        var parts: [String] = [log.mealType.rawValue.capitalized, mealName]

        if let cal = calories, cal > 0 {
            parts.append("\(cal) calories")
        }
        if let prot = protein, prot > 0 {
            parts.append("\(prot) grams protein")
        }

        return parts.joined(separator: ". ")
    }
}

// Note: Using CompactMacroChip to avoid conflict with MacroChip in Components.swift

struct CompactMacroChip: View {
    let value: Int
    let unit: String
    var label: String? = nil
    let color: Color

    var body: some View {
        HStack(spacing: 2) {
            if let label {
                Text(label)
                    .font(.caption2)
                    .fontWeight(.medium)
            }
            Text("\(value)")
                .font(.caption)
                .fontWeight(.medium)
            if label == nil {
                Text(unit)
                    .font(.caption2)
            }
        }
        .foregroundStyle(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(color.opacity(0.15))
        )
    }
}

// MARK: - Day Totals

struct DayTotals {
    let calories: Int
    let protein: Int
    let carbs: Int
    let fat: Int
}

struct DayTotalsRow: View {
    let totals: DayTotals

    var body: some View {
        HStack {
            Text("Day total")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(Color.charcoal)

            Spacer()

            HStack(spacing: 12) {
                if totals.calories > 0 {
                    Text("\(totals.calories) cal")
                        .font(.subheadline)
                        .foregroundStyle(Color.charcoal)
                }

                HStack(spacing: 8) {
                    if totals.protein > 0 {
                        Text("P: \(totals.protein)g")
                            .font(.caption)
                            .foregroundStyle(Color.slateGray)
                    }

                    if totals.carbs > 0 {
                        Text("C: \(totals.carbs)g")
                            .font(.caption)
                            .foregroundStyle(Color.slateGray)
                    }

                    if totals.fat > 0 {
                        Text("F: \(totals.fat)g")
                            .font(.caption)
                            .foregroundStyle(Color.slateGray)
                    }
                }
            }
        }
    }
}

// MARK: - Day Character Badge

/// Shows a calm descriptor for the day (Light, Steady, Hearty)
struct DayCharacterBadge: View {
    let totals: DayTotals

    private var character: DayCharacter {
        // Use a reasonable baseline of ~2000 calories for characterization
        // This is intentionally soft and non-judgmental
        let baseline = 2000

        if totals.calories == 0 {
            return .none
        } else if totals.calories < Int(Double(baseline) * 0.75) {
            return .light
        } else if totals.calories > Int(Double(baseline) * 1.25) {
            return .hearty
        } else {
            return .steady
        }
    }

    enum DayCharacter {
        case none
        case light
        case steady
        case hearty

        var label: String {
            switch self {
            case .none: return ""
            case .light: return "Light day"
            case .steady: return "Steady day"
            case .hearty: return "Hearty day"
            }
        }

        var color: Color {
            switch self {
            case .none: return .clear
            case .light: return Color.softBlue
            case .steady: return Color.sageGreen
            case .hearty: return Color.warmOrange
            }
        }
    }

    var body: some View {
        if character != .none {
            Text(character.label)
                .font(.caption)
                .foregroundStyle(character.color)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(character.color.opacity(0.15))
                )
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        DayDetailCard(
            date: Date(),
            mealLogs: [],
            recipeLookup: PreviewRecipeLookup()
        )

        DayDetailCard(
            date: Date().addingTimeInterval(-86400),
            mealLogs: [],
            recipeLookup: PreviewRecipeLookup()
        )
    }
    .padding()
    .background(Color.gray.opacity(0.1))
}

/// Empty recipe lookup for previews
private struct PreviewRecipeLookup: RecipeMacroLookup {
    func macrosPerServing(for recipeID: UUID) -> MacroSummary? { nil }
}
