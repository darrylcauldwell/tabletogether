import Testing
import Foundation
import CoreData
@testable import TableTogetherLib

@MainActor
@Suite("FoodItemMergeService Tests", .serialized)
struct FoodItemMergeServiceTests {

    private func makeContext() -> (NSManagedObjectContext, Household) {
        let context = PersistenceController(inMemory: true).container.viewContext
        let household = Household(context: context, name: "Test")
        return (context, household)
    }

    private func makeFoodItem(
        _ name: String,
        in context: NSManagedObjectContext,
        household: Household,
        aliases: [String] = []
    ) -> FoodItem {
        let item = FoodItem(
            context: context,
            fdcId: 0,
            usdaDescription: name,
            displayName: name,
            dataType: "Custom",
            caloriesPer100g: 100,
            proteinPer100g: 10,
            carbsPer100g: 10,
            fatPer100g: 5
        )
        item.household = household
        for alias in aliases {
            item.addAlias(alias)
        }
        return item
    }

    private func foodItemCount(in context: NSManagedObjectContext) -> Int {
        let request = NSFetchRequest<FoodItem>(entityName: "FoodItem")
        return (try? context.count(for: request)) ?? 0
    }

    // MARK: - Basic merge

    @Test("Merging deletes source and reassigns MealSlotComponent FKs")
    func basicMerge() throws {
        let (context, household) = makeContext()
        let source = makeFoodItem("Tofu (silken)", in: context, household: household)
        let canonical = makeFoodItem("Tofu", in: context, household: household)

        // Attach a meal slot component referencing source
        let weekPlan = WeekPlan(context: context)
        weekPlan.household = household
        let slot = MealSlot(context: context)
        slot.weekPlan = weekPlan
        let component = MealSlotComponent(context: context)
        component.slot = slot
        component.foodItem = source

        try context.save()

        let service = FoodItemMergeService()
        let preview = try service.merge(source: source, into: canonical)

        #expect(preview.mealSlotComponentCount == 1)
        #expect(foodItemCount(in: context) == 1)

        let allMSC = try context.fetch(NSFetchRequest<MealSlotComponent>(entityName: "MealSlotComponent"))
        #expect(allMSC.first?.foodItem === canonical)
    }

    // MARK: - Alias preservation

    @Test("Source displayName becomes an alias on canonical")
    func sourceNameBecomesAlias() throws {
        let (context, household) = makeContext()
        let source = makeFoodItem("Soybean curd", in: context, household: household)
        let canonical = makeFoodItem("Tofu", in: context, household: household)

        let service = FoodItemMergeService()
        try service.merge(source: source, into: canonical)

        #expect(canonical.userAliasesList.contains("soybean curd"))
    }

    @Test("Source aliases transfer to canonical")
    func sourceAliasesTransfer() throws {
        let (context, household) = makeContext()
        let source = makeFoodItem(
            "Soybean curd",
            in: context,
            household: household,
            aliases: ["bean curd", "doufu"]
        )
        let canonical = makeFoodItem("Tofu", in: context, household: household)

        let service = FoodItemMergeService()
        try service.merge(source: source, into: canonical)

        #expect(canonical.userAliasesList.contains("soybean curd"))
        #expect(canonical.userAliasesList.contains("bean curd"))
        #expect(canonical.userAliasesList.contains("doufu"))
    }

    @Test("Existing aliases on canonical are preserved and not duplicated")
    func canonicalAliasesPreservedNoDup() throws {
        let (context, household) = makeContext()
        let source = makeFoodItem(
            "Soybean curd",
            in: context,
            household: household,
            aliases: ["bean curd"]
        )
        let canonical = makeFoodItem(
            "Tofu",
            in: context,
            household: household,
            aliases: ["bean curd", "soya cake"]
        )

        let service = FoodItemMergeService()
        try service.merge(source: source, into: canonical)

        #expect(canonical.userAliasesList.contains("bean curd"))
        #expect(canonical.userAliasesList.contains("soya cake"))
        #expect(canonical.userAliasesList.contains("soybean curd"))
        let count = canonical.userAliasesList.filter { $0 == "bean curd" }.count
        #expect(count == 1)
    }

    // MARK: - Error cases

    @Test("Merging into itself throws sameRecord")
    func sameRecordError() throws {
        let (context, household) = makeContext()
        let only = makeFoodItem("Solo", in: context, household: household)
        let service = FoodItemMergeService()
        #expect(throws: FoodItemMergeService.MergeError.self) {
            try service.merge(source: only, into: only)
        }
    }

    @Test("Merging across households throws mismatchedHousehold")
    func mismatchedHouseholdError() throws {
        let context = PersistenceController(inMemory: true).container.viewContext
        let householdA = Household(context: context, name: "A")
        let householdB = Household(context: context, name: "B")
        let inA = makeFoodItem("foo", in: context, household: householdA)
        let inB = makeFoodItem("foo", in: context, household: householdB)
        let service = FoodItemMergeService()
        #expect(throws: FoodItemMergeService.MergeError.self) {
            try service.merge(source: inA, into: inB)
        }
    }

    // MARK: - Preview

    @Test("Preview is non-mutating")
    func previewIsNonMutating() throws {
        let (context, household) = makeContext()
        let source = makeFoodItem(
            "source",
            in: context,
            household: household,
            aliases: ["s1", "s2"]
        )
        let canonical = makeFoodItem("canonical", in: context, household: household)

        let service = FoodItemMergeService()
        let preview = service.preview(source: source, into: canonical)

        #expect(preview.sourceName == "source")
        #expect(preview.canonicalName == "canonical")
        #expect(preview.aliasesToTransfer.count == 3) // source name + 2 aliases

        // State unchanged
        #expect(foodItemCount(in: context) == 2)
        #expect(canonical.userAliasesList.isEmpty)
    }
}
