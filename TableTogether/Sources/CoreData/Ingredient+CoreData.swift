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

    /// Alternate names that should resolve to this ingredient when matched.
    /// Stored normalised (lowercase + trimmed). Used by RecipeIngredientResolver
    /// so the user can teach the resolver via the Ingredient Library UI:
    /// e.g. add "scallions" and "green onions" as aliases on a "spring onion"
    /// canonical record so future imports auto-link.
    @NSManaged public var userAliases: [String]?

    // MARK: - Relationships

    @NSManaged public var recipeIngredients: NSSet?
    @NSManaged public var groceryItems: NSSet?
    @NSManaged public var household: Household?
    @NSManaged public var mealSlotComponents: NSSet?

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

    /// Read-only view of `userAliases` that returns an empty list rather than nil.
    /// All stored aliases are already normalised (lowercase + trimmed) so this is
    /// a direct passthrough — callers who need to compare against an arbitrary
    /// input string should normalise their input first.
    var userAliasesList: [String] {
        get { userAliases ?? [] }
        set { userAliases = newValue }
    }

    // MARK: - Methods

    func updateName(_ newName: String) {
        self.name = newName
        self.normalizedName = newName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        self.modifiedAt = Date()
    }

    /// Adds a normalised alias if it isn't already present. No-op for empty
    /// strings, the canonical name itself, or duplicates already in the list.
    func addAlias(_ alias: String) {
        let normalized = alias.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, normalized != normalizedName else { return }
        var aliases = userAliasesList
        guard !aliases.contains(normalized) else { return }
        aliases.append(normalized)
        userAliases = aliases
        modifiedAt = Date()
    }

    /// Removes an alias if present. Matches case-insensitively after trimming.
    func removeAlias(_ alias: String) {
        let normalized = alias.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        var aliases = userAliasesList
        let before = aliases.count
        aliases.removeAll { $0 == normalized }
        guard aliases.count != before else { return }
        userAliases = aliases
        modifiedAt = Date()
    }

    /// Returns true if the given normalised string matches the canonical name
    /// or any alias. Caller must pre-normalise the query (lowercase + trim);
    /// stored aliases are already normalised.
    func matches(normalized query: String) -> Bool {
        if normalizedName == query { return true }
        return userAliasesList.contains(query)
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
