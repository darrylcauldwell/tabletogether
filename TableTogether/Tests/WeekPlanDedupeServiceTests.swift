import Testing
import Foundation
import CoreData
@testable import TableTogetherLib

@MainActor
@Suite("WeekPlanDedupeService Tests", .serialized)
struct WeekPlanDedupeServiceTests {

    private func makeContext() -> NSManagedObjectContext {
        PersistenceController(inMemory: true).container.viewContext
    }

    /// Build "Monday local-midnight" as a Date. Uses the device's current
    /// timezone to match what `WeekPlan.normalizeToMonday` now produces.
    private func monday(year: Int, month: Int, day: Int) -> Date {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .current
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 0
        components.minute = 0
        components.second = 0
        return calendar.date(from: components)!
    }

    // MARK: - normalizeToMonday

    @Test("normalizeToMonday returns the Monday of the week containing the input")
    func normalizeReturnsMondayOfWeek() {
        // Wednesday April 8 2026 noon local time
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = .current
        let wednesday = cal.date(from: DateComponents(
            year: 2026, month: 4, day: 8, hour: 12, minute: 0, second: 0
        ))!

        let normalized = WeekPlan.normalizeToMonday(wednesday)
        let expectedMonday = monday(year: 2026, month: 4, day: 6)
        #expect(normalized == expectedMonday)
    }

    @Test("normalizeToMonday returns the same Monday for different days within a week")
    func normalizeIsStableAcrossWeek() {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = .current
        let expectedMonday = monday(year: 2026, month: 4, day: 6)

        for dayOffset in 0...6 {
            let day = cal.date(byAdding: .day, value: dayOffset, to: expectedMonday)!
            let normalized = WeekPlan.normalizeToMonday(day)
            #expect(normalized == expectedMonday, "Day offset \(dayOffset) normalized to wrong Monday")
        }
    }

    @Test("deterministicID is stable for the same week across multiple normalize calls")
    func deterministicIDIsStable() {
        let wednesday = monday(year: 2026, month: 4, day: 6).addingTimeInterval(2 * 86400 + 3600 * 14)
        let id1 = WeekPlan.deterministicID(for: wednesday)

        let sunday = monday(year: 2026, month: 4, day: 6).addingTimeInterval(6 * 86400)
        let id2 = WeekPlan.deterministicID(for: sunday)

        #expect(id1 == id2)
    }

    // MARK: - Dedupe migration

    @Test("runIfNeeded is idempotent via UserDefaults flag")
    func runIfNeededIsIdempotent() {
        let context = makeContext()
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: WeekPlanDedupeService.migrationFlagKey)
        defer { defaults.removeObject(forKey: WeekPlanDedupeService.migrationFlagKey) }

        let service = WeekPlanDedupeService()
        let first = service.runIfNeeded(context: context)
        #expect(first != nil)

        let second = service.runIfNeeded(context: context)
        #expect(second == nil, "Second run should be guarded by the flag")
    }

    @Test("Two WeekPlans with the same normalized week merge into one")
    func mergesDuplicateWeekPlans() throws {
        let context = makeContext()
        let household = Household(context: context, name: "Test")

        let mondayDate = monday(year: 2026, month: 4, day: 6)
        // Plan A: correctly normalized (this is the canonical target)
        let planA = WeekPlan(context: context, weekStartDate: mondayDate)
        planA.household = household
        planA.createdAt = Date(timeIntervalSince1970: 1000)
        // Force a different UUID so we can tell them apart
        planA.id = UUID()

        // Plan B: created from a slightly-different Date (simulating the bug)
        // but normalizes to the same Monday
        let wrongDate = mondayDate.addingTimeInterval(3600) // +1 hour, same day
        let planB = WeekPlan(context: context, weekStartDate: wrongDate)
        planB.household = household
        planB.createdAt = Date(timeIntervalSince1970: 2000)
        planB.id = UUID()

        try context.save()

        #expect(tryCount(WeekPlan.self, in: context) == 2)

        let result = WeekPlanDedupeService().run(context: context)

        #expect(result.planDuplicatesRemoved == 1)
        #expect(tryCount(WeekPlan.self, in: context) == 1)
    }

    @Test("Slots from duplicate plans are reparented to the canonical plan")
    func slotsMoveToCanonical() throws {
        let context = makeContext()
        let household = Household(context: context, name: "Test")
        let mondayDate = monday(year: 2026, month: 4, day: 6)

        let planA = WeekPlan(context: context, weekStartDate: mondayDate)
        planA.household = household
        planA.createdAt = Date(timeIntervalSince1970: 1000)
        let slotA = MealSlot(context: context, dayOfWeek: .monday, mealType: .dinner)
        slotA.weekPlan = planA
        planA.addToSlots(slotA)

        // Plan B: same week, different random UUID
        let planB = WeekPlan(context: context, weekStartDate: mondayDate)
        planB.id = UUID()
        planB.household = household
        planB.createdAt = Date(timeIntervalSince1970: 2000)
        let slotB = MealSlot(context: context, dayOfWeek: .tuesday, mealType: .breakfast)
        slotB.weekPlan = planB
        planB.addToSlots(slotB)

        try context.save()

        let result = WeekPlanDedupeService().run(context: context)

        #expect(result.planDuplicatesRemoved == 1)
        // After merge: 1 plan, 2 slots (different (day, mealType) so not merged)
        #expect(tryCount(WeekPlan.self, in: context) == 1)
        #expect(tryCount(MealSlot.self, in: context) == 2)

        let canonical = try context.fetch(NSFetchRequest<WeekPlan>(entityName: "WeekPlan")).first
        #expect(canonical?.slotsArray.count == 2)
    }

    @Test("Duplicate slots within a merged plan are deduped by (day, mealType)")
    func duplicateSlotsInSamePlanMerge() throws {
        let context = makeContext()
        let household = Household(context: context, name: "Test")
        let mondayDate = monday(year: 2026, month: 4, day: 6)

        // Create a single plan but with two duplicate "Tuesday breakfast" slots
        let plan = WeekPlan(context: context, weekStartDate: mondayDate)
        plan.household = household

        let slot1 = MealSlot(context: context, dayOfWeek: .tuesday, mealType: .breakfast)
        slot1.weekPlan = plan
        plan.addToSlots(slot1)

        let slot2 = MealSlot(context: context, dayOfWeek: .tuesday, mealType: .breakfast)
        slot2.weekPlan = plan
        plan.addToSlots(slot2)

        try context.save()
        #expect(plan.slotsArray.count == 2)

        WeekPlanDedupeService().run(context: context)

        // After dedup: 1 slot should remain for Tuesday breakfast
        let refreshedPlan = try context.fetch(NSFetchRequest<WeekPlan>(entityName: "WeekPlan")).first!
        #expect(refreshedPlan.slotsArray.count == 1)
    }

    @Test("When merging slots, the one with more recipes wins")
    func slotMergePicksRichestCanonical() throws {
        let context = makeContext()
        let household = Household(context: context, name: "Test")
        let mondayDate = monday(year: 2026, month: 4, day: 6)

        let recipeA = Recipe(context: context, title: "A")
        recipeA.household = household
        let recipeB = Recipe(context: context, title: "B")
        recipeB.household = household

        let plan = WeekPlan(context: context, weekStartDate: mondayDate)
        plan.household = household

        // Empty slot — should NOT be the canonical
        let emptySlot = MealSlot(context: context, dayOfWeek: .wednesday, mealType: .dinner)
        emptySlot.weekPlan = plan
        plan.addToSlots(emptySlot)

        // Populated slot with two recipes — should win
        let populatedSlot = MealSlot(context: context, dayOfWeek: .wednesday, mealType: .dinner)
        populatedSlot.weekPlan = plan
        populatedSlot.addToRecipes(recipeA)
        populatedSlot.addToRecipes(recipeB)
        plan.addToSlots(populatedSlot)

        try context.save()

        WeekPlanDedupeService().run(context: context)

        // Should be 1 slot left, the populated one, with both recipes
        let refreshedPlan = try context.fetch(NSFetchRequest<WeekPlan>(entityName: "WeekPlan")).first!
        #expect(refreshedPlan.slotsArray.count == 1)
        let winner = refreshedPlan.slotsArray.first!
        #expect(winner.recipesArray.count == 2)
    }

    @Test("Recipe sets are unioned when merging duplicate slots")
    func recipeSetsUnionOnMerge() throws {
        let context = makeContext()
        let household = Household(context: context, name: "Test")
        let mondayDate = monday(year: 2026, month: 4, day: 6)

        let recipeA = Recipe(context: context, title: "A")
        recipeA.household = household
        let recipeB = Recipe(context: context, title: "B")
        recipeB.household = household
        let recipeC = Recipe(context: context, title: "C")
        recipeC.household = household

        let plan = WeekPlan(context: context, weekStartDate: mondayDate)
        plan.household = household

        // Canonical candidate 1: 2 recipes (A, B)
        let slot1 = MealSlot(context: context, dayOfWeek: .friday, mealType: .dinner)
        slot1.weekPlan = plan
        slot1.addToRecipes(recipeA)
        slot1.addToRecipes(recipeB)
        plan.addToSlots(slot1)

        // Duplicate: 1 recipe (C)
        let slot2 = MealSlot(context: context, dayOfWeek: .friday, mealType: .dinner)
        slot2.weekPlan = plan
        slot2.addToRecipes(recipeC)
        plan.addToSlots(slot2)

        try context.save()

        let result = WeekPlanDedupeService().run(context: context)

        #expect(result.recipeRelationshipsMerged == 1) // C was added to canonical
        let refreshedPlan = try context.fetch(NSFetchRequest<WeekPlan>(entityName: "WeekPlan")).first!
        let winner = refreshedPlan.slotsArray.first!
        #expect(winner.recipesArray.count == 3) // A + B + C
    }

    @Test("Idempotent: running dedupe on already-clean data does nothing")
    func idempotentOnCleanData() throws {
        let context = makeContext()
        let household = Household(context: context, name: "Test")
        let mondayDate = monday(year: 2026, month: 4, day: 6)

        let plan = WeekPlan(context: context, weekStartDate: mondayDate)
        plan.household = household
        plan.createDefaultSlots(context: context)
        try context.save()

        let beforeSlots = plan.slotsArray.count

        let result1 = WeekPlanDedupeService().run(context: context)
        #expect(result1.planDuplicatesRemoved == 0)
        #expect(result1.slotDuplicatesRemoved == 0)

        // Run again — should still be clean
        let result2 = WeekPlanDedupeService().run(context: context)
        #expect(result2.planDuplicatesRemoved == 0)
        #expect(result2.slotDuplicatesRemoved == 0)

        let refreshedPlan = try context.fetch(NSFetchRequest<WeekPlan>(entityName: "WeekPlan")).first!
        #expect(refreshedPlan.slotsArray.count == beforeSlots)
    }

    // MARK: - Helpers

    private func tryCount<T: NSManagedObject>(_ type: T.Type, in context: NSManagedObjectContext) -> Int {
        let request = NSFetchRequest<T>(entityName: String(describing: type))
        return (try? context.count(for: request)) ?? 0
    }
}
