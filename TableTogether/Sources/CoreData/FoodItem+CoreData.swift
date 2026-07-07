import CoreData

/// A cached food item with USDA nutritional data.
/// Shared via Household — nutrition facts are objective data, not personal.
@objc(FoodItem)
public class FoodItem: NSManagedObject {

    @NSManaged public var id: UUID
    @NSManaged public var fdcId: Int32
    @NSManaged public var usdaDescription: String
    @NSManaged public var displayName: String
    @NSManaged public var normalizedName: String
    @NSManaged public var dataType: String
    @NSManaged public var brandOwner: String?

    // Nutrition per 100g
    @NSManaged public var caloriesPer100g: Double
    @NSManaged public var proteinPer100g: Double
    @NSManaged public var carbsPer100g: Double
    @NSManaged public var fatPer100g: Double
    @NSManaged public var fiberPer100g: NSNumber?
    @NSManaged public var sugarPer100g: NSNumber?
    @NSManaged public var sodiumMgPer100g: NSNumber?

    @NSManaged public var commonPortionsData: Data?
    @NSManaged public var userAliases: [String]?
    @NSManaged public var createdAt: Date

    // MARK: - Relationships

    @NSManaged public var household: Household?
    @NSManaged public var mealSlotComponents: NSSet?

    // MARK: - Computed Properties

    var userAliasesList: [String] {
        get { userAliases ?? [] }
        set { userAliases = newValue }
    }

    var commonPortions: [CommonPortion] {
        guard let data = commonPortionsData else { return [] }
        return (try? JSONDecoder().decode([CommonPortion].self, from: data)) ?? []
    }

    var macrosPer100g: MacroSummary {
        MacroSummary(calories: caloriesPer100g, protein: proteinPer100g, carbs: carbsPer100g, fat: fatPer100g)
    }

    func macros(forGrams grams: Double) -> MacroSummary {
        macrosPer100g.scaled(by: grams / 100.0)
    }

    func addAlias(_ alias: String) {
        let normalized = alias.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        var aliases = userAliasesList
        guard !aliases.contains(normalized) else { return }
        aliases.append(normalized)
        userAliases = aliases
    }

    var dataTypePriority: Int {
        switch dataType {
        case "Foundation": return 3
        case "SR Legacy": return 2
        case "Survey (FNDDS)": return 1
        default: return 0
        }
    }

    // MARK: - Convenience Initializer

    @discardableResult
    convenience init(
        context: NSManagedObjectContext,
        fdcId: Int,
        usdaDescription: String,
        displayName: String,
        dataType: String,
        brandOwner: String? = nil,
        caloriesPer100g: Double,
        proteinPer100g: Double,
        carbsPer100g: Double,
        fatPer100g: Double,
        fiberPer100g: Double? = nil,
        sugarPer100g: Double? = nil,
        sodiumMgPer100g: Double? = nil,
        commonPortions: [CommonPortion] = [],
        userAliases: [String] = []
    ) {
        let entity = NSEntityDescription.entity(forEntityName: "FoodItem", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = UUID()
        // Non-trapping: values that don't fit Int32 (e.g. a barcode passed
        // through as an fdcId) become the 0 sentinel instead of crashing.
        self.fdcId = Int32(exactly: fdcId) ?? 0
        self.usdaDescription = usdaDescription
        self.displayName = displayName
        self.normalizedName = displayName.lowercased()
        self.dataType = dataType
        self.brandOwner = brandOwner
        self.caloriesPer100g = caloriesPer100g
        self.proteinPer100g = proteinPer100g
        self.carbsPer100g = carbsPer100g
        self.fatPer100g = fatPer100g
        self.fiberPer100g = fiberPer100g.map { NSNumber(value: $0) }
        self.sugarPer100g = sugarPer100g.map { NSNumber(value: $0) }
        self.sodiumMgPer100g = sodiumMgPer100g.map { NSNumber(value: $0) }
        self.userAliases = userAliases
        self.createdAt = Date()
        if !commonPortions.isEmpty {
            self.commonPortionsData = try? JSONEncoder().encode(commonPortions)
        }
    }
}
