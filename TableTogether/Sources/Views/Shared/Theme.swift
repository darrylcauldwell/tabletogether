import SwiftUI

// MARK: - Dynamic Type Scaled Spacing

/// Property wrapper that provides spacing values that scale with Dynamic Type settings.
/// Use this for spacing that should grow/shrink with the user's preferred text size.
///
/// Example usage:
/// ```swift
/// struct MyView: View {
///     @ScaledSpacing(.standard) private var padding
///     var body: some View {
///         Text("Hello").padding(padding)
///     }
/// }
/// ```
@propertyWrapper
struct ScaledSpacing: DynamicProperty {
    @ScaledMetric private var scaledValue: CGFloat

    var wrappedValue: CGFloat { scaledValue }

    init(_ spacing: Theme.Spacing.Value) {
        _scaledValue = ScaledMetric(wrappedValue: spacing.rawValue, relativeTo: .body)
    }

    init(wrappedValue: CGFloat, relativeTo textStyle: Font.TextStyle = .body) {
        _scaledValue = ScaledMetric(wrappedValue: wrappedValue, relativeTo: textStyle)
    }
}

/// Property wrapper for icon sizes that scale with Dynamic Type
@propertyWrapper
struct ScaledIconSize: DynamicProperty {
    @ScaledMetric private var scaledValue: CGFloat

    var wrappedValue: CGFloat { scaledValue }

    init(wrappedValue: CGFloat, relativeTo textStyle: Font.TextStyle = .body) {
        _scaledValue = ScaledMetric(wrappedValue: wrappedValue, relativeTo: textStyle)
    }
}

// MARK: - Appearance Mode

/// User-selectable appearance mode for the app
enum AppearanceMode: Int, CaseIterable, Identifiable {
    case system = 0
    case light = 1
    case dark = 2

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// Design tokens for TableTogether app
/// Provides consistent colors, typography, and spacing across the app
enum Theme {

    // MARK: - Colors

    enum Colors {
        /// Primary brand color - Sage Green
        /// Used for: Tab bar tint, primary buttons, accent elements
        static let primary = Color(hex: "8FBC8F")

        /// Secondary accent color - Warm Orange
        /// Used for: Highlights, call-to-action buttons, appetite-related elements
        static let secondary = Color(hex: "E8A87C")

        /// Background color - Adaptive
        /// Light: Off-White (FAF9F6), Dark: Pure black (000000)
        static let background = Color(light: Color(hex: "FAF9F6"), dark: Color(hex: "000000"))

        /// Primary text color - Adaptive
        /// Light: Charcoal (36454F), Dark: Off-white (F5F5F5)
        static let textPrimary = Color(light: Color(hex: "36454F"), dark: Color(hex: "F5F5F5"))

        /// Secondary text color - Adaptive
        /// Light: Slate Gray (708090), Dark: Muted gray (A0A0A5)
        static let textSecondary = Color(light: Color(hex: "708090"), dark: Color(hex: "A0A0A5"))

        /// Card/Surface background - Adaptive
        /// Light: Pure white, Dark: Elevated dark surface (3C3C3E)
        static let cardBackground = Color(light: .white, dark: Color(hex: "3C3C3E"))

        /// Positive accent - Soft Green
        /// Used for: Goals met, success states (never red for unmet goals)
        static let positive = Color(hex: "90EE90")

        /// Neutral accent - Soft Blue
        /// Used for: Informational badges, neutral highlights
        static let neutral = Color(hex: "B0C4DE")

        /// Archetype colors for visual differentiation
        enum Archetype {
            static let quickWeeknight = Color(hex: "FFD700")    // Gold
            static let comfort = Color(hex: "DEB887")           // Burlywood
            static let leftovers = Color(hex: "98D8C8")         // Mint
            static let experimental = Color(hex: "DDA0DD")      // Plum
            static let bigBatch = Color(hex: "F4A460")          // Sandy Brown
            static let familyFavorite = Color(hex: "FF6B6B")    // Coral
            static let lightFresh = Color(hex: "98FB98")        // Pale Green
            static let slowCook = Color(hex: "CD853F")          // Peru
        }
    }

    // MARK: - Typography

    enum Typography {
        /// Large title for main screens
        static let largeTitle = Font.largeTitle.weight(.semibold)

        /// Title for section headers
        static let title = Font.title.weight(.semibold)

        /// Title2 for card headers and subsections
        static let title2 = Font.title2.weight(.medium)

        /// Title3 for smaller headers
        static let title3 = Font.title3.weight(.medium)

        /// Headline for emphasized body text
        static let headline = Font.headline

        /// Body text - default reading text
        static let body = Font.body

        /// Callout for secondary information
        static let callout = Font.callout

        /// Subheadline for supporting text
        static let subheadline = Font.subheadline

        /// Footnote for less prominent text
        static let footnote = Font.footnote

        /// Caption for labels and metadata
        static let caption = Font.caption

        /// Caption2 for smallest text
        static let caption2 = Font.caption2
    }

    // MARK: - Spacing

    enum Spacing {
        /// Extra small spacing: 4pt
        static let xs: CGFloat = 4

        /// Small spacing: 8pt
        static let sm: CGFloat = 8

        /// Medium spacing: 12pt
        static let md: CGFloat = 12

        /// Standard spacing: 16pt
        static let standard: CGFloat = 16

        /// Large spacing: 24pt
        static let lg: CGFloat = 24

        /// Extra large spacing: 32pt
        static let xl: CGFloat = 32

        /// Double extra large spacing: 48pt
        static let xxl: CGFloat = 48

        /// Enum for use with @ScaledSpacing property wrapper
        enum Value: CGFloat {
            case xs = 4
            case sm = 8
            case md = 12
            case standard = 16
            case lg = 24
            case xl = 32
            case xxl = 48
        }
    }

    // MARK: - Corner Radius

    enum CornerRadius {
        /// Small radius for badges and chips: 4pt
        static let small: CGFloat = 4

        /// Medium radius for buttons: 8pt
        static let medium: CGFloat = 8

        /// Standard radius for cards: 12pt
        static let standard: CGFloat = 12

        /// Large radius for modal sheets: 16pt
        static let large: CGFloat = 16

        /// Extra large radius for full cards: 20pt
        static let extraLarge: CGFloat = 20
    }

    // MARK: - Shadows

    enum Shadow {
        /// Subtle shadow for cards
        static let card = ShadowStyle(
            color: Color.black.opacity(0.08),
            radius: 8,
            x: 0,
            y: 2
        )

        /// Elevated shadow for floating elements
        static let elevated = ShadowStyle(
            color: Color.black.opacity(0.12),
            radius: 16,
            x: 0,
            y: 4
        )
    }

    // MARK: - Animation

    enum Animation {
        /// Quick animation for micro-interactions
        static let quick = SwiftUI.Animation.easeInOut(duration: 0.15)

        /// Standard animation for most transitions
        static let standard = SwiftUI.Animation.easeInOut(duration: 0.25)

        /// Smooth animation for larger transitions
        static let smooth = SwiftUI.Animation.easeInOut(duration: 0.35)

        /// Spring animation for bouncy interactions
        static let spring = SwiftUI.Animation.spring(response: 0.4, dampingFraction: 0.7)
    }
}

// MARK: - Shadow Style Helper

struct ShadowStyle {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
}

// MARK: - Color Extension for Hex Support

extension Color {
    /// Initialize a Color with separate light and dark mode variants
    /// - Parameters:
    ///   - light: Color to use in light mode
    ///   - dark: Color to use in dark mode
    init(light: Color, dark: Color) {
        #if os(iOS) || os(tvOS)
        self.init(uiColor: UIColor { traitCollection in
            switch traitCollection.userInterfaceStyle {
            case .dark:
                return UIColor(dark)
            default:
                return UIColor(light)
            }
        })
        #elseif os(macOS)
        self.init(nsColor: NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return NSColor(dark)
            } else {
                return NSColor(light)
            }
        })
        #else
        self = light
        #endif
    }

    /// Initialize a Color from a hex string
    /// - Parameter hex: A hex string (with or without # prefix)
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)

        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - View Modifiers

extension View {
    /// Apply card shadow style
    func cardShadow() -> some View {
        self.shadow(
            color: Theme.Shadow.card.color,
            radius: Theme.Shadow.card.radius,
            x: Theme.Shadow.card.x,
            y: Theme.Shadow.card.y
        )
    }

    /// Apply elevated shadow style
    func elevatedShadow() -> some View {
        self.shadow(
            color: Theme.Shadow.elevated.color,
            radius: Theme.Shadow.elevated.radius,
            x: Theme.Shadow.elevated.x,
            y: Theme.Shadow.elevated.y
        )
    }

    /// Apply standard card styling
    func cardStyle() -> some View {
        self
            .background(Theme.Colors.background)
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.standard))
            .cardShadow()
    }
}

// MARK: - Accessibility Environment Values

/// Environment key for detecting if the user prefers reduced motion
private struct ReduceMotionKey: EnvironmentKey {
    static let defaultValue = false
}

/// Environment key for detecting accessibility text size categories
private struct IsAccessibilitySizeKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Whether the user has requested reduced motion
    var prefersReducedMotion: Bool {
        get { self[ReduceMotionKey.self] }
        set { self[ReduceMotionKey.self] = newValue }
    }

    /// Whether the current Dynamic Type size is an accessibility size (AX1-AX5)
    var isAccessibilitySize: Bool {
        get { self[IsAccessibilitySizeKey.self] }
        set { self[IsAccessibilitySizeKey.self] = newValue }
    }
}

// MARK: - Accessibility View Modifiers

extension View {
    /// Applies the appropriate animation based on the user's Reduce Motion preference.
    /// Uses the provided animation when motion is allowed, or no animation when reduced motion is preferred.
    func accessibilityAnimation<V: Equatable>(_ animation: Animation?, value: V) -> some View {
        modifier(AccessibilityAnimationModifier(animation: animation, value: value))
    }

    /// Adjusts layout for accessibility text sizes.
    /// When accessibility sizes are active, switches from horizontal to vertical layout.
    func accessibilityResponsiveStack<Content: View>(
        horizontalAlignment: HorizontalAlignment = .center,
        verticalAlignment: VerticalAlignment = .center,
        spacing: CGFloat? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        modifier(AccessibilityResponsiveStackModifier(
            horizontalAlignment: horizontalAlignment,
            verticalAlignment: verticalAlignment,
            spacing: spacing,
            content: content
        ))
    }

    /// Ensures minimum touch target size of 44x44 points for accessibility compliance.
    func accessibilityTouchTarget() -> some View {
        self.frame(minWidth: 44, minHeight: 44)
    }

    /// Groups related content and provides a combined accessibility label.
    /// Use this for cards or compound elements that should be read as a single unit.
    func accessibilityGroup(label: String, hint: String? = nil, traits: AccessibilityTraits = []) -> some View {
        self
            .accessibilityElement(children: .combine)
            .accessibilityLabel(label)
            .accessibilityHint(hint ?? "")
            .accessibilityAddTraits(traits)
    }

    /// Marks a view as a header for VoiceOver navigation.
    func accessibilityHeading() -> some View {
        self.accessibilityAddTraits(.isHeader)
    }

    /// Adds support for increment/decrement gestures on adjustable values.
    func accessibilityAdjustable(
        value: Binding<Int>,
        label: String,
        minValue: Int = 0,
        maxValue: Int = Int.max
    ) -> some View {
        modifier(AccessibilityAdjustableModifier(
            value: value,
            label: label,
            minValue: minValue,
            maxValue: maxValue
        ))
    }
}

// MARK: - Accessibility Modifier Implementations

private struct AccessibilityAnimationModifier<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation?
    let value: V

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}

private struct AccessibilityResponsiveStackModifier<StackContent: View>: ViewModifier {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let horizontalAlignment: HorizontalAlignment
    let verticalAlignment: VerticalAlignment
    let spacing: CGFloat?
    @ViewBuilder let content: () -> StackContent

    private var isAccessibilitySize: Bool {
        dynamicTypeSize.isAccessibilitySize
    }

    func body(content: Content) -> some View {
        if isAccessibilitySize {
            VStack(alignment: horizontalAlignment, spacing: spacing) {
                self.content()
            }
        } else {
            HStack(alignment: verticalAlignment, spacing: spacing) {
                self.content()
            }
        }
    }
}

private struct AccessibilityAdjustableModifier: ViewModifier {
    @Binding var value: Int
    let label: String
    let minValue: Int
    let maxValue: Int

    func body(content: Content) -> some View {
        content
            .accessibilityElement(children: .combine)
            .accessibilityLabel(label)
            .accessibilityValue("\(value)")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment:
                    if value < maxValue { value += 1 }
                case .decrement:
                    if value > minValue { value -= 1 }
                @unknown default:
                    break
                }
            }
    }
}

// MARK: - Dynamic Type Helpers

extension View {
    /// Ensures text remains readable at all Dynamic Type sizes by applying a minimum scale factor.
    /// Use for text that might be truncated at larger accessibility sizes.
    func dynamicTypeScalable(minimumScaleFactor: CGFloat = 0.7) -> some View {
        self.minimumScaleFactor(minimumScaleFactor)
    }

    /// Limits the Dynamic Type size for specific UI elements that cannot grow indefinitely.
    /// Use sparingly and only when layout constraints make it necessary.
    @available(iOS 17.0, tvOS 17.0, *)
    func limitDynamicTypeSize(to limit: DynamicTypeSize = .accessibility3) -> some View {
        self.dynamicTypeSize(...limit)
    }
}

// MARK: - Preview

#Preview("Color Palette") {
    VStack(spacing: Theme.Spacing.md) {
        HStack(spacing: Theme.Spacing.md) {
            ColorSwatch(name: "Primary", color: Theme.Colors.primary)
            ColorSwatch(name: "Secondary", color: Theme.Colors.secondary)
        }
        HStack(spacing: Theme.Spacing.md) {
            ColorSwatch(name: "Background", color: Theme.Colors.background)
            ColorSwatch(name: "Text Primary", color: Theme.Colors.textPrimary)
        }
        HStack(spacing: Theme.Spacing.md) {
            ColorSwatch(name: "Text Secondary", color: Theme.Colors.textSecondary)
            ColorSwatch(name: "Positive", color: Theme.Colors.positive)
        }
        HStack(spacing: Theme.Spacing.md) {
            ColorSwatch(name: "Neutral", color: Theme.Colors.neutral)
        }
    }
    .padding()
}

#Preview("Typography") {
    VStack(alignment: .leading, spacing: Theme.Spacing.md) {
        Text("Large Title").font(Theme.Typography.largeTitle)
        Text("Title").font(Theme.Typography.title)
        Text("Title 2").font(Theme.Typography.title2)
        Text("Title 3").font(Theme.Typography.title3)
        Text("Headline").font(Theme.Typography.headline)
        Text("Body").font(Theme.Typography.body)
        Text("Callout").font(Theme.Typography.callout)
        Text("Subheadline").font(Theme.Typography.subheadline)
        Text("Footnote").font(Theme.Typography.footnote)
        Text("Caption").font(Theme.Typography.caption)
        Text("Caption 2").font(Theme.Typography.caption2)
    }
    .padding()
    .foregroundStyle(Theme.Colors.textPrimary)
}

// Helper view for color preview
private struct ColorSwatch: View {
    let name: String
    let color: Color

    var body: some View {
        VStack {
            RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                .fill(color)
                .frame(width: 80, height: 80)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                        .strokeBorder(Color.gray.opacity(0.3), lineWidth: 1)
                )
            Text(name)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }
}
