import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// Note: cardStyle() is defined in Theme.swift
// Note: accessibilityTouchTarget() and other accessibility modifiers are defined in Theme.swift

extension View {
    /// Apply a subtle card background without shadow
    func softCardStyle() -> some View {
        self
            .padding()
            #if os(iOS)
            .background(Color(.secondarySystemBackground))
            #else
            .background(Color.secondary.opacity(0.1))
            #endif
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    /// Conditional modifier
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }

    /// Apply archetype accent color
    func archetypeAccent(_ archetype: ArchetypeType?) -> some View {
        self.tint(archetype?.color ?? Theme.Colors.primary)
    }

    #if canImport(UIKit)
    /// Hide keyboard (iOS only)
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
    #endif

    /// Apply calm, non-alarming styling for numbers
    func calmNumberStyle() -> some View {
        self
            .foregroundStyle(Theme.Colors.textPrimary)
            .fontWeight(.medium)
    }
}

// MARK: - Empty State Modifier

struct EmptyStateModifier: ViewModifier {
    let isEmpty: Bool
    let title: String
    let message: String
    let systemImage: String

    func body(content: Content) -> some View {
        if isEmpty {
            ContentUnavailableView {
                Label(title, systemImage: systemImage)
            } description: {
                Text(message)
            }
        } else {
            content
        }
    }
}

extension View {
    func emptyState(
        isEmpty: Bool,
        title: String,
        message: String,
        systemImage: String
    ) -> some View {
        modifier(EmptyStateModifier(
            isEmpty: isEmpty,
            title: title,
            message: message,
            systemImage: systemImage
        ))
    }
}

// MARK: - Drag & Drop Helpers

#if os(iOS)
extension View {
    /// Make view draggable as a recipe (iOS only - drag and drop not available on tvOS)
    func draggableRecipe(_ recipe: Recipe) -> some View {
        self.draggable(recipe.id.uuidString) {
            RecipeCardView(recipe: recipe)
                .frame(width: 150, height: 100)
                .opacity(0.9)
        }
    }
}
#else
extension View {
    /// Stub for non-iOS platforms where drag and drop is not available
    func draggableRecipe(_ recipe: Recipe) -> some View {
        self
    }
}
#endif

// MARK: - Accessibility Convenience Extensions

extension View {
    /// Applies a background that respects the Reduce Transparency accessibility setting.
    /// When Reduce Transparency is enabled, uses a solid color instead of translucent material.
    func accessibilityAwareBackground<S: ShapeStyle>(
        material: Material = .regular,
        solidFallback: S
    ) -> some View {
        modifier(AccessibilityAwareBackgroundModifier(material: material, solidFallback: solidFallback))
    }

    /// Hides decorative content from VoiceOver.
    /// Use for icons, images, or other visual elements that don't add information.
    func accessibilityDecorative() -> some View {
        self.accessibilityHidden(true)
    }

    /// Marks content as a button for VoiceOver.
    func accessibilityButton(label: String, hint: String? = nil) -> some View {
        self
            .accessibilityLabel(label)
            .accessibilityHint(hint ?? "")
            .accessibilityAddTraits(.isButton)
    }

    /// Marks content as an image for VoiceOver with a description.
    func accessibilityImage(description: String) -> some View {
        self
            .accessibilityLabel(description)
            .accessibilityAddTraits(.isImage)
    }

    /// Creates an accessibility element that represents a summary of child content.
    /// Useful for complex layouts where VoiceOver should read a simplified version.
    func accessibilitySummary(_ summary: String, hint: String? = nil) -> some View {
        self
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(summary)
            .accessibilityHint(hint ?? "")
    }
}

// MARK: - Accessibility Background Modifier

private struct AccessibilityAwareBackgroundModifier<S: ShapeStyle>: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let material: Material
    let solidFallback: S

    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(solidFallback)
        } else {
            content.background(material)
        }
    }
}

// MARK: - Dynamic Type Size Extensions

extension View {
    /// Adjusts layout based on whether the current Dynamic Type size is an accessibility size.
    /// Use this to provide alternative layouts that work better at large text sizes.
    func accessibilitySizeAware<Standard: View, Accessible: View>(
        @ViewBuilder standard: @escaping () -> Standard,
        @ViewBuilder accessible: @escaping () -> Accessible
    ) -> some View {
        AccessibilitySizeAwareView(standard: standard, accessible: accessible)
    }
}

private struct AccessibilitySizeAwareView<Standard: View, Accessible: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let standard: () -> Standard
    let accessible: () -> Accessible

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            accessible()
        } else {
            standard()
        }
    }
}

// MARK: - Bold Text Support

extension View {
    /// Applies bold weight when the user has Bold Text enabled in accessibility settings.
    /// Useful for text that should emphasize more strongly when Bold Text is on.
    func accessibilityBoldText() -> some View {
        modifier(AccessibilityBoldTextModifier())
    }
}

private struct AccessibilityBoldTextModifier: ViewModifier {
    @Environment(\.legibilityWeight) private var legibilityWeight

    func body(content: Content) -> some View {
        if legibilityWeight == .bold {
            content.fontWeight(.semibold)
        } else {
            content
        }
    }
}
