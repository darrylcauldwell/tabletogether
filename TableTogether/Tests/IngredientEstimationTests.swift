import Testing
import CoreData
@testable import TableTogetherLib

// MARK: - MealEstimatorService

@MainActor
struct MealEstimatorServiceTests {

    @Test("Empty description returns nil")
    func emptyReturnsNil() {
        #expect(MealEstimatorService().estimate(description: "") == nil)
    }

    @Test("'beans on toast' yields its known components with positive macros")
    func beansOnToast() {
        let estimate = MealEstimatorService().estimate(description: "beans on toast")
        #expect(estimate != nil)
        #expect(estimate?.components.count == 3)
        let names = (estimate?.components.map { $0.name.lowercased() }) ?? []
        #expect(names.contains { $0.contains("bean") })
        #expect(names.contains { $0.contains("toast") })
        #expect((estimate?.totalMacros.calories ?? 0) > 0)
    }


    @Test("Bare 'pie' gets a modest generic estimate instead of nothing")
    func genericPieEstimates() {
        let estimate = MealEstimatorService().estimate(description: "pie")
        #expect((estimate?.totalMacros.calories ?? 0) > 0)
    }

    @Test("'chips and gravy' estimates both components")
    func chipsAndGravy() {
        let estimate = MealEstimatorService().estimate(description: "chips and gravy")
        let names = (estimate?.components.map { $0.name.lowercased() }) ?? []
        #expect(names.contains { $0.contains("chips") })
        #expect(names.contains { $0.contains("gravy") })
        #expect((estimate?.totalMacros.calories ?? 0) > 0)
    }

    @Test("'egg on toast' includes eggs")
    func eggOnToast() {
        let estimate = MealEstimatorService().estimate(description: "egg on toast")
        let names = (estimate?.components.map { $0.name.lowercased() }) ?? []
        #expect(names.contains { $0.contains("egg") })
    }

    @Test("'egg on toast with chips' picks up the side dish")
    func eggOnToastWithChips() {
        let estimate = MealEstimatorService().estimate(description: "egg on toast with chips")
        let names = (estimate?.components.map { $0.name.lowercased() }) ?? []
        #expect(names.contains { $0.contains("chip") })
    }

    @Test("Total macros equal the sum of the components")
    func totalIsSumOfComponents() {
        guard let estimate = MealEstimatorService().estimate(description: "beans on toast") else {
            Issue.record("Expected an estimate for 'beans on toast'")
            return
        }
        let summed = estimate.components.reduce(MacroSummary.zero) { $0.adding($1.macros) }
        #expect(estimate.totalMacros.calories == summed.calories)
        #expect(estimate.totalMacros.protein == summed.protein)
    }

    @Test("Unrecognised text returns nil")
    func unrecognisedReturnsNil() {
        #expect(MealEstimatorService().estimate(description: "qwxyz vroom blarg") == nil)
    }
}

// MARK: - IngredientResolverService (local-cache path, network-free)

@MainActor
struct IngredientResolverServiceTests {

    private func makeContext() -> NSManagedObjectContext {
        PersistenceController(inMemory: true).viewContext
    }

    @discardableResult
    private func seedFoodItem(_ name: String, in context: NSManagedObjectContext) -> FoodItem {
        FoodItem(
            context: context,
            fdcId: 1,
            usdaDescription: "\(name), raw",
            displayName: name,
            dataType: "Foundation",
            caloriesPer100g: 165,
            proteinPer100g: 31,
            carbsPer100g: 0,
            fatPer100g: 3.6
        )
    }

    private func parsed(_ name: String) -> MealParsedIngredient {
        MealParsedIngredient(name: name, quantity: 1, unit: nil, confidence: .high, originalText: name)
    }

    @Test("An exact local FoodItem match resolves from the local cache (no network)")
    func localCacheHit() async {
        let context = makeContext()
        seedFoodItem("Chicken Breast", in: context)

        let resolver = IngredientResolverService()
        let results = await resolver.resolve(
            ingredients: [parsed("chicken breast")], context: context, household: nil)

        #expect(results.count == 1)
        #expect(results.first?.source == .localCache)
        #expect(results.first?.foodItem?.normalizedName == "chicken breast")
    }

    @Test("Resolving several ingredients returns one result each, in order")
    func resolvesEachIngredient() async {
        let context = makeContext()
        seedFoodItem("Chicken Breast", in: context)
        seedFoodItem("Brown Rice", in: context)

        let resolver = IngredientResolverService()
        let results = await resolver.resolve(
            ingredients: [parsed("chicken breast"), parsed("brown rice")],
            context: context, household: nil)

        #expect(results.count == 2)
        #expect(results.allSatisfy { $0.source == .localCache })
    }
}
