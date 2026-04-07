import SwiftUI
import CoreData

/// A small personal-nutrition card that summarises the **planned** macros across
/// the active WeekPlan. Sits alongside the existing Apple Health card and the
/// retrospective Weekly Trend card to give the user a forward-looking view:
/// "Your planned week averages this much per day."
///
/// This is a personal view — per the CLAUDE.md sharing spec, numeric nutrition
/// totals only appear in personal contexts (this Nutrition tab), never in the
/// shared planning grid.
///
/// The card aggregates `MealSlot.plannedMacros` (added in #45) across every
/// slot in the active WeekPlan, then divides by 7 to express a daily average.
/// If no slot has macro data, the card hides itself entirely — no nudge, no
/// "log more meals" prompt, per the spec.
struct WeekPlannedNutritionCard: View {
    let weekPlan: WeekPlan?

    private var dailyAverage: MacroSummary? {
        guard let weekPlan, let slots = weekPlan.slots as? Set<MealSlot> else {
            return nil
        }

        var totalCalories: Double = 0
        var totalProtein: Double = 0
        var totalCarbs: Double = 0
        var totalFat: Double = 0
        var hasAny = false

        for slot in slots {
            guard let macros = slot.plannedMacros else { continue }
            hasAny = true
            if let cal = macros.calories { totalCalories += cal }
            if let p = macros.protein { totalProtein += p }
            if let c = macros.carbs { totalCarbs += c }
            if let f = macros.fat { totalFat += f }
        }

        guard hasAny else { return nil }

        // Average over a 7-day week
        return MacroSummary(
            calories: totalCalories > 0 ? totalCalories / 7 : nil,
            protein: totalProtein > 0 ? totalProtein / 7 : nil,
            carbs: totalCarbs > 0 ? totalCarbs / 7 : nil,
            fat: totalFat > 0 ? totalFat / 7 : nil
        )
    }

    var body: some View {
        if let average = dailyAverage {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "calendar.badge.clock")
                        .font(.headline)
                        .foregroundStyle(Theme.Colors.primary)
                    Text("This week, planned")
                        .font(.headline)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Spacer()
                }

                Text("Your planned week averages this per day, before you log anything.")
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                MacroSummaryRow(summary: average)
            }
            .padding()
            .background(Theme.Colors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
        }
        // When dailyAverage is nil the card renders nothing — no nudge, no
        // "log more meals" prompt, per the CLAUDE.md spec for respectful
        // nutrition feedback.
    }
}
