import SwiftUI

// Note: Color(hex:) initializer is defined in Theme.swift to avoid duplication

// MARK: - Cross-Platform System Colors

extension Color {
    /// Cross-platform equivalent of systemGray5
    static var systemGray5: Color {
        #if os(iOS)
        return Color(.systemGray5)
        #else
        return Color.gray.opacity(0.2)
        #endif
    }

    /// Cross-platform equivalent of systemGray6
    static var systemGray6: Color {
        #if os(iOS)
        return Color(.systemGray6)
        #else
        return Color.gray.opacity(0.15)
        #endif
    }

    /// Cross-platform equivalent of systemBackground
    static var systemBackground: Color {
        #if os(iOS)
        return Color(.systemBackground)
        #else
        return Color.black
        #endif
    }

    /// Cross-platform equivalent of secondarySystemBackground
    static var secondarySystemBackground: Color {
        #if os(iOS)
        return Color(.secondarySystemBackground)
        #else
        return Color.secondary.opacity(0.1)
        #endif
    }

    /// Cross-platform equivalent of systemGroupedBackground
    static var systemGroupedBackground: Color {
        #if os(iOS)
        return Color(.systemGroupedBackground)
        #else
        return Color.gray.opacity(0.1)
        #endif
    }

    /// Cross-platform equivalent of tertiarySystemBackground
    static var tertiarySystemBackground: Color {
        #if os(iOS)
        return Color(.tertiarySystemBackground)
        #else
        return Color.gray.opacity(0.08)
        #endif
    }

    /// Cross-platform equivalent of separator
    static var separator: Color {
        #if os(iOS)
        return Color(.separator)
        #else
        return Color.gray.opacity(0.3)
        #endif
    }
}

extension Color {
    /// Convert to hex string
    var hexString: String {
        #if canImport(UIKit)
        guard let components = UIColor(self).cgColor.components else {
            return "#000000"
        }
        let r = Int(components[0] * 255)
        let g = Int(components[1] * 255)
        let b = Int(components[2] * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
        #else
        // macOS fallback
        guard let components = NSColor(self).cgColor.components else {
            return "#000000"
        }
        let r = Int(components[0] * 255)
        let g = Int(components[1] * 255)
        let b = Int(components[2] * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
        #endif
    }
}

// MARK: - Semantic Colors for Macros

extension Color {
    /// Soft color for calories display (never alarming)
    static let caloriesSoft = Color(hex: "B8D4E3") // Soft blue

    /// Soft color for protein display
    static let proteinSoft = Color(hex: "C5E1A5") // Soft green

    /// Soft color for carbs display
    static let carbsSoft = Color(hex: "FFECB3") // Soft amber

    /// Soft color for fat display
    static let fatSoft = Color(hex: "F8BBD9") // Soft pink
}

// MARK: - Ingredient Category Colors

extension IngredientCategory {
    var color: Color {
        switch self {
        case .produce: return Color(hex: "8BC34A") // Green
        case .protein: return Color(hex: "FF7043") // Deep orange
        case .dairy: return Color(hex: "42A5F5") // Blue
        case .grain: return Color(hex: "FFCA28") // Amber
        case .pantry: return Color(hex: "8D6E63") // Brown
        case .frozen: return Color(hex: "4DD0E1") // Cyan
        case .condiment: return Color(hex: "AB47BC") // Purple
        case .beverage: return Color(hex: "26A69A") // Teal
        case .other: return Color(hex: "78909C") // Blue grey
        }
    }
}

// MARK: - Archetype Colors

extension ArchetypeType {
    var color: Color {
        switch self {
        case .quickWeeknight: return Color(hex: "4FC3F7") // Light blue
        case .comfort: return Color(hex: "FFB74D") // Orange
        case .leftovers: return Color(hex: "81C784") // Green
        case .newExperimental: return Color(hex: "BA68C8") // Purple
        case .bigBatch: return Color(hex: "4DB6AC") // Teal
        case .familyFavorite: return Color(hex: "F06292") // Pink
        case .lightFresh: return Color(hex: "AED581") // Light green
        case .slowCook: return Color(hex: "A1887F") // Brown
        }
    }
}
