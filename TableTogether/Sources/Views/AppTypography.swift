import SwiftUI

/// The single source of truth for typography across the app.
///
/// Views reference these tokens instead of inline `.font(...)` literals so font choices
/// can change in one place. Tokens map 1:1 onto SwiftUI's dynamic-type styles so text still
/// scales with the system text-size setting.
///
/// Two families exist for the large styles:
/// - plain tokens (`title2`) match a bare `.font(.title2)`
/// - `*Emphasized` tokens carry the weight used by the design system's headers
///
/// `Theme.Typography` forwards to these tokens, so there is one definition.
enum AppTypography {

    // MARK: - Dynamic type tokens (plain)

    static let largeTitle = Font.largeTitle
    static let title = Font.title
    static let title2 = Font.title2
    static let title3 = Font.title3
    static let headline = Font.headline
    static let body = Font.body
    static let callout = Font.callout
    static let subheadline = Font.subheadline
    static let footnote = Font.footnote
    static let caption = Font.caption
    static let caption2 = Font.caption2

    // MARK: - Emphasized header tokens (weighted)

    static let largeTitleEmphasized = Font.largeTitle.weight(.semibold)
    static let titleEmphasized = Font.title.weight(.semibold)
    static let title2Emphasized = Font.title2.weight(.medium)
    static let title3Emphasized = Font.title3.weight(.medium)

    // MARK: - Semantic tokens

    /// Card / row headers.
    static let cardTitle = headline
    /// Default reading text inside a card.
    static let cardBody = body
    /// Supporting metadata under a card title.
    static let cardMeta = caption
    /// Small pill / badge text.
    static let badge = caption2
    /// Labels on controls and form rows.
    static let controlLabel = subheadline
    /// Transient toast / confirmation text.
    static let toast = subheadline

    // MARK: - Fixed sizes (decorative / canvas)

    /// Fixed-size font for decorative or canvas-drawn text that can't use dynamic type
    /// (e.g. large emoji glyphs, gauge numerals). Centralised here so no view reaches for a
    /// raw `Font.system(size:)`. These scale with their container, not the text-size setting.
    static func fixed(_ size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        .system(size: size, weight: weight, design: design)
    }
}
