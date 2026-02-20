import Foundation
import SwiftData

// MARK: - SuggestionMemory Model

/// Intelligence layer storage for recipe suggestions.
/// Tracks cooking history and user preferences to improve recommendations.
@Model
final class SuggestionMemory {
    /// Primary identifier
    @Attribute(.unique) var id: UUID

    /// Historical count of times this recipe has been cooked
    var timesCooked: Int

    /// Date when recipe was last cooked
    var lastCookedDate: Date?

    /// Average user rating (if ratings are implemented)
    var averageRating: Double?

    /// Household familiarity level with this recipe
    var householdFamiliarity: FamiliarityLevel

    /// Date when this recipe was last suggested
    var lastSuggestedDate: Date?

    /// Number of times user declined this suggestion
    var suggestionDeclined: Int

    // MARK: - Relationships

    /// The recipe this memory is tracking
    @Relationship
    var recipe: Recipe?

    /// Parent household for CloudKit sharing
    @Relationship
    var household: Household?

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        recipe: Recipe? = nil,
        timesCooked: Int = 0,
        lastCookedDate: Date? = nil,
        averageRating: Double? = nil,
        lastSuggestedDate: Date? = nil,
        suggestionDeclined: Int = 0
    ) {
        self.id = id
        self.recipe = recipe
        self.timesCooked = timesCooked
        self.lastCookedDate = lastCookedDate
        self.averageRating = averageRating
        self.householdFamiliarity = FamiliarityLevel.from(timesCooked: timesCooked)
        self.lastSuggestedDate = lastSuggestedDate
        self.suggestionDeclined = suggestionDeclined
    }

    // MARK: - Methods

    /// Records that this recipe was cooked
    func recordCooking() {
        timesCooked += 1
        lastCookedDate = Date()
        householdFamiliarity = FamiliarityLevel.from(timesCooked: timesCooked)
    }

    /// Records that this recipe was suggested
    func recordSuggestion() {
        lastSuggestedDate = Date()
    }

    /// Records that the user declined this suggestion
    func recordDecline() {
        suggestionDeclined += 1
    }

    /// Resets decline count (e.g., after significant time has passed)
    func resetDeclines() {
        suggestionDeclined = 0
    }

    /// Updates the average rating
    func updateRating(_ newRating: Double) {
        if let existingRating = averageRating {
            // Simple running average (could be improved with count tracking)
            averageRating = (existingRating + newRating) / 2.0
        } else {
            averageRating = newRating
        }
    }

    // MARK: - Computed Properties

    /// Number of days since last cooked
    var daysSinceLastCooked: Int? {
        guard let lastCooked = lastCookedDate else { return nil }
        return Calendar.current.dateComponents([.day], from: lastCooked, to: Date()).day
    }

    /// Number of days since last suggested
    var daysSinceLastSuggested: Int? {
        guard let lastSuggested = lastSuggestedDate else { return nil }
        return Calendar.current.dateComponents([.day], from: lastSuggested, to: Date()).day
    }

    /// Whether this recipe has been recently cooked (within last 7 days)
    var wasRecentlyCooked: Bool {
        guard let days = daysSinceLastCooked else { return false }
        return days < 7
    }

    /// Whether this recipe has been frequently declined
    var isFrequentlyDeclined: Bool {
        suggestionDeclined > 2
    }

    /// Suggestion score based on familiarity, recency, and declines
    /// Higher score = more likely to suggest
    var suggestionScore: Double {
        var score: Double = 0

        // Familiarity bonus (prefer familiar recipes)
        switch householdFamiliarity {
        case .staple: score += 25
        case .familiar: score += 20
        case .tried: score += 10
        case .new: score += 0
        }

        // Recency penalty (avoid recent repeats)
        if let days = daysSinceLastCooked {
            if days < 7 {
                score -= 20
            } else if days < 14 {
                score -= 10
            }
        }

        // Decline penalty
        score -= Double(suggestionDeclined) * 5

        // Rating bonus
        if let rating = averageRating, rating >= 4.0 {
            score += 10
        }

        return score
    }
}
