import SwiftUI

// MARK: - Color Convenience Extensions
// Note: Color(hex:) is defined in Theme.swift

extension Color {
    // Convenience aliases to Theme.Colors
    static var appPrimary: Color { Theme.Colors.primary }
    static var appSecondary: Color { Theme.Colors.secondary }
    static var appBackground: Color { Theme.Colors.background }
    static var appTextPrimary: Color { Theme.Colors.textPrimary }
    static var appTextSecondary: Color { Theme.Colors.textSecondary }
    static var appPositive: Color { Theme.Colors.positive }
    static var appNeutral: Color { Theme.Colors.neutral }

    /// Gets the color for an archetype type
    static func archetypeColor(for archetype: ArchetypeType) -> Color {
        Color(hex: archetype.colorHex)
    }
}

// MARK: - Font Convenience Extensions

extension Font {
    static var appTitle: Font { Theme.Typography.largeTitle }
    static var appHeading: Font { Theme.Typography.title2 }
    static var appSubheading: Font { Theme.Typography.title3 }
    static var appBody: Font { Theme.Typography.body }
    static var appCaption: Font { Theme.Typography.caption }
}

// MARK: - Button Styles

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .headline) private var horizontalPadding: CGFloat = 24
    @ScaledMetric(relativeTo: .headline) private var verticalPadding: CGFloat = 12

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Typography.headline)
            .foregroundStyle(.white)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .frame(minHeight: 44) // Minimum touch target
            .background(Theme.Colors.primary)
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1.0)
            .animation(reduceMotion ? nil : Theme.Animation.quick, value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .headline) private var horizontalPadding: CGFloat = 24
    @ScaledMetric(relativeTo: .headline) private var verticalPadding: CGFloat = 12

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Typography.headline)
            .foregroundStyle(Theme.Colors.primary)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .frame(minHeight: 44) // Minimum touch target
            .background(Theme.Colors.primary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1.0)
            .animation(reduceMotion ? nil : Theme.Animation.quick, value: configuration.isPressed)
    }
}

struct DestructiveButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .headline) private var horizontalPadding: CGFloat = 24
    @ScaledMetric(relativeTo: .headline) private var verticalPadding: CGFloat = 12

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Typography.headline)
            .foregroundStyle(.white)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .frame(minHeight: 44) // Minimum touch target
            .background(Color.red)
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1.0)
            .animation(reduceMotion ? nil : Theme.Animation.quick, value: configuration.isPressed)
    }
}

// MARK: - Chip Style Modifier

struct ChipStyleModifier: ViewModifier {
    let color: Color

    func body(content: Content) -> some View {
        content
            .font(Theme.Typography.caption)
            .fontWeight(.medium)
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
    }
}

extension View {
    func chipStyle(color: Color = Theme.Colors.primary) -> some View {
        modifier(ChipStyleModifier(color: color))
    }
}

// MARK: - Floating Action Button

struct FloatingActionButton<Content: View>: View {
    let action: () -> Void
    var accessibilityLabel: String = "Add"
    @ViewBuilder let content: () -> Content

    @ScaledMetric(relativeTo: .title2) private var buttonSize: CGFloat = 56

    var body: some View {
        Button(action: action) {
            content()
                .font(Theme.Typography.title2)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .frame(width: max(buttonSize, 56), height: max(buttonSize, 56)) // Ensure minimum 56pt touch target
                .background(Theme.Colors.primary)
                .clipShape(Circle())
                .shadow(color: Theme.Colors.primary.opacity(0.4), radius: 8, x: 0, y: 4)
        }
        .accessibilityLabel(accessibilityLabel)
    }
}

// MARK: - Search Bar

struct SearchBar: View {
    @Binding var text: String
    var placeholder: String = "Search"

    @ScaledMetric(relativeTo: .body) private var padding: CGFloat = 12

    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.Colors.textSecondary)
                .accessibilityHidden(true)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .accessibilityLabel("Search")
                .accessibilityHint("Enter text to search")

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .accessibilityLabel("Clear search")
                .accessibilityTouchTarget()
            }
        }
        .padding(padding)
        .background(Color.systemGray6)
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
    }
}

// MARK: - Filter Chip

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    var icon: String?
    let action: () -> Void

    @ScaledMetric(relativeTo: .caption) private var horizontalPadding: CGFloat = 12
    @ScaledMetric(relativeTo: .caption) private var verticalPadding: CGFloat = 8

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.xs) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(Theme.Typography.caption)
                }
                Text(title)
                    .font(Theme.Typography.caption)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .frame(minHeight: 44) // Minimum touch target
            .background(isSelected ? Theme.Colors.primary : Color.systemGray6)
            .foregroundStyle(isSelected ? .white : Theme.Colors.textPrimary)
            .clipShape(Capsule())
        }
        .accessibilityLabel("\(title) filter")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityHint(isSelected ? "Double tap to deselect" : "Double tap to select")
    }
}

// MARK: - Empty State View

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var action: (() -> Void)?
    var actionLabel: String?

    @ScaledMetric(relativeTo: .title) private var iconSize: CGFloat = 48

    var body: some View {
        VStack(spacing: Theme.Spacing.standard) {
            Image(systemName: icon)
                .font(.system(size: iconSize))
                .foregroundStyle(Theme.Colors.textSecondary)
                .accessibilityHidden(true)

            Text(title)
                .font(Theme.Typography.title2)
                .foregroundStyle(Theme.Colors.textPrimary)
                .accessibilityAddTraits(.isHeader)

            Text(message)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Spacing.xl)

            if let action = action, let actionLabel = actionLabel {
                Button(action: action) {
                    Text(actionLabel)
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.top, Theme.Spacing.sm)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Time Chip

struct TimeChip: View {
    let minutes: Int

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: "clock")
                .font(Theme.Typography.caption)
                .accessibilityHidden(true)
            Text(formattedTime)
                .font(Theme.Typography.caption)
                .fontWeight(.medium)
        }
        .chipStyle(color: Theme.Colors.textSecondary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityFormattedTime)
    }

    private var formattedTime: String {
        if minutes < 60 {
            return "\(minutes) min"
        } else {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            if remainingMinutes == 0 {
                return "\(hours) hr"
            } else {
                return "\(hours) hr \(remainingMinutes) min"
            }
        }
    }

    private var accessibilityFormattedTime: String {
        if minutes < 60 {
            return "\(minutes) \(minutes == 1 ? "minute" : "minutes")"
        } else {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            let hourText = hours == 1 ? "hour" : "hours"
            if remainingMinutes == 0 {
                return "\(hours) \(hourText)"
            } else {
                let minuteText = remainingMinutes == 1 ? "minute" : "minutes"
                return "\(hours) \(hourText) \(remainingMinutes) \(minuteText)"
            }
        }
    }
}

// MARK: - Favorite Button

struct FavoriteButton: View {
    @Binding var isFavorite: Bool
    var size: CGFloat = 24

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var scaledSize: CGFloat = 24

    private var effectiveSize: CGFloat {
        max(scaledSize, size)
    }

    var body: some View {
        Button {
            if reduceMotion {
                isFavorite.toggle()
            } else {
                withAnimation(Theme.Animation.spring) {
                    isFavorite.toggle()
                }
            }
        } label: {
            Image(systemName: isFavorite ? "heart.fill" : "heart")
                .font(.system(size: effectiveSize))
                .foregroundStyle(isFavorite ? Color.red : Theme.Colors.textSecondary)
                .scaleEffect(isFavorite && !reduceMotion ? 1.1 : 1.0)
                .frame(minWidth: 44, minHeight: 44) // Minimum touch target
        }
        .accessibilityLabel(isFavorite ? "Remove from favorites" : "Add to favorites")
        .accessibilityAddTraits(isFavorite ? [.isSelected] : [])
    }
}

// MARK: - Previews

#Preview("Button Styles") {
    VStack(spacing: Theme.Spacing.standard) {
        Button("Primary Button") {}
            .buttonStyle(PrimaryButtonStyle())

        Button("Secondary Button") {}
            .buttonStyle(SecondaryButtonStyle())

        Button("Destructive Button") {}
            .buttonStyle(DestructiveButtonStyle())
    }
    .padding()
}

#Preview("Components") {
    VStack(spacing: Theme.Spacing.standard) {
        SearchBar(text: .constant(""))

        HStack {
            FilterChip(title: "All", isSelected: true) {}
            FilterChip(title: "Quick", isSelected: false, icon: "bolt.fill") {}
            FilterChip(title: "Favorites", isSelected: false, icon: "heart.fill") {}
        }

        TimeChip(minutes: 45)
        TimeChip(minutes: 90)

        HStack {
            FavoriteButton(isFavorite: .constant(false))
            FavoriteButton(isFavorite: .constant(true))
        }
    }
    .padding()
}
