import CoreData

/// The shared root entity for a household.
/// All collaborative data belongs to a Household.
/// When shared via CloudKit, all related records sync to all participants.
/// There are no roles or hierarchy — all household members are equal.
@objc(Household)
public class Household: NSManagedObject {

    @NSManaged public var id: UUID
    @NSManaged public var name: String
    @NSManaged public var createdAt: Date

    // MARK: - Relationships (NSSet)

    @NSManaged public var recipes: NSSet?
    @NSManaged public var ingredients: NSSet?
    @NSManaged public var weekPlans: NSSet?
    @NSManaged public var users: NSSet?
    @NSManaged public var archetypes: NSSet?
    @NSManaged public var memories: NSSet?
    @NSManaged public var foodItems: NSSet?

    // MARK: - Typed Accessors

    var recipesArray: [Recipe] {
        (recipes?.allObjects as? [Recipe])?.sorted { $0.title < $1.title } ?? []
    }

    var ingredientsArray: [Ingredient] {
        (ingredients?.allObjects as? [Ingredient])?.sorted { $0.name < $1.name } ?? []
    }

    var weekPlansArray: [WeekPlan] {
        (weekPlans?.allObjects as? [WeekPlan])?.sorted { $0.weekStartDate > $1.weekStartDate } ?? []
    }

    var usersArray: [User] {
        (users?.allObjects as? [User])?.sorted { $0.displayName < $1.displayName } ?? []
    }

    var archetypesArray: [MealArchetype] {
        (archetypes?.allObjects as? [MealArchetype])?.sorted { $0.name < $1.name } ?? []
    }

    var memoriesArray: [SuggestionMemory] {
        (memories?.allObjects as? [SuggestionMemory]) ?? []
    }

    var foodItemsArray: [FoodItem] {
        (foodItems?.allObjects as? [FoodItem])?.sorted { $0.displayName < $1.displayName } ?? []
    }

    // MARK: - Convenience Initializer

    @discardableResult
    convenience init(context: NSManagedObjectContext, name: String = "My Household") {
        let entity = NSEntityDescription.entity(forEntityName: "Household", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
    }
}
