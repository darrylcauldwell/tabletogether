import Testing
import Foundation
import CloudKit
@testable import TableTogetherLib

// MARK: - PrivateMealLog CKRecord / Codable round-trip

struct PrivateMealLogTests {

    private func fixedDate() -> Date {
        var comps = DateComponents()
        comps.year = 2025; comps.month = 6; comps.day = 2; comps.hour = 12
        return Calendar.current.date(from: comps)!
    }

    @Test("Recipe-based log survives a CKRecord round-trip")
    func recipeLogRoundTrips() {
        let original = PrivateMealLog(
            id: UUID(), date: fixedDate(), mealType: .dinner,
            recipeID: UUID(), mealSlotID: UUID(), servingsConsumed: 1.5,
            notes: "tasty", status: .consumed)

        let restored = PrivateMealLog(from: original.toRecord())
        #expect(restored != nil)
        #expect(restored?.id == original.id)
        #expect(restored?.recipeID == original.recipeID)
        #expect(restored?.mealSlotID == original.mealSlotID)
        #expect(restored?.servingsConsumed == 1.5)
        #expect(restored?.mealType == .dinner)
        #expect(restored?.status == .consumed)
    }

    @Test("Quick-log macros survive a CKRecord round-trip")
    func quickLogRoundTrips() {
        let original = PrivateMealLog(
            id: UUID(), date: fixedDate(), mealType: .lunch,
            quickLogName: "Sandwich", calories: 450, protein: 20, carbs: 50, fat: 18)

        let restored = PrivateMealLog(from: original.toRecord())
        #expect(restored?.quickLogName == "Sandwich")
        #expect(restored?.quickLogCalories == 450)
        #expect(restored?.quickLogProtein == 20)
        #expect(restored?.quickLogCarbs == 50)
        #expect(restored?.quickLogFat == 18)
        #expect(restored?.isQuickLog == true)
    }

    @Test("A record with no status defaults to .consumed (backward compat)")
    func missingStatusDefaultsConsumed() {
        let record = CKRecord(recordType: PrivateMealLog.recordType)
        record["id"] = UUID().uuidString as CKRecordValue
        record["date"] = fixedDate() as CKRecordValue
        record["mealType"] = MealType.breakfast.rawValue as CKRecordValue
        // deliberately no "status"

        let restored = PrivateMealLog(from: record)
        #expect(restored?.status == .consumed)
    }

    @Test("A record of the wrong type returns nil")
    func wrongRecordTypeReturnsNil() {
        let record = CKRecord(recordType: "NotAMealLog")
        record["id"] = UUID().uuidString as CKRecordValue
        record["date"] = fixedDate() as CKRecordValue
        record["mealType"] = MealType.dinner.rawValue as CKRecordValue
        #expect(PrivateMealLog(from: record) == nil)
    }

    @Test("A record missing a required field returns nil")
    func missingRequiredFieldReturnsNil() {
        let record = CKRecord(recordType: PrivateMealLog.recordType)
        record["date"] = fixedDate() as CKRecordValue
        record["mealType"] = MealType.dinner.rawValue as CKRecordValue
        // no "id"
        #expect(PrivateMealLog(from: record) == nil)
    }

    @Test("Codable round-trip preserves all fields")
    func codableRoundTrips() throws {
        let original = PrivateMealLog(
            id: UUID(), date: fixedDate(), mealType: .snack,
            quickLogName: "Apple", calories: 95)
        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(PrivateMealLog.self, from: data)
        #expect(restored.id == original.id)
        #expect(restored.quickLogName == "Apple")
        #expect(restored.quickLogCalories == 95)
    }
}

// MARK: - MacroAggregator

private struct StubRecipeLookup: RecipeMacroLookup {
    let macros: MacroSummary
    func macrosPerServing(for recipeID: UUID) -> MacroSummary? { macros }
}

struct MacroAggregatorTests {

    private func monday() -> Date {
        var comps = DateComponents()
        comps.year = 2025; comps.month = 6; comps.day = 2 // a Monday
        return Calendar.current.startOfDay(for: Calendar.current.date(from: comps)!)
    }

    @Test("A quick-log meal surfaces its manual macros")
    func quickLogSurfacesMacros() {
        let day = monday()
        let log = PrivateMealLog(date: day, mealType: .lunch,
                                 quickLogName: "Bowl", calories: 600, protein: 40, carbs: 60, fat: 20)
        let result = MacroAggregator().aggregateDailyMacros(on: day, logs: [log])
        #expect(result.mealsLogged == 1)
        #expect(result.macros.calories == 600)
        #expect(result.macros.protein == 40)
    }

    @Test("A recipe-based log is scaled by servings consumed")
    func recipeLogScaledByServings() {
        let day = monday()
        let log = PrivateMealLog(date: day, mealType: .dinner,
                                 recipeID: UUID(), servingsConsumed: 1.5)
        let lookup = StubRecipeLookup(macros: MacroSummary(calories: 400, protein: 30, carbs: 40, fat: 10))
        let result = MacroAggregator().aggregateDailyMacros(on: day, logs: [log], recipeLookup: lookup)
        #expect(result.macros.calories == 600)   // 400 * 1.5
        #expect(result.macros.protein == 45)      // 30 * 1.5
    }

    @Test("Weekly aggregation produces exactly seven startOfDay buckets")
    func weeklyHasSevenBuckets() {
        let start = monday()
        let log = PrivateMealLog(date: start, mealType: .breakfast,
                                 quickLogName: "Toast", calories: 200)
        let week = MacroAggregator().aggregateWeeklyMacros(weekStart: start, logs: [log])
        #expect(week.count == 7)
        // Every key is normalized to start-of-day.
        #expect(week.keys.allSatisfy { $0 == Calendar.current.startOfDay(for: $0) })
        // The log's day has one meal; the others are empty.
        #expect(week[start]?.mealsLogged == 1)
        #expect(week.values.filter { $0.mealsLogged > 0 }.count == 1)
    }

    @Test("Insight text with no data invites logging")
    func insightTextEmpty() {
        let text = MacroAggregator().generateInsightText(from: [:])
        #expect(text.contains("Start logging"))
    }

    @Test("Insight text never uses judgmental language")
    func insightTextIsNonJudgmental() {
        let start = monday()
        // A few days of varied data so the generator produces real observations.
        let logs = [
            PrivateMealLog(date: start, mealType: .breakfast, quickLogName: "Eggs", calories: 350, protein: 25, carbs: 5, fat: 25),
            PrivateMealLog(date: start, mealType: .lunch, quickLogName: "Salad", calories: 500, protein: 30, carbs: 40, fat: 20),
            PrivateMealLog(date: Calendar.current.date(byAdding: .day, value: 1, to: start)!,
                           mealType: .dinner, quickLogName: "Pasta", calories: 700, protein: 25, carbs: 90, fat: 20),
        ]
        let week = MacroAggregator().aggregateWeeklyMacros(weekStart: start, logs: logs)
        let text = MacroAggregator().generateInsightText(from: week).lowercased()

        for forbidden in ["deficit", "excess", "failed", "inconsistent", "should", "bad", "guilt"] {
            #expect(!text.contains(forbidden), "Insight text must avoid judgmental term: \(forbidden)")
        }
        #expect(!text.isEmpty)
    }
}
