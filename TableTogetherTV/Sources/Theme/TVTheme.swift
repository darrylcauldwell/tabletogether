import SwiftUI

// MARK: - tvOS Design System
//
// Adapted from TableTogether's iOS design system for large-screen, focus-based navigation.
// Key differences:
// - Larger typography (readable from 10+ feet)
// - Glass-first aesthetic (translucent cards with blur)
// - Focus states with scale and glow
// - Dark-first design (tvOS default)
// - Gentle, slow animations (0.25-0.35s)

enum TVTheme {
    // MARK: - Colors

    enum Colors {
        // Primary palette
        static let primary = Color(hex: "8FBC8F")      // Sage Green
        static let secondary = Color(hex: "E8A87C")    // Warm Orange

        // tvOS backgrounds (dark-first)
        static let background = Color(hex: "1C1C1E")
        static let backgroundElevated = Color(hex: "2C2C2E")

        // Glass effect colors
        static let glassBackground = Color.white.opacity(0.08)
        static let glassBorder = Color.white.opacity(0.12)
        static let glassHighlight = Color.white.opacity(0.15)

        // Text colors (high contrast for readability)
        static let textPrimary = Color(hex: "F5F5F5")
        static let textSecondary = Color(hex: "A0A0A5")
        static let textTertiary = Color(hex: "6E6E73")

        // Semantic colors (never judgmental)
        static let positive = Color(hex: "90EE90")     // Soft Green
        static let neutral = Color(hex: "B0C4DE")      // Soft Blue
        static let warm = Color(hex: "FFB74D")         // Warm accent

        // Focus state
        static let focusRing = Color.white.opacity(0.9)
        static let focusGlow = primary.opacity(0.4)

        // Meal type colors
        static let breakfast = Color(hex: "FFD54F")    // Warm yellow
        static let lunch = Color(hex: "81C784")        // Fresh green
        static let dinner = Color(hex: "64B5F6")       // Cool blue
        static let snack = Color(hex: "FFB74D")        // Orange

        static func mealTypeColor(_ type: MealType) -> Color {
            switch type {
            case .breakfast: return breakfast
            case .lunch: return lunch
            case .dinner: return dinner
            case .snack: return snack
            }
        }
    }

    // MARK: - Typography (Large Screen Optimized)

    enum Typography {
        // Hero text (for ambient display)
        static let hero = Font.system(size: 76, weight: .semibold, design: .rounded)

        // Large titles
        static let largeTitle = Font.system(size: 56, weight: .semibold, design: .rounded)
        static let title = Font.system(size: 48, weight: .semibold, design: .rounded)
        static let title2 = Font.system(size: 40, weight: .medium, design: .rounded)
        static let title3 = Font.system(size: 34, weight: .medium, design: .rounded)

        // Body text (readable from across the room)
        static let headline = Font.system(size: 32, weight: .semibold, design: .rounded)
        static let body = Font.system(size: 29, weight: .regular, design: .rounded)
        static let bodyLarge = Font.system(size: 34, weight: .regular, design: .rounded)
        static let callout = Font.system(size: 26, weight: .regular, design: .rounded)

        // Supporting text
        static let subheadline = Font.system(size: 24, weight: .medium, design: .rounded)
        static let footnote = Font.system(size: 21, weight: .regular, design: .rounded)
        static let caption = Font.system(size: 19, weight: .regular, design: .rounded)

        // Monospace for timers/numbers
        static let timer = Font.system(size: 64, weight: .light, design: .monospaced)
        static let timerSmall = Font.system(size: 40, weight: .light, design: .monospaced)
        static let stepNumber = Font.system(size: 48, weight: .bold, design: .monospaced)
    }

    // MARK: - Spacing (Scaled for TV)

    enum Spacing {
        static let xs: CGFloat = 8
        static let sm: CGFloat = 16
        static let md: CGFloat = 24
        static let standard: CGFloat = 32
        static let lg: CGFloat = 48
        static let xl: CGFloat = 64
        static let xxl: CGFloat = 96

        // Safe area insets for tvOS
        static let safeAreaHorizontal: CGFloat = 90
        static let safeAreaVertical: CGFloat = 60
    }

    // MARK: - Corner Radius

    enum CornerRadius {
        static let small: CGFloat = 12
        static let medium: CGFloat = 20
        static let standard: CGFloat = 28
        static let large: CGFloat = 36
        static let extraLarge: CGFloat = 44
    }

    // MARK: - Animation (Slow, Gentle)

    enum Animation {
        static let quick = SwiftUI.Animation.easeInOut(duration: 0.2)
        static let standard = SwiftUI.Animation.easeInOut(duration: 0.3)
        static let smooth = SwiftUI.Animation.easeInOut(duration: 0.4)
        static let gentle = SwiftUI.Animation.easeInOut(duration: 0.5)

        // Focus animations
        static let focusIn = SwiftUI.Animation.spring(response: 0.3, dampingFraction: 0.7)
        static let focusOut = SwiftUI.Animation.easeOut(duration: 0.2)

        // Ambient transitions
        static let ambient = SwiftUI.Animation.easeInOut(duration: 1.5)
        static let crossfade = SwiftUI.Animation.easeInOut(duration: 0.8)
    }

    // MARK: - Focus Scale

    enum FocusScale {
        static let card: CGFloat = 1.05
        static let button: CGFloat = 1.08
        static let small: CGFloat = 1.03
    }

    // MARK: - Blur

    enum Blur {
        static let glass: CGFloat = 30
        static let background: CGFloat = 50
        static let overlay: CGFloat = 20
    }
}

// MARK: - Glass Card Modifier

struct TVGlassBackground: ViewModifier {
    var isHighlighted: Bool = false

    func body(content: Content) -> some View {
        content
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
                                isHighlighted ? TVTheme.Colors.focusRing : TVTheme.Colors.glassBorder,
                                lineWidth: isHighlighted ? 3 : 1
                            )
                    )
            )
    }
}

// MARK: - Focus Effect Modifier

struct TVFocusEffect: ViewModifier {
    @Environment(\.isFocused) var isFocused
    var scale: CGFloat = TVTheme.FocusScale.card

    func body(content: Content) -> some View {
        content
            .scaleEffect(isFocused ? scale : 1.0)
            .shadow(
                color: isFocused ? TVTheme.Colors.focusGlow : .clear,
                radius: isFocused ? 20 : 0
            )
            .animation(isFocused ? TVTheme.Animation.focusIn : TVTheme.Animation.focusOut, value: isFocused)
    }
}

// MARK: - View Extensions

extension View {
    func tvGlassBackground(highlighted: Bool = false) -> some View {
        modifier(TVGlassBackground(isHighlighted: highlighted))
    }

    func tvFocusEffect(scale: CGFloat = TVTheme.FocusScale.card) -> some View {
        modifier(TVFocusEffect(scale: scale))
    }

    func tvCardStyle() -> some View {
        self
            .tvGlassBackground()
            .clipShape(RoundedRectangle(cornerRadius: TVTheme.CornerRadius.standard))
    }

    func tvSafeArea() -> some View {
        self.padding(.horizontal, TVTheme.Spacing.safeAreaHorizontal)
            .padding(.vertical, TVTheme.Spacing.safeAreaVertical)
    }
}

// Note: Color(hex:) extension is defined in the shared Theme.swift file
