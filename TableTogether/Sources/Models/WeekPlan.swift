import Foundation
import SwiftData

// MARK: - WeekPlan Model

/// Container for a week's meal slots.
/// Each week plan starts on Monday and contains all meal slots for that week.
@Model
final class WeekPlan {
    /// Primary identifier
    @Attribute(.unique) var id: UUID

    /// Monday of the week (start date)
    var weekStartDate: Date

    /// Optional household note for the week
    var householdNote: String?

    /// Current status of the plan
    var status: WeekPlanStatus

    /// Creation timestamp
    var createdAt: Date

    /// Last modification timestamp
    var modifiedAt: Date

    // MARK: - Relationships

    /// All meal slots for this week
    @Relationship(deleteRule: .cascade)
    var slots: [MealSlot] = []

    /// Grocery items derived from this week's plan
    @Relationship(deleteRule: .cascade)
    var groceryItems: [GroceryItem] = []

    /// Parent household for CloudKit sharing
    @Relationship
    var household: Household?

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        weekStartDate: Date,
        householdNote: String? = nil,
        status: WeekPlanStatus = .draft
    ) {
        self.id = id
        self.weekStartDate = Self.normalizeToMonday(weekStartDate)
        self.householdNote = householdNote
        self.status = status
        self.createdAt = Date()
        self.modifiedAt = Date()
    }

    // MARK: - Computed Properties

    /// End date of the week (Sunday)
    var weekEndDate: Date {
        Calendar.current.date(byAdding: .day, value: 6, to: weekStartDate) ?? weekStartDate
    }

    /// Formatted week range string (e.g., "Jan 20 - 26, 2025")
    var weekRangeDisplay: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        let start = formatter.string(from: weekStartDate)

        let yearFormatter = DateFormatter()
        yearFormatter.dateFormat = "d, yyyy"
        let end = yearFormatter.string(from: weekEndDate)

        return "\(start) - \(end)"
    }

    /// Short week display (e.g., "Week of Jan 20")
    var shortWeekDisplay: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return "Week of \(formatter.string(from: weekStartDate))"
    }

    /// All planned slots (those with a recipe or custom meal)
    var plannedSlots: [MealSlot] {
        slots.filter { $0.isPlanned }
    }

    /// All empty slots (no recipe, no custom meal, not skipped)
    var emptySlots: [MealSlot] {
        slots.filter { $0.isEmpty }
    }

    /// Planning progress (0.0 to 1.0)
    var planningProgress: Double {
        guard !slots.isEmpty else { return 0.0 }
        let nonSkippedSlots = slots.filter { !$0.isSkipped }
        guard !nonSkippedSlots.isEmpty else { return 1.0 }
        return Double(plannedSlots.count) / Double(nonSkippedSlots.count)
    }

    /// Count of planned meals
    var plannedMealsCount: Int {
        plannedSlots.count
    }

    /// Total count of active slots (not skipped)
    var activeSlotsCount: Int {
        slots.filter { !$0.isSkipped }.count
    }

    /// Whether this is the current week
    var isCurrentWeek: Bool {
        let calendar = Calendar.current
        let today = Date()
        return calendar.isDate(today, equalTo: weekStartDate, toGranularity: .weekOfYear)
    }

    // MARK: - Methods

    /// Normalizes any date to the Monday of that week
    static func normalizeToMonday(_ date: Date) -> Date {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        components.weekday = 2 // Monday
        return calendar.date(from: components) ?? date
    }

    /// Gets slots for a specific day
    func slots(for day: DayOfWeek) -> [MealSlot] {
        slots.filter { $0.dayOfWeek == day }
            .sorted { $0.mealType.rawValue < $1.mealType.rawValue }
    }

    /// Gets a specific slot by day and meal type
    func slot(for day: DayOfWeek, mealType: MealType) -> MealSlot? {
        slots.first { $0.dayOfWeek == day && $0.mealType == mealType }
    }

    /// Creates default slots for all days and meal types
    func createDefaultSlots(mealTypes: [MealType] = [.breakfast, .lunch, .dinner]) {
        for day in DayOfWeek.allCases {
            for mealType in mealTypes {
                let slot = MealSlot(dayOfWeek: day, mealType: mealType)
                slot.weekPlan = self
                slots.append(slot)
            }
        }
        modifiedAt = Date()
    }

    /// Activates this week plan
    func activate() {
        status = .active
        modifiedAt = Date()
    }

    /// Marks this week plan as completed
    func complete() {
        status = .completed
        modifiedAt = Date()
    }

    /// Copies meal assignments from another week plan
    func copyFrom(_ otherPlan: WeekPlan, by user: User) {
        for otherSlot in otherPlan.slots {
            if let matchingSlot = slot(for: otherSlot.dayOfWeek, mealType: otherSlot.mealType) {
                if !otherSlot.recipes.isEmpty {
                    matchingSlot.recipes = otherSlot.recipes
                    matchingSlot.customMealName = nil
                    matchingSlot.isSkipped = false
                    matchingSlot.modifiedAt = Date()
                    matchingSlot.modifiedBy = user
                } else if let customName = otherSlot.customMealName {
                    matchingSlot.setCustomMeal(customName, by: user)
                }
                matchingSlot.servingsPlanned = otherSlot.servingsPlanned
                matchingSlot.archetype = otherSlot.archetype
            }
        }
        modifiedAt = Date()
    }

    /// Clears all meal assignments
    func clearAll(by user: User) {
        for slot in slots {
            slot.clear(by: user)
        }
        modifiedAt = Date()
    }

    /// Gets all unique recipes used in this week
    var uniqueRecipes: [Recipe] {
        Array(Set(slots.flatMap { $0.recipes }))
    }

    /// Gets date for a specific day of the week
    func date(for day: DayOfWeek) -> Date {
        let daysToAdd = day.rawValue - 1 // Monday = 1, so Monday adds 0 days
        return Calendar.current.date(byAdding: .day, value: daysToAdd, to: weekStartDate) ?? weekStartDate
    }
}
