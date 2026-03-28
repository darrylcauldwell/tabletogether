import CoreData

/// Defines the character of a meal slot, guiding recipe suggestions.
/// Can be system-defined or user-created.
@objc(MealArchetype)
public class MealArchetype: NSManagedObject {

    @NSManaged public var id: UUID
    @NSManaged public var name: String
    @NSManaged public var systemTypeRaw: String?
    @NSManaged public var archetypeDescription: String
    @NSManaged public var icon: String
    @NSManaged public var colorHex: String
    @NSManaged public var isUserCreated: Bool

    // MARK: - Relationships

    @NSManaged public var mealSlots: NSSet?
    @NSManaged public var household: Household?

    // MARK: - Enum Wrapper

    var systemType: ArchetypeType? {
        get { systemTypeRaw.flatMap { ArchetypeType(rawValue: $0) } }
        set { systemTypeRaw = newValue?.rawValue }
    }

    // MARK: - Typed Accessors

    var mealSlotsArray: [MealSlot] {
        (mealSlots?.allObjects as? [MealSlot]) ?? []
    }

    // MARK: - Factory Methods

    /// Creates all system-defined archetypes.
    static func createSystemArchetypes(context: NSManagedObjectContext) -> [MealArchetype] {
        ArchetypeType.allCases.map { type in
            MealArchetype(context: context, systemType: type)
        }
    }

    // MARK: - Convenience Initializers

    /// Creates a custom user archetype.
    @discardableResult
    convenience init(
        context: NSManagedObjectContext,
        id: UUID = UUID(),
        name: String,
        description: String,
        icon: String = "circle.fill",
        colorHex: String = "#8FBC8F"
    ) {
        let entity = NSEntityDescription.entity(forEntityName: "MealArchetype", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = id
        self.name = name
        self.systemTypeRaw = nil
        self.archetypeDescription = description
        self.icon = icon
        self.colorHex = colorHex
        self.isUserCreated = true
    }

    /// Creates a system archetype from a predefined type.
    @discardableResult
    convenience init(context: NSManagedObjectContext, systemType: ArchetypeType) {
        let entity = NSEntityDescription.entity(forEntityName: "MealArchetype", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        self.name = systemType.displayName
        self.systemTypeRaw = systemType.rawValue
        self.archetypeDescription = systemType.description
        self.icon = systemType.icon
        self.colorHex = systemType.colorHex
        self.isUserCreated = false
    }
}
