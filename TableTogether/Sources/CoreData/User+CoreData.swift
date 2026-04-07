import CoreData

/// Household member identity — shared with all household members.
/// All household members have equal permissions — no roles or hierarchy.
/// Personal data (macro goals, meal logs) is stored separately in CloudKit private database.
@objc(User)
public class User: NSManagedObject {

    @NSManaged public var id: UUID
    @NSManaged public var displayName: String
    @NSManaged public var avatarEmoji: String
    @NSManaged public var avatarColorHex: String
    @NSManaged public var cloudKitRecordID: String?
    @NSManaged public var createdAt: Date

    // MARK: - Relationships (NSSet)

    @NSManaged public var assignedMealSlots: NSSet?
    @NSManaged public var modifiedMealSlots: NSSet?
    @NSManaged public var createdRecipes: NSSet?
    @NSManaged public var checkedGroceryItems: NSSet?
    @NSManaged public var household: Household?

    // MARK: - Typed Accessors

    var assignedMealSlotsArray: [MealSlot] {
        (assignedMealSlots?.allObjects as? [MealSlot]) ?? []
    }

    var modifiedMealSlotsArray: [MealSlot] {
        (modifiedMealSlots?.allObjects as? [MealSlot]) ?? []
    }

    var createdRecipesArray: [Recipe] {
        (createdRecipes?.allObjects as? [Recipe])?.sorted { $0.title < $1.title } ?? []
    }

    var checkedGroceryItemsArray: [GroceryItem] {
        (checkedGroceryItems?.allObjects as? [GroceryItem]) ?? []
    }

    // MARK: - Computed Properties

    /// User's initials from display name.
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

    /// Deterministic UUID for the default "Me" user. Each device's owner creates this
    /// before CloudKit sync completes; using the same ID across devices prevents
    /// duplicate user records.
    static let defaultMeID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

    // MARK: - Convenience Initializer

    @discardableResult
    convenience init(
        context: NSManagedObjectContext,
        id: UUID = UUID(),
        displayName: String,
        avatarEmoji: String = "😊",
        avatarColorHex: String = "#8FBC8F",
        cloudKitRecordID: String? = nil
    ) {
        let entity = NSEntityDescription.entity(forEntityName: "User", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = id
        self.displayName = displayName
        self.avatarEmoji = avatarEmoji
        self.avatarColorHex = avatarColorHex
        self.cloudKitRecordID = cloudKitRecordID
        self.createdAt = Date()
    }
}
