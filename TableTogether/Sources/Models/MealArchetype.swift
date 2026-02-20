import Foundation
import SwiftData

// MARK: - MealArchetype Model

/// Defines the character of a meal slot, guiding recipe suggestions.
/// Can be system-defined or user-created.
@Model
final class MealArchetype {
    /// Primary identifier
    @Attribute(.unique) var id: UUID

    /// Display name for the archetype
    var name: String

    /// Optional system type for built-in archetypes
    var systemType: ArchetypeType?

    /// Description explaining purpose to user
    var archetypeDescription: String

    /// SF Symbol name for icon display
    var icon: String

    /// Hex color code for accent color (e.g., "#FFB347")
    var colorHex: String

    /// Whether this is a user-created custom archetype
    var isUserCreated: Bool

    // MARK: - Relationships

    /// Meal slots that use this archetype
    @Relationship(inverse: \MealSlot.archetype)
    var mealSlots: [MealSlot] = []

    /// Parent household for CloudKit sharing
    @Relationship
    var household: Household?

    // MARK: - Initialization

    /// Creates a custom user archetype
    init(
        id: UUID = UUID(),
        name: String,
        description: String,
        icon: String = "circle.fill",
        colorHex: String = "#8FBC8F"
    ) {
        self.id = id
        self.name = name
        self.systemType = nil
        self.archetypeDescription = description
        self.icon = icon
        self.colorHex = colorHex
        self.isUserCreated = true
    }

    /// Creates a system archetype from a predefined type
    init(systemType: ArchetypeType) {
        self.id = UUID()
        self.name = systemType.displayName
        self.systemType = systemType
        self.archetypeDescription = systemType.description
        self.icon = systemType.icon
        self.colorHex = systemType.colorHex
        self.isUserCreated = false
    }

    // MARK: - Factory Methods

    /// Creates all system-defined archetypes
    static func createSystemArchetypes() -> [MealArchetype] {
        ArchetypeType.allCases.map { MealArchetype(systemType: $0) }
    }
}
