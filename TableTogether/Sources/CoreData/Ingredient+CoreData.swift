import CoreData

/// The foundational unit representing a food ingredient with optional macro data.
@objc(Ingredient)
public class Ingredient: NSManagedObject {

    @NSManaged public var id: UUID
    @NSManaged public var name: String
    @NSManaged public var normalizedName: String
    @NSManaged public var categoryRaw: String
    @NSManaged public var defaultUnitRaw: String
    @NSManaged public var caloriesPer100g: NSNumber?
    @NSManaged public var proteinPer100g: NSNumber?
    @NSManaged public var carbsPer100g: NSNumber?
    @NSManaged public var fatPer100g: NSNumber?
    @NSManaged public var isUserCreated: Bool
    @NSManaged public var createdAt: Date
    @NSManaged public var modifiedAt: Date

    // MARK: - Relationships

    @NSManaged public var recipeIngredients: NSSet?
    @NSManaged public var groceryItems: NSSet?
    @NSManaged public var household: Household?

    // MARK: - Enum Wrappers

    var category: IngredientCategory {
        get { IngredientCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    var defaultUnit: MeasurementUnit {
        get { MeasurementUnit(rawValue: defaultUnitRaw) ?? .gram }
        set { defaultUnitRaw = newValue.rawValue }
    }

    // MARK: - Typed Accessors

    var recipeIngredientsArray: [RecipeIngredient] {
        (recipeIngredients?.allObjects as? [RecipeIngredient]) ?? []
    }

    var groceryItemsArray: [GroceryItem] {
        (groceryItems?.allObjects as? [GroceryItem]) ?? []
    }

    // MARK: - Computed Properties

    var hasMacroData: Bool {
        caloriesPer100g != nil && proteinPer100g != nil && carbsPer100g != nil && fatPer100g != nil
    }

    // MARK: - Methods

    func updateName(_ newName: String) {
        self.name = newName
        self.normalizedName = newName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        self.modifiedAt = Date()
    }

    // MARK: - Convenience Initializer

    @discardableResult
    convenience init(
        context: NSManagedObjectContext,
        id: UUID = UUID(),
        name: String,
        category: IngredientCategory = .other,
        defaultUnit: MeasurementUnit = .gram,
        caloriesPer100g: Double? = nil,
        proteinPer100g: Double? = nil,
        carbsPer100g: Double? = nil,
        fatPer100g: Double? = nil,
        isUserCreated: Bool = true
    ) {
        let entity = NSEntityDescription.entity(forEntityName: "Ingredient", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = id
        self.name = name
        self.normalizedName = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        self.categoryRaw = category.rawValue
        self.defaultUnitRaw = defaultUnit.rawValue
        self.caloriesPer100g = caloriesPer100g.map { NSNumber(value: $0) }
        self.proteinPer100g = proteinPer100g.map { NSNumber(value: $0) }
        self.carbsPer100g = carbsPer100g.map { NSNumber(value: $0) }
        self.fatPer100g = fatPer100g.map { NSNumber(value: $0) }
        self.isUserCreated = isUserCreated
        self.createdAt = Date()
        self.modifiedAt = Date()
    }
}
