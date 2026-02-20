import SwiftUI

// MARK: - Meal Card

/// Large, glanceable card for displaying a planned meal.
/// Designed to be readable from across the room.
struct TVMealCard: View {
    let mealSlot: MealSlot
    var showTime: Bool = true
    var onSelect: (() -> Void)?

    @Environment(\.isFocused) private var isFocused

    private var mealTypeColor: Color {
        TVTheme.Colors.mealTypeColor(mealSlot.mealType)
    }

    private var mealTime: String {
        switch mealSlot.mealType {
        case .breakfast: return "8:00 AM"
        case .lunch: return "12:00 PM"
        case .dinner: return "6:00 PM"
        case .snack: return "3:00 PM"
        }
    }

    var body: some View {
        Button(action: { onSelect?() }) {
            VStack(alignment: .leading, spacing: TVTheme.Spacing.md) {
                // Header: Meal type and time
                HStack {
                    HStack(spacing: TVTheme.Spacing.sm) {
                        Image(systemName: mealSlot.mealType.iconName)
                            .font(TVTheme.Typography.headline)
                            .foregroundStyle(mealTypeColor)

                        Text(mealSlot.mealType.displayName)
                            .font(TVTheme.Typography.headline)
                            .foregroundStyle(mealTypeColor)
                    }

                    Spacer()

                    if showTime {
                        Text(mealTime)
                            .font(TVTheme.Typography.subheadline)
                            .foregroundStyle(TVTheme.Colors.textSecondary)
                    }
                }

                // Main content
                if mealSlot.isPlanned {
                    VStack(alignment: .leading, spacing: TVTheme.Spacing.sm) {
                        // Recipe/meal title
                        Text(mealSlot.displayTitle)
                            .font(TVTheme.Typography.title2)
                            .foregroundStyle(TVTheme.Colors.textPrimary)
                            .lineLimit(2)

                        // Recipe info row
                        if let recipe = mealSlot.recipes.first {
                            HStack(spacing: TVTheme.Spacing.md) {
                                if let totalTime = recipe.totalTimeMinutes {
                                    TVTimeChip(minutes: totalTime)
                                }

                                if let archetype = recipe.suggestedArchetypes.first {
                                    TVArchetypeBadge(archetype: archetype)
                                }

                                Spacer()
                            }
                        }

                        // Assigned users
                        if !mealSlot.assignedTo.isEmpty {
                            HStack(spacing: -TVTheme.Spacing.sm) {
                                ForEach(mealSlot.assignedTo.prefix(4)) { user in
                                    TVUserAvatar(user: user, size: 44, showName: false)
                                }

                                if mealSlot.assignedTo.count > 4 {
                                    Text("+\(mealSlot.assignedTo.count - 4)")
                                        .font(TVTheme.Typography.subheadline)
                                        .foregroundStyle(TVTheme.Colors.textSecondary)
                                        .padding(.leading, TVTheme.Spacing.sm)
                                }
                            }
                        }
                    }
                } else if mealSlot.isSkipped {
                    Text("Skipped")
                        .font(TVTheme.Typography.title3)
                        .foregroundStyle(TVTheme.Colors.textTertiary)
                        .italic()
                } else {
                    Text("No meal planned")
                        .font(TVTheme.Typography.title3)
                        .foregroundStyle(TVTheme.Colors.textTertiary)
                }

                // Notes
                if let notes = mealSlot.notes, !notes.isEmpty {
                    Text(notes)
                        .font(TVTheme.Typography.callout)
                        .foregroundStyle(TVTheme.Colors.textSecondary)
                        .lineLimit(2)
                }
            }
            .padding(TVTheme.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: TVTheme.CornerRadius.large)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: TVTheme.CornerRadius.large)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        mealTypeColor.opacity(0.15),
                                        TVTheme.Colors.glassBackground
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: TVTheme.CornerRadius.large)
                            .strokeBorder(
                                isFocused ? TVTheme.Colors.focusRing : mealTypeColor.opacity(0.3),
                                lineWidth: isFocused ? 4 : 1
                            )
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: TVTheme.CornerRadius.large))
        }
        .buttonStyle(.plain)
        .scaleEffect(isFocused ? TVTheme.FocusScale.card : 1.0)
        .shadow(
            color: isFocused ? mealTypeColor.opacity(0.4) : .clear,
            radius: isFocused ? 30 : 0
        )
        .animation(
            isFocused ? TVTheme.Animation.focusIn : TVTheme.Animation.focusOut,
            value: isFocused
        )
    }
}

// MARK: - Compact Meal Row

/// Compact meal display for lists and sidebars.
struct TVMealRow: View {
    let mealSlot: MealSlot

    @Environment(\.isFocused) private var isFocused

    private var mealTypeColor: Color {
        TVTheme.Colors.mealTypeColor(mealSlot.mealType)
    }

    var body: some View {
        HStack(spacing: TVTheme.Spacing.md) {
            // Meal type icon
            Image(systemName: mealSlot.mealType.iconName)
                .font(TVTheme.Typography.title3)
                .foregroundStyle(mealTypeColor)
                .frame(width: 48)

            // Content
            VStack(alignment: .leading, spacing: TVTheme.Spacing.xs) {
                Text(mealSlot.mealType.displayName)
                    .font(TVTheme.Typography.subheadline)
                    .foregroundStyle(mealTypeColor)

                Text(mealSlot.displayTitle)
                    .font(TVTheme.Typography.headline)
                    .foregroundStyle(TVTheme.Colors.textPrimary)
                    .lineLimit(1)
            }

            Spacer()

            // Time indicator
            if let recipe = mealSlot.recipes.first, let time = recipe.totalTimeMinutes {
                Text("\(time) min")
                    .font(TVTheme.Typography.callout)
                    .foregroundStyle(TVTheme.Colors.textSecondary)
            }
        }
        .padding(TVTheme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: TVTheme.CornerRadius.medium)
                .fill(isFocused ? TVTheme.Colors.glassHighlight : TVTheme.Colors.glassBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: TVTheme.CornerRadius.medium)
                .strokeBorder(
                    isFocused ? TVTheme.Colors.focusRing : .clear,
                    lineWidth: 2
                )
        )
        .scaleEffect(isFocused ? TVTheme.FocusScale.small : 1.0)
        .animation(TVTheme.Animation.focusIn, value: isFocused)
    }
}

// MARK: - Day Header

/// Header showing the day name with visual indicator for today.
struct TVDayHeader: View {
    let day: DayOfWeek
    let date: Date
    var isToday: Bool = false

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }

    var body: some View {
        HStack(spacing: TVTheme.Spacing.md) {
            VStack(alignment: .leading, spacing: TVTheme.Spacing.xs) {
                HStack(spacing: TVTheme.Spacing.sm) {
                    Text(day.fullName)
                        .font(TVTheme.Typography.title2)
                        .foregroundStyle(isToday ? TVTheme.Colors.primary : TVTheme.Colors.textPrimary)

                    if isToday {
                        Text("TODAY")
                            .font(TVTheme.Typography.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(TVTheme.Colors.primary)
                            .padding(.horizontal, TVTheme.Spacing.sm)
                            .padding(.vertical, TVTheme.Spacing.xs)
                            .background(
                                Capsule()
                                    .fill(TVTheme.Colors.primary.opacity(0.2))
                            )
                    }
                }

                Text(formattedDate)
                    .font(TVTheme.Typography.subheadline)
                    .foregroundStyle(TVTheme.Colors.textSecondary)
            }

            Spacer()
        }
    }
}

#Preview("Meal Card") {
    ZStack {
        Color.black.ignoresSafeArea()

        VStack(spacing: 32) {
            Text("Preview requires actual MealSlot data")
                .font(TVTheme.Typography.body)
                .foregroundStyle(TVTheme.Colors.textSecondary)
        }
        .tvSafeArea()
    }
}
