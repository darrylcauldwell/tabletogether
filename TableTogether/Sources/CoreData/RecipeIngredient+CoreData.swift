import CoreData

/// Junction model linking Ingredient to Recipe with quantity and preparation details.
@objc(RecipeIngredient)
public class RecipeIngredient: NSManagedObject {

    @NSManaged public var id: UUID
    @NSManaged public var quantity: Double
    @NSManaged public var unitRaw: String
    @NSManaged public var preparationNote: String?
    @NSManaged public var isOptional: Bool
    @NSManaged public var order: Int32
    @NSManaged public var customName: String?

    // MARK: - Relationships

    @NSManaged public var ingredient: Ingredient?
    @NSManaged public var recipe: Recipe?

    // MARK: - Enum Wrapper

    var unit: MeasurementUnit {
        get { MeasurementUnit(rawValue: unitRaw) ?? .gram }
        set { unitRaw = newValue.rawValue }
    }

    // MARK: - Computed Properties

    var displayName: String {
        ingredient?.name ?? customName ?? "Unknown Ingredient"
    }

    var displayString: String {
        var result = "\(formattedQuantity) \(unit.abbreviation)"
        result += " \(displayName)"
        if let note = preparationNote, !note.isEmpty {
            result += ", \(note)"
        }
        if isOptional {
            result += " (optional)"
        }
        return result
    }

    var formattedQuantity: String {
        if quantity.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", quantity)
        } else {
            return String(format: "%.2f", quantity)
                .replacingOccurrences(of: "\\.?0+$", with: "", options: .regularExpression)
        }
    }

    func scaledQuantity(originalServings: Int, newServings: Int) -> Double {
        guard originalServings > 0 else { return quantity }
        return quantity * Double(newServings) / Double(originalServings)
    }

    func formattedScaledQuantity(for servings: Int, baseServings: Int) -> String {
        let scaled = scaledQuantity(originalServings: baseServings, newServings: servings)
        if scaled.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(scaled)) \(unit.abbreviation)"
        } else {
            return String(format: "%.1f", scaled) + " \(unit.abbreviation)"
        }
    }

    // MARK: - Macro Calculations

    var calculatedCalories: Double? {
        guard let grams = convertToGrams(),
              let cals = ingredient?.caloriesPer100g?.doubleValue else { return nil }
        return (cals * grams) / 100.0
    }

    var calculatedProtein: Double? {
        guard let grams = convertToGrams(),
              let prot = ingredient?.proteinPer100g?.doubleValue else { return nil }
        return (prot * grams) / 100.0
    }

    var calculatedCarbs: Double? {
        guard let grams = convertToGrams(),
              let carbs = ingredient?.carbsPer100g?.doubleValue else { return nil }
        return (carbs * grams) / 100.0
    }

    var calculatedFat: Double? {
        guard let grams = convertToGrams(),
              let fat = ingredient?.fatPer100g?.doubleValue else { return nil }
        return (fat * grams) / 100.0
    }

    private func convertToGrams() -> Double? {
        switch unit {
        case .gram: return quantity
        case .kilogram: return quantity * 1000
        case .milliliter: return quantity
        case .liter: return quantity * 1000
        case .cup: return quantity * 240
        case .tablespoon: return quantity * 15
        case .teaspoon: return quantity * 5
        case .piece, .slice, .clove, .bunch, .pinch, .toTaste: return nil
        }
    }

    // MARK: - Convenience Initializer

    @discardableResult
    convenience init(
        context: NSManagedObjectContext,
        id: UUID = UUID(),
        ingredient: Ingredient? = nil,
        quantity: Double,
        unit: MeasurementUnit,
        preparationNote: String? = nil,
        isOptional: Bool = false,
        order: Int = 0,
        customName: String? = nil
    ) {
        let entity = NSEntityDescription.entity(forEntityName: "RecipeIngredient", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = id
        self.ingredient = ingredient
        self.quantity = quantity
        self.unitRaw = unit.rawValue
        self.preparationNote = preparationNote
        self.isOptional = isOptional
        self.order = Int32(order)
        self.customName = customName
    }
}
