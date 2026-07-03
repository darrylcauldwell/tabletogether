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

    @Test("Alcoholic drinks estimate calories")
    func alcoholEstimates() {
        let estimator = MealEstimatorService()
        for drink in ["gin and tonic", "red wine", "beer", "prosecco", "wine"] {
            let estimate = estimator.estimate(description: drink)
            #expect((estimate?.totalMacros.calories ?? 0) > 0, "\(drink) should estimate calories")
        }
    }

    @Test("Compound drink beats bare spirit in matching")
    func compoundDrinkWins() {
        let estimate = MealEstimatorService().estimate(description: "gin and tonic")
        let names = (estimate?.components.map { $0.name.lowercased() }) ?? []
        #expect(names.contains { $0.contains("gin and tonic") })
    }

    @Test("Explicit ABV + volume + quantity computes precise alcohol calories")
    func preciseAlcohol() {
        let estimate = MealEstimatorService().estimate(description: "4x 440ml 8% DIPA")
        // Ethanol ≈ 778 kcal + residual carbs (~211) ≈ 990 across 4 cans.
        let cal = estimate?.totalMacros.calories ?? 0
        #expect(cal > 900 && cal < 1100, "expected ~990, got \(cal)")
        #expect(estimate?.components.first?.name == "Double IPA")
    }

    @Test("Wine ABV changes calories; a bottle is 750ml")
    func wineBottleAndABV() {
        let estimator = MealEstimatorService()
        let light = estimator.estimate(description: "bottle of wine 10%")?.totalMacros.calories ?? 0
        let strong = estimator.estimate(description: "bottle of wine 14%")?.totalMacros.calories ?? 0
        #expect(light < strong)
        // 750ml × 14% × 0.789 × 7 ≈ 580 alcohol + carbs → a full bottle is high.
        #expect(strong > 500, "a 14% bottle should be substantial, got \(strong)")
    }

    @Test("Higher ABV yields more calories for the same volume")
    func abvScalesCalories() {
        let estimator = MealEstimatorService()
        let weak = estimator.estimate(description: "440ml 3% beer")?.totalMacros.calories ?? 0
        let strong = estimator.estimate(description: "440ml 8% beer")?.totalMacros.calories ?? 0
        #expect(weak < strong)
    }

    @Test("Drinks without an explicit ABV still fall back to named tiers")
    func vagueAlcoholFallsBackToTiers() {
        // No "%": the precise parser must not fire; the named tier handles it.
        let estimate = MealEstimatorService().estimate(description: "a pint of lager")
        #expect((estimate?.totalMacros.calories ?? 0) > 0)
    }

    @Test("Beer strength tiers scale calories by ABV band")
    func beerStrengthTiers() {
        let estimator = MealEstimatorService()
        let light = estimator.estimate(description: "light beer")?.totalMacros.calories ?? 0
        let lager = estimator.estimate(description: "lager")?.totalMacros.calories ?? 0
        let ipa = estimator.estimate(description: "IPA")?.totalMacros.calories ?? 0
        let strong = estimator.estimate(description: "double IPA")?.totalMacros.calories ?? 0
        #expect(light < lager)
        #expect(lager < ipa)
        #expect(ipa < strong)
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
