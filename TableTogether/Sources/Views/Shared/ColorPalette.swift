import SwiftUI

// Shared colour vocabulary. These were previously declared inside screen files
// (InsightsView, MacroDistributionRing) but are consumed across several views, so they
// live here next to Theme. All semantic aliases resolve to Theme.Colors so there is a
// single underlying palette.

extension Color {
    // MARK: - Insights semantic aliases (adapt to light/dark via Theme.Colors)

    /// Primary accent — Sage Green (same in both modes)
    static let sageGreen = Theme.Colors.primary
    /// Secondary accent — Warm Orange (same in both modes)
    static let warmOrange = Theme.Colors.secondary
    /// Card/surface background — adapts to mode
    static let offWhite = Theme.Colors.cardBackground
    /// Primary text — adapts to mode
    static let charcoal = Theme.Colors.textPrimary
    /// Secondary text — adapts to mode
    static let slateGray = Theme.Colors.textSecondary
    /// Positive accent (same in both modes)
    static let softGreen = Theme.Colors.positive
    /// Neutral accent (same in both modes)
    static let softBlue = Theme.Colors.neutral

    // MARK: - Macro ring colours

    /// Soft sage-tinted green for protein
    static let macroProtein = Color(red: 0.55, green: 0.75, blue: 0.65)
    /// Soft warm tone for carbs
    static let macroCarbs = Color(red: 0.85, green: 0.75, blue: 0.55)
    /// Soft cool tone for fat
    static let macroFat = Color(red: 0.65, green: 0.75, blue: 0.85)
}
