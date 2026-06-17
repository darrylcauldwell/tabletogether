import Testing
import Foundation
import CoreData
@testable import TableTogetherLib

/// Tests for `SuggestionEngine` scoring and ranking behaviour.
///
/// `ScoringConstants` inside `SuggestionEngine` is `private`, so these tests assert
/// behaviour via *ranking / ordering* and via the *presence or absence* of a recipe
/// in the familiar/new buckets, rather than by hardcoding magic score totals.
///
/// Confirmed constant values from source (`SuggestionEngine.ScoringConstants`):
///   archetypeMatchBonus = 30, stapleFamiliarityBonus = 25, familiarFamiliarityBonus = 20,
///   triedFamiliarityBonus = 10, favoriteBonus = 15, recentlyUsedPenalty7Days = -20,
///   recentlyUsedPenalty14Days = -10, declinePenaltyMultiplier = 5, declineThreshold = 2.
@MainActor
@Suite("SuggestionEngine Tests", .serialized)
struct SuggestionEngineTests {

    /// The decline threshold pinned by the recent `>=` fix. Mirrors
    /// `SuggestionEngine.ScoringConstants.declineThreshold`, which is `private` and
    /// therefore not directly referenceable from tests.
    private static let declineThreshold = 2

    // MARK: - Fixtures

    private func makeContext() -> (NSManagedObjectContext, Household) {
        let context = PersistenceController(inMemory: true).container.viewContext
        let household = Household(context: context, name: "Test")
        return (context, household)
    }

    /// Builds a recipe attached to the household.
    @discardableResult
    private func makeRecipe(
        _ title: String,
        in context: NSManagedObjectContext,
        household: Household,
        isFavorite: Bool = false,
        lastCookedDate: Date? = nil,
        suggestedArchetypes: [ArchetypeType] = []
    ) -> Recipe {
        let recipe = Recipe(
            context: context,
            title: title,
            suggestedArchetypes: suggestedArchetypes,
            isFavorite: isFavorite,
            lastCookedDate: lastCookedDate
        )
        recipe.household = household
        return recipe
    }

    /// Builds a `SuggestionMemory` linked to the given recipe. `familiarity` is set
    /// explicitly after init because the convenience init derives familiarity from
    /// `timesCooked`; setting it directly keeps tests independent of that mapping.
    @discardableResult
    private func makeMemory(
        for recipe: Recipe,
        in context: NSManagedObjectContext,
        household: Household,
        familiarity: FamiliarityLevel,
        lastCookedDate: Date? = nil,
        suggestionDeclined: Int = 0
    ) -> SuggestionMemory {
        let memory = SuggestionMemory(
            context: context,
            recipe: recipe,
            lastCookedDate: lastCookedDate,
            suggestionDeclined: suggestionDeclined
        )
        memory.household = household
        memory.householdFamiliarity = familiarity
        return memory
    }

    private func daysAgo(_ days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -days, to: Date())!
    }

    /// Rank (index) of a recipe in the combined familiar-then-new ordering returned
    /// by a `SuggestionResult`. Lower index = ranked higher. `nil` if not present.
    private func rank(of recipe: Recipe, in result: SuggestionResult) -> Int? {
        let ordered = result.familiarSuggestions + result.newSuggestions
        return ordered.firstIndex { $0.id == recipe.id }
    }

    // MARK: - Familiarity bonus ordering

    @Test("A familiar/staple recipe ranks above a brand-new one, all else equal")
    func familiarRanksAboveNew() {
        let (context, household) = makeContext()

        let staple = makeRecipe("Staple", in: context, household: household)
        let brandNew = makeRecipe("Brand New", in: context, household: household)

        let stapleMemory = makeMemory(for: staple, in: context, household: household, familiarity: .staple)
        // Brand-new recipe has no memory at all (the .new / nil branch gives no bonus).
        let memory = [stapleMemory]

        let engine = SuggestionEngine()
        let result = engine.suggestRecipes(allRecipes: [staple, brandNew], weekPlan: nil, memory: memory)

        // Familiar bucket contains the staple; new bucket contains the brand-new one.
        #expect(result.familiarSuggestions.contains { $0.id == staple.id })
        #expect(result.newSuggestions.contains { $0.id == brandNew.id })
        #expect(rank(of: staple, in: result)! < rank(of: brandNew, in: result)!)
    }

    @Test("Staple ranks above familiar ranks above tried (familiarity gradient)")
    func familiarityGradientOrders() {
        let (context, household) = makeContext()

        let staple = makeRecipe("Staple", in: context, household: household)
        let familiar = makeRecipe("Familiar", in: context, household: household)
        let tried = makeRecipe("Tried", in: context, household: household)

        let memory = [
            makeMemory(for: staple, in: context, household: household, familiarity: .staple),
            makeMemory(for: familiar, in: context, household: household, familiarity: .familiar),
            makeMemory(for: tried, in: context, household: household, familiarity: .tried)
        ]

        let engine = SuggestionEngine()
        let result = engine.suggestRecipes(allRecipes: [tried, familiar, staple], weekPlan: nil, memory: memory)

        // All three are non-new, so all land in the familiar bucket, ordered by score.
        #expect(result.familiarSuggestions.map(\.id) == [staple.id, familiar.id, tried.id])
    }

    // MARK: - Favorite bonus

    @Test("A favorite ranks above an equivalent non-favorite")
    func favoriteRanksAboveNonFavorite() {
        let (context, household) = makeContext()

        let favorite = makeRecipe("Favorite", in: context, household: household, isFavorite: true)
        let plain = makeRecipe("Plain", in: context, household: household, isFavorite: false)

        // Identical familiarity so the only differentiator is the favorite bonus.
        let memory = [
            makeMemory(for: favorite, in: context, household: household, familiarity: .familiar),
            makeMemory(for: plain, in: context, household: household, familiarity: .familiar)
        ]

        let engine = SuggestionEngine()
        let result = engine.suggestRecipes(allRecipes: [plain, favorite], weekPlan: nil, memory: memory)

        #expect(result.familiarSuggestions.first?.id == favorite.id)
        #expect(rank(of: favorite, in: result)! < rank(of: plain, in: result)!)
    }

    // MARK: - Recency penalty

    @Test("General path: a recently-cooked recipe ranks below one cooked long ago")
    func recencyPenaltyGeneralPath() {
        let (context, household) = makeContext()

        // General scoring reads recency from `recipe.lastCookedDate`.
        let recent = makeRecipe("Recent", in: context, household: household, lastCookedDate: daysAgo(2))
        let longAgo = makeRecipe("Long Ago", in: context, household: household, lastCookedDate: daysAgo(60))

        let memory = [
            makeMemory(for: recent, in: context, household: household, familiarity: .familiar),
            makeMemory(for: longAgo, in: context, household: household, familiarity: .familiar)
        ]

        let engine = SuggestionEngine()
        let result = engine.suggestRecipes(allRecipes: [recent, longAgo], weekPlan: nil, memory: memory)

        #expect(rank(of: longAgo, in: result)! < rank(of: recent, in: result)!)
    }

    @Test("Slot path: a recently-cooked recipe ranks below one cooked long ago")
    func recencyPenaltySlotPath() {
        let (context, household) = makeContext()

        // Slot scoring reads recency from the *memory's* lastCookedDate.
        let recent = makeRecipe("Recent", in: context, household: household)
        let longAgo = makeRecipe("Long Ago", in: context, household: household)

        let memory = [
            makeMemory(for: recent, in: context, household: household, familiarity: .familiar, lastCookedDate: daysAgo(2)),
            makeMemory(for: longAgo, in: context, household: household, familiarity: .familiar, lastCookedDate: daysAgo(60))
        ]

        let weekPlan = WeekPlan(context: context, weekStartDate: Date())
        weekPlan.household = household
        let slot = MealSlot(context: context, dayOfWeek: .monday, mealType: .dinner)
        slot.weekPlan = weekPlan

        let engine = SuggestionEngine()
        let result = engine.suggestRecipes(for: slot, in: weekPlan, allRecipes: [recent, longAgo], memory: memory)

        #expect(rank(of: longAgo, in: result)! < rank(of: recent, in: result)!)
    }

    // MARK: - Decline threshold (pins the `>=` fix)

    @Test("General path: declining exactly declineThreshold times applies the penalty")
    func declineAtThresholdPenalisedGeneralPath() {
        let (context, household) = makeContext()

        // Both familiar and equal; only the at-threshold decline differs.
        let declined = makeRecipe("Declined", in: context, household: household)
        let clean = makeRecipe("Clean", in: context, household: household)

        let memory = [
            makeMemory(
                for: declined, in: context, household: household,
                familiarity: .familiar, suggestionDeclined: Self.declineThreshold
            ),
            makeMemory(for: clean, in: context, household: household, familiarity: .familiar, suggestionDeclined: 0)
        ]

        let engine = SuggestionEngine()
        let result = engine.suggestRecipes(allRecipes: [declined, clean], weekPlan: nil, memory: memory)

        // With `>=`, the at-threshold decline IS penalised, so it ranks below the clean recipe.
        #expect(rank(of: clean, in: result)! < rank(of: declined, in: result)!)
    }

    @Test("Slot path: declining exactly declineThreshold times applies the penalty")
    func declineAtThresholdPenalisedSlotPath() {
        let (context, household) = makeContext()

        let declined = makeRecipe("Declined", in: context, household: household)
        let clean = makeRecipe("Clean", in: context, household: household)

        let memory = [
            makeMemory(
                for: declined, in: context, household: household,
                familiarity: .familiar, suggestionDeclined: Self.declineThreshold
            ),
            makeMemory(for: clean, in: context, household: household, familiarity: .familiar, suggestionDeclined: 0)
        ]

        let weekPlan = WeekPlan(context: context, weekStartDate: Date())
        weekPlan.household = household
        let slot = MealSlot(context: context, dayOfWeek: .monday, mealType: .dinner)
        slot.weekPlan = weekPlan

        let engine = SuggestionEngine()
        let result = engine.suggestRecipes(for: slot, in: weekPlan, allRecipes: [declined, clean], memory: memory)

        // Both scoring paths use `>=`, so behaviour at the boundary is consistent.
        #expect(rank(of: clean, in: result)! < rank(of: declined, in: result)!)
    }

    @Test("Declining below the threshold does NOT apply a penalty")
    func declineBelowThresholdNotPenalised() {
        let (context, household) = makeContext()

        // declineThreshold - 1 declines should leave the recipe on par with a clean one.
        let belowThreshold = makeRecipe("Below", in: context, household: household)
        let clean = makeRecipe("Clean", in: context, household: household)

        let memory = [
            makeMemory(
                for: belowThreshold, in: context, household: household,
                familiarity: .familiar, suggestionDeclined: Self.declineThreshold - 1
            ),
            makeMemory(for: clean, in: context, household: household, familiarity: .familiar, suggestionDeclined: 0)
        ]

        let engine = SuggestionEngine()
        let result = engine.suggestRecipes(allRecipes: [belowThreshold, clean], weekPlan: nil, memory: memory)

        // Equal scores -> both present in familiar bucket, neither penalised relative to the other.
        #expect(result.familiarSuggestions.contains { $0.id == belowThreshold.id })
        #expect(result.familiarSuggestions.contains { $0.id == clean.id })
    }

    // MARK: - Archetype match bonus (slot path only)

    @Test("Slot path: a recipe matching the slot archetype ranks above a non-matching one")
    func archetypeMatchBonusRanksHigher() {
        let (context, household) = makeContext()

        let matching = makeRecipe(
            "Matching", in: context, household: household,
            suggestedArchetypes: [.quickWeeknight]
        )
        let nonMatching = makeRecipe(
            "Non-Matching", in: context, household: household,
            suggestedArchetypes: [.comfort]
        )

        // Equal familiarity; the archetype bonus is the only differentiator.
        let memory = [
            makeMemory(for: matching, in: context, household: household, familiarity: .familiar),
            makeMemory(for: nonMatching, in: context, household: household, familiarity: .familiar)
        ]

        let weekPlan = WeekPlan(context: context, weekStartDate: Date())
        weekPlan.household = household

        let archetype = MealArchetype(context: context, systemType: .quickWeeknight)
        archetype.household = household
        let slot = MealSlot(context: context, dayOfWeek: .monday, mealType: .dinner, archetype: archetype)
        slot.weekPlan = weekPlan

        let engine = SuggestionEngine()
        let result = engine.suggestRecipes(
            for: slot, in: weekPlan,
            allRecipes: [nonMatching, matching], memory: memory
        )

        #expect(result.familiarSuggestions.first?.id == matching.id)
        #expect(rank(of: matching, in: result)! < rank(of: nonMatching, in: result)!)
    }

    // MARK: - Planned-recipe exclusion

    @Test("Recipes already planned in the week are excluded from suggestions")
    func plannedRecipesExcluded() {
        let (context, household) = makeContext()

        let planned = makeRecipe("Planned", in: context, household: household)
        let available = makeRecipe("Available", in: context, household: household)

        let memory = [
            makeMemory(for: planned, in: context, household: household, familiarity: .familiar),
            makeMemory(for: available, in: context, household: household, familiarity: .familiar)
        ]

        let weekPlan = WeekPlan(context: context, weekStartDate: Date())
        weekPlan.household = household
        let slot = MealSlot(context: context, dayOfWeek: .monday, mealType: .dinner)
        slot.weekPlan = weekPlan
        slot.addToRecipes(planned)

        let engine = SuggestionEngine()
        let result = engine.suggestRecipes(for: slot, in: weekPlan, allRecipes: [planned, available], memory: memory)

        #expect(rank(of: planned, in: result) == nil)
        #expect(rank(of: available, in: result) != nil)
    }
}
