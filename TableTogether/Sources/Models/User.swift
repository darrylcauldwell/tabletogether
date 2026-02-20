import Foundation
import SwiftData

/// Household member identity - shared with all household members.
/// All household members have equal permissions - no roles or hierarchy.
///
/// Note: Personal data (macro goals, meal logs, insights preferences) is stored
/// separately in CloudKit private database via PrivateDataManager. This model
/// only contains shared identity information visible to all household members.
@Model
final class User {
    /// Primary identifier
    @Attribute(.unique) var id: UUID

    /// Name shown in app
    var displayName: String

    /// Simple emoji avatar for quick identification
    var avatarEmoji: String

    /// Background color hex for avatar display
    var avatarColorHex: String

    /// iCloud identity link for sync
    var cloudKitRecordID: String?

    /// Creation timestamp
    var createdAt: Date

    // MARK: - Relationships

    /// Meal slots assigned to this user (cooking responsibility, not consumption)
    @Relationship(inverse: \MealSlot.assignedTo)
    var assignedMealSlots: [MealSlot] = []

    /// Meal slots last modified by this user
    @Relationship(inverse: \MealSlot.modifiedBy)
    var modifiedMealSlots: [MealSlot] = []

    /// Recipes created by this user
    @Relationship(inverse: \Recipe.createdBy)
    var createdRecipes: [Recipe] = []

    /// Grocery items checked off by this user
    @Relationship(inverse: \GroceryItem.checkedBy)
    var checkedGroceryItems: [GroceryItem] = []

    /// Parent household for CloudKit sharing
    @Relationship
    var household: Household?

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        displayName: String,
        avatarEmoji: String = "😊",
        avatarColorHex: String = "#8FBC8F",
        cloudKitRecordID: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.avatarEmoji = avatarEmoji
        self.avatarColorHex = avatarColorHex
        self.cloudKitRecordID = cloudKitRecordID
        self.createdAt = Date()
    }

    // MARK: - Computed Properties

    /// User's initials from display name
    var initials: String {
        let components = displayName.split(separator: " ")
        if components.count >= 2 {
            let first = components[0].prefix(1)
            let last = components[1].prefix(1)
            return "\(first)\(last)".uppercased()
        } else if let first = components.first {
            return String(first.prefix(2)).uppercased()
        }
        return "??"
    }
}
