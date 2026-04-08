import Testing
import Foundation
import CoreData
@testable import TableTogetherLib

@MainActor
@Suite("RecipeIngredientResolver Tests", .serialized)
struct RecipeIngredientResolverTests {

    /// Build a fresh in-memory Core Data context with a household for each test.
    private func makeContext() -> (NSManagedObjectContext, Household) {
        let context = PersistenceController(inMemory: true).container.viewContext
        let household = Household(context: context, name: "Test Household")
        return (context, household)
    }

    // MARK: - Exact match

    @Test("Resolves to existing ingredient by exact normalised name")
    func resolvesExactMatch() {
        let (context, household) = makeContext()
        let existing = Ingredient(context: context, name: "tomato")
        existing.household = household

        let resolver = RecipeIngredientResolver(context: context, household: household)
        let resolved = resolver.resolve("tomato")

        #expect(resolved === existing)
    }

    @Test("Resolves case-insensitively")
    func resolvesCaseInsensitively() {
        let (context, household) = makeContext()
        let existing = Ingredient(context: context, name: "Tomato")
        existing.household = household

        let resolver = RecipeIngredientResolver(context: context, household: household)
        let resolved = resolver.resolve("TOMATO")

        #expect(resolved === existing)
    }

    @Test("Resolves with surrounding whitespace")
    func resolvesWithWhitespace() {
        let (context, household) = makeContext()
        let existing = Ingredient(context: context, name: "tomato")
        existing.household = household

        let resolver = RecipeIngredientResolver(context: context, household: household)
        let resolved = resolver.resolve("   tomato\n  ")

        #expect(resolved === existing)
    }

    // MARK: - Alias match

    @Test("Resolves via userAliases")
    func resolvesViaAlias() {
        let (context, household) = makeContext()
        let canonical = Ingredient(context: context, name: "spring onion")
        canonical.household = household
        canonical.addAlias("scallion")
        canonical.addAlias("green onion")

        let resolver = RecipeIngredientResolver(context: context, household: household)

        #expect(resolver.resolve("scallion") === canonical)
        #expect(resolver.resolve("green onion") === canonical)
        #expect(resolver.resolve("spring onion") === canonical)
    }

    @Test("Alias matching is case-insensitive after normalisation")
    func resolvesAliasCaseInsensitively() {
        let (context, household) = makeContext()
        let canonical = Ingredient(context: context, name: "coriander")
        canonical.household = household
        canonical.addAlias("cilantro")

        let resolver = RecipeIngredientResolver(context: context, household: household)

        #expect(resolver.resolve("CILANTRO") === canonical)
        #expect(resolver.resolve("  Cilantro  ") === canonical)
    }

    // MARK: - Create new

    @Test("Creates a new ingredient on first resolve of an unknown name")
    func createsNewWhenUnknown() {
        let (context, household) = makeContext()
        let resolver = RecipeIngredientResolver(context: context, household: household)

        let resolved = resolver.resolve("garlic")

        #expect(resolved != nil)
        #expect(resolved?.normalizedName == "garlic")
        #expect(resolved?.name == "garlic")
        #expect(resolved?.household === household)
        #expect(resolved?.isUserCreated == false)
    }

    @Test("New ingredient preserves original display casing")
    func newIngredientPreservesCasing() {
        let (context, household) = makeContext()
        let resolver = RecipeIngredientResolver(context: context, household: household)

        let resolved = resolver.resolve("Sea Salt")

        #expect(resolved?.name == "Sea Salt")          // display preserved
        #expect(resolved?.normalizedName == "sea salt") // normalised stored
    }

    @Test("New ingredient trims whitespace from display name")
    func newIngredientTrimsWhitespace() {
        let (context, household) = makeContext()
        let resolver = RecipeIngredientResolver(context: context, household: household)

        let resolved = resolver.resolve("  Olive Oil  \n")

        #expect(resolved?.name == "Olive Oil")
        #expect(resolved?.normalizedName == "olive oil")
    }

    // MARK: - Cache behaviour

    @Test("Repeated resolves of the same name return the same instance")
    func cacheReturnsSameInstance() {
        let (context, household) = makeContext()
        let resolver = RecipeIngredientResolver(context: context, household: household)

        let first = resolver.resolve("flour")
        let second = resolver.resolve("flour")
        let third = resolver.resolve("FLOUR")

        #expect(first === second)
        #expect(first === third)
    }

    @Test("Resolving N distinct names creates N distinct ingredients")
    func distinctNamesCreateDistinctIngredients() {
        let (context, household) = makeContext()
        let resolver = RecipeIngredientResolver(context: context, household: household)

        let a = resolver.resolve("salt")
        let b = resolver.resolve("pepper")
        let c = resolver.resolve("sugar")

        #expect(a != nil && b != nil && c != nil)
        #expect(a !== b)
        #expect(b !== c)
        #expect(a !== c)
        #expect(resolver.cacheCount == 3)
    }

    @Test("Cache count reflects only unique normalised names")
    func cacheCountUnique() {
        let (context, household) = makeContext()
        let resolver = RecipeIngredientResolver(context: context, household: household)

        _ = resolver.resolve("Tomato")
        _ = resolver.resolve("tomato")
        _ = resolver.resolve("TOMATO")
        _ = resolver.resolve("  tomato  ")

        #expect(resolver.cacheCount == 1)
    }

    // MARK: - Empty / nil-like input

    @Test("Empty input returns nil")
    func emptyInputReturnsNil() {
        let (context, household) = makeContext()
        let resolver = RecipeIngredientResolver(context: context, household: household)

        #expect(resolver.resolve("") == nil)
        #expect(resolver.resolve("   ") == nil)
        #expect(resolver.resolve("\n\t") == nil)
    }

    // MARK: - Household isolation

    @Test("Resolver scoped to household A does not see ingredients in household B")
    func householdIsolation() {
        let context = PersistenceController(inMemory: true).container.viewContext
        let householdA = Household(context: context, name: "A")
        let householdB = Household(context: context, name: "B")

        let inB = Ingredient(context: context, name: "tomato")
        inB.household = householdB

        let resolverA = RecipeIngredientResolver(context: context, household: householdA)
        let resolved = resolverA.resolve("tomato")

        // resolverA should NOT find the ingredient in household B; it creates a new one
        #expect(resolved !== inB)
        #expect(resolved?.household === householdA)
    }

    // MARK: - Prewarm

    @Test("Prewarm picks up existing aliases at init time")
    func prewarmIncludesAliases() {
        let (context, household) = makeContext()
        let canonical = Ingredient(context: context, name: "aubergine")
        canonical.household = household
        canonical.addAlias("eggplant")
        canonical.addAlias("brinjal")

        let resolver = RecipeIngredientResolver(context: context, household: household)

        // Cache should contain canonical + 2 aliases
        #expect(resolver.cacheCount == 3)
        #expect(resolver.resolve("eggplant") === canonical)
        #expect(resolver.resolve("brinjal") === canonical)
        #expect(resolver.resolve("aubergine") === canonical)
    }
}
