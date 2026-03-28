import Foundation

/// A standard portion size with a name and gram weight.
struct CommonPortion: Codable, Hashable, Sendable {
    /// Display name for the portion (e.g., "1 cup", "1 medium")
    let name: String

    /// Weight in grams for this portion
    let gramWeight: Double
}
