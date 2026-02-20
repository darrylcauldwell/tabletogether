import SwiftUI

// MARK: - Glass Card

/// A translucent card with subtle glass effect for tvOS.
/// Adapts to focus state with scale and glow effects.
struct TVGlassCard<Content: View>: View {
    @Environment(\.isFocused) private var isFocused
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(TVTheme.Spacing.standard)
            .background(
                RoundedRectangle(cornerRadius: TVTheme.CornerRadius.standard)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: TVTheme.CornerRadius.standard)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        TVTheme.Colors.glassHighlight,
                                        TVTheme.Colors.glassBackground
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: TVTheme.CornerRadius.standard)
                            .strokeBorder(
                                isFocused ? TVTheme.Colors.focusRing : TVTheme.Colors.glassBorder,
                                lineWidth: isFocused ? 4 : 1
                            )
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: TVTheme.CornerRadius.standard))
            .scaleEffect(isFocused ? TVTheme.FocusScale.card : 1.0)
            .shadow(
                color: isFocused ? TVTheme.Colors.focusGlow : .clear,
                radius: isFocused ? 30 : 0
            )
            .animation(
                isFocused ? TVTheme.Animation.focusIn : TVTheme.Animation.focusOut,
                value: isFocused
            )
    }
}

// MARK: - Section Header

/// A glass section header for organizing content.
struct TVSectionHeader: View {
    let title: String
    var subtitle: String?
    var icon: String?

    var body: some View {
        HStack(spacing: TVTheme.Spacing.md) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(TVTheme.Typography.title3)
                    .foregroundStyle(TVTheme.Colors.primary)
            }

            VStack(alignment: .leading, spacing: TVTheme.Spacing.xs) {
                Text(title)
                    .font(TVTheme.Typography.title3)
                    .foregroundStyle(TVTheme.Colors.textPrimary)

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(TVTheme.Typography.callout)
                        .foregroundStyle(TVTheme.Colors.textSecondary)
                }
            }

            Spacer()
        }
        .padding(.horizontal, TVTheme.Spacing.standard)
        .padding(.vertical, TVTheme.Spacing.md)
    }
}

// MARK: - Time Chip

/// Displays cooking time with a clock icon.
struct TVTimeChip: View {
    let minutes: Int

    private var formattedTime: String {
        if minutes >= 60 {
            let hours = minutes / 60
            let mins = minutes % 60
            if mins == 0 {
                return "\(hours) hr"
            }
            return "\(hours) hr \(mins) min"
        }
        return "\(minutes) min"
    }

    var body: some View {
        HStack(spacing: TVTheme.Spacing.sm) {
            Image(systemName: "clock.fill")
                .font(TVTheme.Typography.callout)
            Text(formattedTime)
                .font(TVTheme.Typography.callout)
        }
        .foregroundStyle(TVTheme.Colors.textSecondary)
        .padding(.horizontal, TVTheme.Spacing.md)
        .padding(.vertical, TVTheme.Spacing.sm)
        .background(
            Capsule()
                .fill(TVTheme.Colors.glassBackground)
        )
    }
}

// MARK: - Archetype Badge

/// Displays a meal archetype with icon and colored background.
struct TVArchetypeBadge: View {
    let archetype: ArchetypeType

    var body: some View {
        HStack(spacing: TVTheme.Spacing.sm) {
            Image(systemName: archetype.iconName)
                .font(TVTheme.Typography.callout)
            Text(archetype.displayName)
                .font(TVTheme.Typography.callout)
                .fontWeight(.medium)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, TVTheme.Spacing.md)
        .padding(.vertical, TVTheme.Spacing.sm)
        .background(
            Capsule()
                .fill(Color(hex: archetype.colorHex).opacity(0.8))
        )
    }
}

// MARK: - User Avatar (Large)

/// Large avatar for tvOS household presence.
struct TVUserAvatar: View {
    let user: User
    var size: CGFloat = 80
    var showName: Bool = true

    var body: some View {
        VStack(spacing: TVTheme.Spacing.sm) {
            ZStack {
                Circle()
                    .fill(Color(hex: user.avatarColorHex))
                    .frame(width: size, height: size)

                Text(user.avatarEmoji)
                    .font(.system(size: size * 0.5))
            }

            if showName {
                Text(user.displayName)
                    .font(TVTheme.Typography.subheadline)
                    .foregroundStyle(TVTheme.Colors.textSecondary)
            }
        }
    }
}

// MARK: - Countdown Timer Display

/// Large, glanceable countdown timer.
struct TVCountdownTimer: View {
    let targetDate: Date
    let label: String

    @State private var timeRemaining: TimeInterval = 0
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var formattedTime: String {
        if timeRemaining <= 0 {
            return "Now"
        }

        let hours = Int(timeRemaining) / 3600
        let minutes = (Int(timeRemaining) % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    private var urgencyColor: Color {
        if timeRemaining <= 600 { // 10 minutes
            return TVTheme.Colors.secondary
        } else if timeRemaining <= 1800 { // 30 minutes
            return TVTheme.Colors.warm
        }
        return TVTheme.Colors.textSecondary
    }

    var body: some View {
        VStack(spacing: TVTheme.Spacing.sm) {
            Text(label)
                .font(TVTheme.Typography.callout)
                .foregroundStyle(TVTheme.Colors.textSecondary)

            Text(formattedTime)
                .font(TVTheme.Typography.timer)
                .foregroundStyle(urgencyColor)
                .monospacedDigit()
        }
        .onReceive(timer) { _ in
            timeRemaining = targetDate.timeIntervalSinceNow
        }
        .onAppear {
            timeRemaining = targetDate.timeIntervalSinceNow
        }
    }
}

// MARK: - Reaction Button

/// Simple reaction button for household collaboration.
struct TVReactionButton: View {
    let emoji: String
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.isFocused) private var isFocused

    var body: some View {
        Button(action: action) {
            HStack(spacing: TVTheme.Spacing.sm) {
                Text(emoji)
                    .font(.system(size: 32))

                if count > 0 {
                    Text("\(count)")
                        .font(TVTheme.Typography.headline)
                        .foregroundStyle(TVTheme.Colors.textPrimary)
                }
            }
            .padding(.horizontal, TVTheme.Spacing.md)
            .padding(.vertical, TVTheme.Spacing.sm)
            .background(
                Capsule()
                    .fill(isSelected ? TVTheme.Colors.primary.opacity(0.3) : TVTheme.Colors.glassBackground)
            )
            .overlay(
                Capsule()
                    .strokeBorder(
                        isSelected ? TVTheme.Colors.primary : (isFocused ? TVTheme.Colors.focusRing : TVTheme.Colors.glassBorder),
                        lineWidth: isFocused ? 3 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(isFocused ? TVTheme.FocusScale.button : 1.0)
        .animation(TVTheme.Animation.focusIn, value: isFocused)
    }
}

// MARK: - Progress Indicator

/// Gentle step progress indicator.
struct TVStepProgress: View {
    let currentStep: Int
    let totalSteps: Int

    var body: some View {
        HStack(spacing: TVTheme.Spacing.md) {
            Text("Step \(currentStep)")
                .font(TVTheme.Typography.headline)
                .foregroundStyle(TVTheme.Colors.textPrimary)

            Text("of \(totalSteps)")
                .font(TVTheme.Typography.headline)
                .foregroundStyle(TVTheme.Colors.textSecondary)

            Spacer()

            // Visual progress dots
            HStack(spacing: TVTheme.Spacing.sm) {
                ForEach(1...totalSteps, id: \.self) { step in
                    Circle()
                        .fill(step <= currentStep ? TVTheme.Colors.primary : TVTheme.Colors.glassBackground)
                        .frame(width: 12, height: 12)
                }
            }
        }
    }
}

// MARK: - Empty State

/// Friendly empty state for when there's no content.
struct TVEmptyState: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: TVTheme.Spacing.lg) {
            Image(systemName: icon)
                .font(.system(size: 80))
                .foregroundStyle(TVTheme.Colors.textTertiary)

            VStack(spacing: TVTheme.Spacing.md) {
                Text(title)
                    .font(TVTheme.Typography.title2)
                    .foregroundStyle(TVTheme.Colors.textPrimary)

                Text(message)
                    .font(TVTheme.Typography.body)
                    .foregroundStyle(TVTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 600)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview("Glass Card") {
    ZStack {
        Color.black.ignoresSafeArea()

        TVGlassCard {
            VStack(alignment: .leading, spacing: 16) {
                Text("Dinner")
                    .font(TVTheme.Typography.headline)
                    .foregroundStyle(TVTheme.Colors.textPrimary)

                Text("Chicken Tikka Masala")
                    .font(TVTheme.Typography.title3)
                    .foregroundStyle(TVTheme.Colors.textPrimary)
            }
        }
        .frame(width: 400)
    }
}
