import SwiftUI
import SwiftData

// MARK: - DayColumnView

/// Single day column showing the day header and meal slots.
/// Used in both the full week grid (iPad) and day-by-day view (iPhone).
struct DayColumnView: View {
    let day: DayOfWeek
    let weekStartDate: Date
    let slots: [MealSlot]
    let onSlotTapped: (MealSlot) -> Void
    let onRecipeDropped: (String, MealSlot) -> Void  // Receives recipe UUID string

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isCompact: Bool {
        horizontalSizeClass == .compact
    }

    var body: some View {
        VStack(spacing: isCompact ? 8 : 6) {
            DayHeaderView(
                day: day,
                weekStartDate: weekStartDate,
                isCompact: isCompact
            )

            ForEach(MealType.allCases, id: \.self) { mealType in
                if let slot = slots.first(where: { $0.mealType == mealType }) {
                    MealSlotView(
                        slot: slot,
                        isCompact: isCompact,
                        onTapped: { onSlotTapped(slot) },
                        onRecipeDropped: { recipeId in onRecipeDropped(recipeId, slot) }
                    )
                } else {
                    EmptyMealSlotPlaceholder(mealType: mealType, isCompact: isCompact)
                }
            }
        }
    }
}

// MARK: - DayHeaderView

/// Header for a day column showing day name and date
struct DayHeaderView: View {
    let day: DayOfWeek
    let weekStartDate: Date
    let isCompact: Bool

    private var dateForDay: Date {
        Calendar.current.date(byAdding: .day, value: day.rawValue - 1, to: weekStartDate) ?? weekStartDate
    }

    private var isToday: Bool {
        Calendar.current.isDateInToday(dateForDay)
    }

    private var dateLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: dateForDay)
    }

    private var monthLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        return formatter.string(from: dateForDay)
    }

    var body: some View {
        VStack(spacing: 2) {
            if isCompact {
                // iPhone: Show full day name with date
                HStack {
                    Text(day.fullName)
                        .font(.title2)
                        .fontWeight(.semibold)

                    Spacer()

                    Text("\(monthLabel) \(dateLabel)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(isToday ? Color.accentColor.opacity(0.1) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                // iPad: Compact column header
                Text(day.shortName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)

                Text(dateLabel)
                    .font(.title3)
                    .fontWeight(isToday ? .bold : .medium)
                    .foregroundColor(isToday ? .accentColor : .primary)
                    .frame(width: 32, height: 32)
                    .background(isToday ? Color.accentColor.opacity(0.15) : Color.clear)
                    .clipShape(Circle())
            }
        }
        .padding(.bottom, 4)
    }
}

// MARK: - EmptyMealSlotPlaceholder

/// Placeholder view for slots that don't exist yet
struct EmptyMealSlotPlaceholder: View {
    let mealType: MealType
    let isCompact: Bool

    var body: some View {
        Group {
            if isCompact {
                VStack(spacing: 4) {
                    Image(systemName: mealType.icon)
                        .font(.title3)
                        .foregroundColor(.secondary.opacity(0.5))

                    Text(mealType.displayName)
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.5))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 60)
            } else {
                HStack(spacing: 4) {
                    Image(systemName: mealType.icon)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary.opacity(0.4))

                    Text(mealType.displayName)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary.opacity(0.4))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 32)
            }
        }
        .background(Color.systemGray6.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: isCompact ? 8 : 6))
        .overlay(
            RoundedRectangle(cornerRadius: isCompact ? 8 : 6)
                .strokeBorder(style: StrokeStyle(lineWidth: 0.5, dash: [3]))
                .foregroundColor(.secondary.opacity(0.2))
        )
    }
}

// MARK: - Preview

#Preview("Day Column - Regular") {
    ScrollView {
        HStack(alignment: .top, spacing: 16) {
            ForEach(DayOfWeek.allCases.prefix(3), id: \.self) { day in
                DayColumnView(
                    day: day,
                    weekStartDate: Date(),
                    slots: [],
                    onSlotTapped: { _ in },
                    onRecipeDropped: { _, _ in }
                )
                .frame(width: 120)
            }
        }
        .padding()
    }
    .modelContainer(for: [MealSlot.self, WeekPlan.self, Recipe.self], inMemory: true)
}

#Preview("Day Column - Compact") {
    ScrollView {
        DayColumnView(
            day: .monday,
            weekStartDate: Date(),
            slots: [],
            onSlotTapped: { _ in },
            onRecipeDropped: { _, _ in }
        )
        .padding()
    }
    .modelContainer(for: [MealSlot.self, WeekPlan.self, Recipe.self], inMemory: true)
    .environment(\.horizontalSizeClass, .compact)
}
