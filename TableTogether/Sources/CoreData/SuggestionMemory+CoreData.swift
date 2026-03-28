import CoreData

/// Intelligence layer storage for recipe suggestions.
/// Tracks cooking history and user preferences to improve recommendations.
@objc(SuggestionMemory)
public class SuggestionMemory: NSManagedObject {

    @NSManaged public var id: UUID
    @NSManaged public var timesCooked: Int32
    @NSManaged public var lastCookedDate: Date?
    @NSManaged public var averageRating: NSNumber?
    @NSManaged public var familiarityRaw: String
    @NSManaged public var lastSuggestedDate: Date?
    @NSManaged public var suggestionDeclined: Int32

    // MARK: - Relationships

    @NSManaged public var recipe: Recipe?
    @NSManaged public var household: Household?

    // MARK: - Enum Wrapper

    var householdFamiliarity: FamiliarityLevel {
        get { FamiliarityLevel(rawValue: familiarityRaw) ?? .new }
        set { familiarityRaw = newValue.rawValue }
    }

    // MARK: - Methods

    func recordCooking() {
        timesCooked += 1
        lastCookedDate = Date()
        householdFamiliarity = FamiliarityLevel.from(timesCooked: Int(timesCooked))
    }

    func recordSuggestion() {
        lastSuggestedDate = Date()
    }

    func recordDecline() {
        suggestionDeclined += 1
    }

    func resetDeclines() {
        suggestionDeclined = 0
    }

    func updateRating(_ newRating: Double) {
        if let existing = averageRating?.doubleValue {
            averageRating = NSNumber(value: (existing + newRating) / 2.0)
        } else {
            averageRating = NSNumber(value: newRating)
        }
    }

    // MARK: - Computed Properties

    var daysSinceLastCooked: Int? {
        guard let lastCooked = lastCookedDate else { return nil }
        return Calendar.current.dateComponents([.day], from: lastCooked, to: Date()).day
    }

    var daysSinceLastSuggested: Int? {
        guard let lastSuggested = lastSuggestedDate else { return nil }
        return Calendar.current.dateComponents([.day], from: lastSuggested, to: Date()).day
    }

    var wasRecentlyCooked: Bool {
        guard let days = daysSinceLastCooked else { return false }
        return days < 7
    }

    var isFrequentlyDeclined: Bool {
        suggestionDeclined > 2
    }

    var suggestionScore: Double {
        var score: Double = 0
        switch householdFamiliarity {
        case .staple: score += 25
        case .familiar: score += 20
        case .tried: score += 10
        case .new: score += 0
        }
        if let days = daysSinceLastCooked {
            if days < 7 { score -= 20 }
            else if days < 14 { score -= 10 }
        }
        score -= Double(suggestionDeclined) * 5
        if let rating = averageRating?.doubleValue, rating >= 4.0 {
            score += 10
        }
        return score
    }

    // MARK: - Convenience Initializer

    @discardableResult
    convenience init(
        context: NSManagedObjectContext,
        id: UUID = UUID(),
        recipe: Recipe? = nil,
        timesCooked: Int = 0,
        lastCookedDate: Date? = nil,
        averageRating: Double? = nil,
        lastSuggestedDate: Date? = nil,
        suggestionDeclined: Int = 0
    ) {
        let entity = NSEntityDescription.entity(forEntityName: "SuggestionMemory", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = id
        self.recipe = recipe
        self.timesCooked = Int32(timesCooked)
        self.lastCookedDate = lastCookedDate
        self.averageRating = averageRating.map { NSNumber(value: $0) }
        self.familiarityRaw = FamiliarityLevel.from(timesCooked: timesCooked).rawValue
        self.lastSuggestedDate = lastSuggestedDate
        self.suggestionDeclined = Int32(suggestionDeclined)
    }
}
