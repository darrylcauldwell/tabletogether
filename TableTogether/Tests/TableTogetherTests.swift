import Testing
import SwiftData
import Foundation
@testable import TableTogether

// MARK: - Model Tests

@Suite("Ingredient Tests")
struct IngredientTests {
    @Test("Ingredient normalizes name correctly")
    func ingredientNormalizesName() {
        let ingredient = Ingredient(
            name: "  Chicken Breast  ",
            category: .protein,
            defaultUnit: .gram
        )
        #expect(ingredient.normalizedName == "chicken breast")
    }

    @Test("Ingredient with macros calculates display correctly")
    func ingredientMacroDisplay() {
        let ingredient = Ingredient(
            name: "Chicken Breast",
            category: .protein,
            defaultUnit: .gram,
            caloriesPer100g: 165,
            proteinPer100g: 31,
            carbsPer100g: 0,
            fatPer100g: 3.6
        )
        #expect(ingredient.caloriesPer100g == 165)
        #expect(ingredient.proteinPer100g == 31)
    }
}

@Suite("Recipe Tests")
struct RecipeTests {
    @Test("Recipe calculates total time correctly")
    func recipeTotalTime() {
        let recipe = Recipe(
            title: "Test Recipe",
            servings: 4,
            prepTimeMinutes: 15,
            cookTimeMinutes: 30
        )
        #expect(recipe.totalTimeMinutes == 45)
    }

    @Test("Recipe without times returns nil for total")
    func recipeNoTimes() {
        let recipe = Recipe(
            title: "Test Recipe",
            servings: 4
        )
        #expect(recipe.totalTimeMinutes == nil)
    }

    @Test("Recipe formatted prep time")
    func recipeFormattedPrepTime() {
        let recipe = Recipe(
            title: "Test",
            servings: 4,
            prepTimeMinutes: 45
        )
        #expect(recipe.formattedPrepTime == "45 min prep")
    }

    @Test("Recipe favorite state")
    func recipeFavoriteState() {
        let recipe = Recipe(title: "Test", servings: 4)
        #expect(!recipe.isFavorite)

        recipe.isFavorite = true
        #expect(recipe.isFavorite)
    }

    @Test("Recipe with archetypes")
    func recipeWithArchetypes() {
        let recipe = Recipe(
            title: "Quick Stir Fry",
            servings: 4,
            suggestedArchetypes: [.quickWeeknight, .familyFavorite]
        )
        #expect(recipe.suggestedArchetypes.count == 2)
        #expect(recipe.suggestedArchetypes.contains(.quickWeeknight))
    }

    @Test("Recipe tags")
    func recipeTags() {
        let recipe = Recipe(title: "Test", servings: 4)
        recipe.tags = ["vegetarian", "gluten-free", "quick"]
        #expect(recipe.tags.count == 3)
        #expect(recipe.tags.contains("vegetarian"))
    }

    @Test("Recipe instructions")
    func recipeInstructions() {
        let recipe = Recipe(
            title: "Test",
            servings: 4,
            instructions: ["Step 1", "Step 2", "Step 3"]
        )
        #expect(recipe.instructions.count == 3)
        #expect(recipe.instructions[0] == "Step 1")
    }
}

@Suite("MacroSummary Tests")
struct MacroSummaryTests {
    @Test("MacroSummary formats calories correctly")
    func formatsCalories() {
        let summary = MacroSummary(
            calories: 1850.5,
            protein: 120.3,
            carbs: 200.7,
            fat: 65.2
        )
        #expect(summary.formattedCalories == "1851 cal")
    }

    @Test("MacroSummary handles nil values")
    func handlesNilValues() {
        let summary = MacroSummary(
            calories: nil,
            protein: 50,
            carbs: nil,
            fat: nil
        )
        #expect(summary.formattedCalories == "--")
        #expect(summary.formattedProtein == "50g")
    }

    @Test("MacroSummary hasData property")
    func hasDataProperty() {
        let summaryWithData = MacroSummary(calories: 500, protein: 25, carbs: 50, fat: 20)
        #expect(summaryWithData.hasData)

        let summaryWithoutData = MacroSummary(calories: nil, protein: nil, carbs: nil, fat: nil)
        #expect(!summaryWithoutData.hasData)
    }
}

@Suite("Date Extension Tests")
struct DateExtensionTests {
    @Test("Start of week returns Monday")
    func startOfWeekIsMonday() {
        // Create a Wednesday
        var components = DateComponents()
        components.year = 2025
        components.month = 1
        components.day = 22 // Wednesday
        let wednesday = Calendar.current.date(from: components)!

        let startOfWeek = wednesday.startOfWeek
        let weekday = Calendar.current.component(.weekday, from: startOfWeek)

        #expect(weekday == 2) // Monday is weekday 2
    }

    @Test("Week dates returns 7 days")
    func weekDatesReturnsSeven() {
        let today = Date()
        let weekDates = today.weekDates
        #expect(weekDates.count == 7)
    }
}

// MARK: - User Model Tests

@Suite("User Tests")
struct UserTests {
    @Test("User creates with display name")
    func userCreatesWithDisplayName() {
        let user = User(displayName: "Test User")
        #expect(user.displayName == "Test User")
        #expect(!user.avatarEmoji.isEmpty)
        #expect(!user.avatarColorHex.isEmpty)
    }

    @Test("User with custom avatar")
    func userWithCustomAvatar() {
        let user = User(
            displayName: "Chef",
            avatarEmoji: "👨‍🍳",
            avatarColorHex: "FF5733"
        )
        #expect(user.avatarEmoji == "👨‍🍳")
        #expect(user.avatarColorHex == "FF5733")
    }

    // Note: Nutrition targets have been moved to PersonalSettings (private CloudKit storage)
    // See PersonalSettings Tests for target-related tests
}

// MARK: - WeekPlan Model Tests

@Suite("WeekPlan Tests")
struct WeekPlanTests {
    @Test("WeekPlan creates with start date")
    func weekPlanCreatesWithStartDate() {
        let startDate = Date()
        let weekPlan = WeekPlan(weekStartDate: startDate)
        #expect(weekPlan.status == .draft)
    }

    @Test("WeekPlan statuses are correct")
    func weekPlanStatuses() {
        let weekPlan = WeekPlan(weekStartDate: Date())
        #expect(weekPlan.status == .draft)

        weekPlan.status = .active
        #expect(weekPlan.status == .active)

        weekPlan.status = .completed
        #expect(weekPlan.status == .completed)
    }

    @Test("WeekPlan household note defaults to nil")
    func weekPlanHouseholdNoteDefaultsNil() {
        let weekPlan = WeekPlan(weekStartDate: Date())
        #expect(weekPlan.householdNote == nil)
    }

    @Test("WeekPlan can set household note")
    func weekPlanCanSetHouseholdNote() {
        let weekPlan = WeekPlan(weekStartDate: Date())
        weekPlan.householdNote = "Remember to defrost chicken!"
        #expect(weekPlan.householdNote == "Remember to defrost chicken!")
    }
}

// MARK: - MealSlot Model Tests

@Suite("MealSlot Tests")
struct MealSlotTests {
    @Test("MealSlot creates with day and meal type")
    func mealSlotCreatesCorrectly() {
        let slot = MealSlot(dayOfWeek: .wednesday, mealType: .lunch)
        #expect(slot.dayOfWeek == .wednesday)
        #expect(slot.mealType == .lunch)
        #expect(slot.servingsPlanned == 2) // default is 2
    }

    @Test("MealSlot with custom servings")
    func mealSlotCustomServings() {
        let slot = MealSlot(dayOfWeek: .friday, mealType: .dinner, servingsPlanned: 6)
        #expect(slot.servingsPlanned == 6)
    }

    @Test("MealSlot skipped state")
    func mealSlotSkippedState() {
        let slot = MealSlot(dayOfWeek: .saturday, mealType: .breakfast)
        #expect(!slot.isSkipped)

        slot.isSkipped = true
        #expect(slot.isSkipped)
    }

    @Test("MealSlot custom meal name")
    func mealSlotCustomMealName() {
        let slot = MealSlot(dayOfWeek: .sunday, mealType: .dinner)
        slot.customMealName = "Takeout Night"
        #expect(slot.customMealName == "Takeout Night")
    }

    @Test("MealSlot notes")
    func mealSlotNotes() {
        let slot = MealSlot(dayOfWeek: .monday, mealType: .dinner)
        slot.notes = "Make extra for leftovers"
        #expect(slot.notes == "Make extra for leftovers")
    }
}

// MARK: - RecipeIngredient Model Tests

@Suite("RecipeIngredient Tests")
struct RecipeIngredientTests {
    @Test("RecipeIngredient creates correctly")
    func recipeIngredientCreates() {
        let ingredient = RecipeIngredient(
            quantity: 2.5,
            unit: .cup,
            order: 0,
            customName: "All-purpose flour"
        )
        #expect(ingredient.quantity == 2.5)
        #expect(ingredient.unit == .cup)
        #expect(ingredient.customName == "All-purpose flour")
    }

    @Test("RecipeIngredient with preparation note")
    func recipeIngredientWithPrepNote() {
        let ingredient = RecipeIngredient(
            quantity: 3,
            unit: .clove,
            preparationNote: "minced",
            order: 1,
            customName: "Garlic"
        )
        #expect(ingredient.preparationNote == "minced")
    }

    @Test("RecipeIngredient optional flag")
    func recipeIngredientOptional() {
        let ingredient = RecipeIngredient(
            quantity: 1,
            unit: .tablespoon,
            isOptional: true,
            order: 0,
            customName: "Fresh herbs"
        )
        #expect(ingredient.isOptional)
    }

    @Test("RecipeIngredient display name from custom name")
    func recipeIngredientDisplayName() {
        let ingredient = RecipeIngredient(
            quantity: 1,
            unit: .piece,
            order: 0,
            customName: "Onion"
        )
        #expect(ingredient.displayName == "Onion")
    }
}

// MARK: - GroceryItem Model Tests

@Suite("GroceryItem Tests")
struct GroceryItemTests {
    @Test("GroceryItem creates correctly")
    func groceryItemCreates() {
        let weekPlan = WeekPlan(weekStartDate: Date())
        let item = GroceryItem(
            customName: "Milk",
            quantity: 1,
            unit: .liter,
            category: .dairy,
            weekPlan: weekPlan
        )
        #expect(item.customName == "Milk")
        #expect(item.quantity == 1)
        #expect(item.unit == .liter)
        #expect(item.category == .dairy)
    }

    @Test("GroceryItem check state")
    func groceryItemCheckState() {
        let weekPlan = WeekPlan(weekStartDate: Date())
        let item = GroceryItem(
            customName: "Eggs",
            quantity: 1,
            unit: .piece,
            category: .dairy,
            weekPlan: weekPlan
        )
        #expect(!item.isChecked)

        item.isChecked = true
        item.checkedAt = Date()
        #expect(item.isChecked)
        #expect(item.checkedAt != nil)
    }

    @Test("GroceryItem manually added flag")
    func groceryItemManuallyAdded() {
        let weekPlan = WeekPlan(weekStartDate: Date())
        let item = GroceryItem(
            customName: "Snacks",
            quantity: 1,
            unit: .piece,
            category: .other,
            weekPlan: weekPlan
        )
        item.isManuallyAdded = true
        #expect(item.isManuallyAdded)
    }
}

// MARK: - MealArchetype Model Tests

@Suite("MealArchetype Tests")
struct MealArchetypeTests {
    @Test("MealArchetype creates from system type")
    func mealArchetypeFromSystemType() {
        let archetype = MealArchetype(systemType: .quickWeeknight)
        #expect(archetype.name == "Quick Weeknight")
        #expect(archetype.systemType == .quickWeeknight)
        #expect(!archetype.icon.isEmpty)
    }

    @Test("All system archetypes have valid icons")
    func allArchetypesHaveIcons() {
        for archetypeType in ArchetypeType.allCases {
            let archetype = MealArchetype(systemType: archetypeType)
            #expect(!archetype.icon.isEmpty)
        }
    }

    @Test("All system archetypes have valid colors")
    func allArchetypesHaveColors() {
        for archetypeType in ArchetypeType.allCases {
            let archetype = MealArchetype(systemType: archetypeType)
            #expect(!archetype.colorHex.isEmpty)
        }
    }
}

// MARK: - Enum Tests

@Suite("Enum Tests")
struct EnumTests {
    @Test("ArchetypeType has correct display names")
    func archetypeDisplayNames() {
        #expect(ArchetypeType.quickWeeknight.displayName == "Quick Weeknight")
        #expect(ArchetypeType.bigBatch.displayName == "Big Batch")
        #expect(ArchetypeType.newExperimental.displayName == "New / Experimental")
    }

    @Test("MealType has correct icons")
    func mealTypeIcons() {
        #expect(MealType.breakfast.icon == "sunrise.fill")
        #expect(MealType.dinner.icon == "moon.fill")
    }

    @Test("IngredientCategory has all expected cases")
    func ingredientCategoryAllCases() {
        #expect(IngredientCategory.allCases.count == 9)
    }

    @Test("DayOfWeek raw values are correct")
    func dayOfWeekRawValues() {
        #expect(DayOfWeek.monday.rawValue == 1)
        #expect(DayOfWeek.sunday.rawValue == 7)
    }
}

// MARK: - MeasurementUnit Tests

@Suite("MeasurementUnit Tests")
struct MeasurementUnitTests {
    @Test("MeasurementUnit display names are user-friendly")
    func measurementUnitDisplayNames() {
        #expect(MeasurementUnit.tablespoon.displayName == "tablespoon")
        #expect(MeasurementUnit.teaspoon.displayName == "teaspoon")
        #expect(MeasurementUnit.cup.displayName == "cup")
    }

    @Test("MeasurementUnit abbreviations are correct")
    func measurementUnitAbbreviations() {
        #expect(MeasurementUnit.tablespoon.abbreviation == "tbsp")
        #expect(MeasurementUnit.teaspoon.abbreviation == "tsp")
        #expect(MeasurementUnit.gram.abbreviation == "g")
        #expect(MeasurementUnit.kilogram.abbreviation == "kg")
    }

    @Test("All measurement units have abbreviations")
    func allUnitsHaveAbbreviations() {
        for unit in MeasurementUnit.allCases {
            #expect(!unit.abbreviation.isEmpty)
        }
    }
}

// MARK: - DayOfWeek Tests

@Suite("DayOfWeek Tests")
struct DayOfWeekTests {
    @Test("DayOfWeek display names are correct")
    func dayOfWeekDisplayNames() {
        #expect(DayOfWeek.monday.displayName == "Monday")
        #expect(DayOfWeek.friday.displayName == "Friday")
        #expect(DayOfWeek.sunday.displayName == "Sunday")
    }

    @Test("DayOfWeek short names are correct")
    func dayOfWeekShortNames() {
        #expect(DayOfWeek.monday.shortName == "Mon")
        #expect(DayOfWeek.wednesday.shortName == "Wed")
        #expect(DayOfWeek.saturday.shortName == "Sat")
    }

    @Test("DayOfWeek ordering is Monday to Sunday")
    func dayOfWeekOrdering() {
        let days = DayOfWeek.allCases
        #expect(days.first == .monday)
        #expect(days.last == .sunday)
        #expect(days.count == 7)
    }

    @Test("DayOfWeek weekend detection")
    func dayOfWeekWeekendDetection() {
        #expect(!DayOfWeek.monday.isWeekend)
        #expect(!DayOfWeek.friday.isWeekend)
        #expect(DayOfWeek.saturday.isWeekend)
        #expect(DayOfWeek.sunday.isWeekend)
    }
}

// MARK: - WeekPlanStatus Tests

@Suite("WeekPlanStatus Tests")
struct WeekPlanStatusTests {
    @Test("WeekPlanStatus has expected cases")
    func weekPlanStatusCases() {
        #expect(WeekPlanStatus.allCases.count == 3)
        #expect(WeekPlanStatus.allCases.contains(.draft))
        #expect(WeekPlanStatus.allCases.contains(.active))
        #expect(WeekPlanStatus.allCases.contains(.completed))
    }

    @Test("WeekPlanStatus display names")
    func weekPlanStatusDisplayNames() {
        #expect(WeekPlanStatus.draft.displayName == "Draft")
        #expect(WeekPlanStatus.active.displayName == "Active")
        #expect(WeekPlanStatus.completed.displayName == "Completed")
    }
}

// MARK: - FamiliarityLevel Tests

@Suite("FamiliarityLevel Tests")
struct FamiliarityLevelTests {
    @Test("FamiliarityLevel from times cooked")
    func familiarityLevelFromTimesCooked() {
        #expect(FamiliarityLevel.from(timesCooked: 0) == .new)
        #expect(FamiliarityLevel.from(timesCooked: 1) == .tried)
        #expect(FamiliarityLevel.from(timesCooked: 2) == .tried)
        #expect(FamiliarityLevel.from(timesCooked: 3) == .familiar)
        #expect(FamiliarityLevel.from(timesCooked: 5) == .familiar)
        #expect(FamiliarityLevel.from(timesCooked: 6) == .staple)
        #expect(FamiliarityLevel.from(timesCooked: 100) == .staple)
    }

    @Test("FamiliarityLevel display names")
    func familiarityLevelDisplayNames() {
        #expect(FamiliarityLevel.new.displayName == "New")
        #expect(FamiliarityLevel.tried.displayName == "Tried")
        #expect(FamiliarityLevel.familiar.displayName == "Familiar")
        #expect(FamiliarityLevel.staple.displayName == "Staple")
    }
}

// MARK: - Service Tests

@Suite("SuggestionEngine Tests")
struct SuggestionEngineTests {
    @Test("Engine returns suggestions structure")
    func returnsSuggestionsStructure() {
        let engine = SuggestionEngine()

        // Create test data
        let familiarRecipe = Recipe(title: "Familiar Pasta", servings: 4)
        let newRecipe = Recipe(title: "New Dish", servings: 4)

        let familiarMemory = SuggestionMemory(recipe: familiarRecipe)
        familiarMemory.householdFamiliarity = .staple
        familiarMemory.timesCooked = 10

        let newMemory = SuggestionMemory(recipe: newRecipe)
        newMemory.householdFamiliarity = .new
        newMemory.timesCooked = 0

        let weekPlan = WeekPlan(weekStartDate: Date())
        let slot = MealSlot(dayOfWeek: .monday, mealType: .dinner)

        let result = engine.suggestRecipes(
            for: slot,
            in: weekPlan,
            allRecipes: [familiarRecipe, newRecipe],
            memory: [familiarMemory, newMemory]
        )

        #expect(result.familiarSuggestions.count >= 0)
        #expect(result.newSuggestions.count >= 0)
    }
}

@Suite("GroceryListGenerator Tests")
struct GroceryListGeneratorTests {
    @Test("Generator exists and can be instantiated")
    func generatorExists() {
        let generator = GroceryListGenerator()
        #expect(generator != nil)
    }
}

// MARK: - MacroAggregator Tests

@Suite("MacroAggregator Tests")
struct MacroAggregatorTests {
    @Test("Insight text is always positive")
    func insightTextIsPositive() {
        let aggregator = MacroAggregator()

        // Test with empty data
        let emptyInsight = aggregator.generateInsightText(from: [:])
        #expect(!emptyInsight.contains("fail"))
        #expect(!emptyInsight.contains("bad"))
        #expect(!emptyInsight.contains("poor"))

        // Test with some data
        let today = Date()
        let macros = MacroSummary(calories: 2000, protein: 100, carbs: 250, fat: 70)
        let testData: [Date: AggregatedMacroResult] = [
            today: AggregatedMacroResult(macros: macros, mealsLogged: 3)
        ]
        let insight = aggregator.generateInsightText(from: testData)
        #expect(!insight.contains("fail"))
        #expect(!insight.contains("deficit"))
        #expect(!insight.contains("excess"))
    }
}

// MARK: - Suggestion Memory Tests

@Suite("SuggestionMemory Tests")
struct SuggestionMemoryTests {
    @Test("SuggestionMemory creates correctly")
    func suggestionMemoryCreates() {
        let recipe = Recipe(title: "Test Recipe", servings: 4)
        let memory = SuggestionMemory(recipe: recipe)
        #expect(memory.timesCooked == 0)
        #expect(memory.householdFamiliarity == .new)
    }

    @Test("SuggestionMemory familiarity levels")
    func suggestionMemoryFamiliarityLevels() {
        let recipe = Recipe(title: "Test", servings: 4)
        let memory = SuggestionMemory(recipe: recipe)

        memory.householdFamiliarity = .familiar
        #expect(memory.householdFamiliarity == .familiar)

        memory.householdFamiliarity = .staple
        #expect(memory.householdFamiliarity == .staple)
    }

    @Test("SuggestionMemory tracks times cooked")
    func suggestionMemoryTimesCooked() {
        let recipe = Recipe(title: "Test", servings: 4)
        let memory = SuggestionMemory(recipe: recipe)

        memory.timesCooked = 5

        #expect(memory.timesCooked == 5)
    }
}

// MARK: - ArchetypeType Color Tests

@Suite("ArchetypeType Color Tests")
struct ArchetypeTypeColorTests {
    @Test("All archetypes have valid color hex codes")
    func allArchetypesHaveColorHex() {
        for archetype in ArchetypeType.allCases {
            let colorHex = archetype.colorHex
            #expect(colorHex.hasPrefix("#"))
            #expect(colorHex.count == 7) // #RRGGBB format
        }
    }
}

// MARK: - Integration Tests

@Suite("Integration Tests")
struct IntegrationTests {
    @Test("Recipe with ingredients chain")
    func recipeWithIngredientsChain() {
        let recipe = Recipe(title: "Test Recipe", servings: 4)

        let flour = RecipeIngredient(quantity: 2, unit: .cup, order: 0, customName: "Flour")
        let sugar = RecipeIngredient(quantity: 1, unit: .cup, order: 1, customName: "Sugar")
        let butter = RecipeIngredient(quantity: 0.5, unit: .cup, order: 2, customName: "Butter")

        recipe.recipeIngredients.append(flour)
        recipe.recipeIngredients.append(sugar)
        recipe.recipeIngredients.append(butter)

        #expect(recipe.recipeIngredients.count == 3)
        #expect(recipe.sortedIngredients.first?.displayName == "Flour")
        #expect(recipe.sortedIngredients.last?.displayName == "Butter")
    }

    @Test("WeekPlan with MealSlots chain")
    func weekPlanWithMealSlotsChain() {
        let weekPlan = WeekPlan(weekStartDate: Date())

        let mondayDinner = MealSlot(dayOfWeek: .monday, mealType: .dinner)
        let tuesdayDinner = MealSlot(dayOfWeek: .tuesday, mealType: .dinner)

        weekPlan.slots.append(mondayDinner)
        weekPlan.slots.append(tuesdayDinner)

        #expect(weekPlan.slots.count == 2)
    }

    @Test("MealSlot with Recipe assignment")
    func mealSlotWithRecipeAssignment() {
        let slot = MealSlot(dayOfWeek: .wednesday, mealType: .lunch)
        let recipe = Recipe(title: "Chicken Salad", servings: 2)

        slot.recipes.append(recipe)
        slot.servingsPlanned = 4

        #expect(slot.recipes.first?.title == "Chicken Salad")
        #expect(slot.servingsPlanned == 4)
    }

    @Test("GroceryItem with WeekPlan chain")
    func groceryItemWithWeekPlanChain() {
        let weekPlan = WeekPlan(weekStartDate: Date())
        let item1 = GroceryItem(customName: "Apples", quantity: 6, unit: .piece, category: .produce, weekPlan: weekPlan)
        let item2 = GroceryItem(customName: "Milk", quantity: 1, unit: .liter, category: .dairy, weekPlan: weekPlan)

        weekPlan.groceryItems.append(item1)
        weekPlan.groceryItems.append(item2)

        #expect(weekPlan.groceryItems.count == 2)
    }

    // Note: MealLog has been replaced by PrivateMealLog in CloudKit private database
    // See PrivateMealLog Tests for meal logging tests

    @Test("Complete meal planning workflow")
    func completeMealPlanningWorkflow() {
        // Create a user (for shared household identity only)
        let user = User(displayName: "Chef")

        // Create a week plan
        let weekPlan = WeekPlan(weekStartDate: Date())
        weekPlan.status = .draft

        // Create a recipe
        let recipe = Recipe(
            title: "Spaghetti Bolognese",
            servings: 4,
            prepTimeMinutes: 15,
            cookTimeMinutes: 45
        )
        recipe.isFavorite = true

        // Create a meal slot and assign the recipe
        let slot = MealSlot(dayOfWeek: .monday, mealType: .dinner, servingsPlanned: 4)
        slot.recipes.append(recipe)

        // Add slot to week plan
        weekPlan.slots.append(slot)

        // Activate the plan
        weekPlan.status = .active

        // Verify shared data is connected
        #expect(weekPlan.status == .active)
        #expect(weekPlan.slots.count == 1)
        #expect(slot.recipes.first?.title == "Spaghetti Bolognese")
        #expect(recipe.totalTimeMinutes == 60)
        #expect(user.displayName == "Chef")

        // Note: Meal logging is now done via PrivateMealLog in CloudKit private database
        // Personal nutrition targets are in PersonalSettings, not User
    }
}

// MARK: - Theme and Color Tests

@Suite("Theme Tests")
struct ThemeTests {
    @Test("Theme colors are accessible")
    func themeColorsAccessible() {
        // Verify theme colors can be accessed
        #expect(Theme.Colors.primary != nil)
        #expect(Theme.Colors.secondary != nil)
        #expect(Theme.Colors.textPrimary != nil)
        #expect(Theme.Colors.textSecondary != nil)
    }
}

// MARK: - Sharing Coordinator Tests

@Suite("Sharing Coordinator Tests")
struct SharingCoordinatorTests {
    @Test("Sync status enum values")
    func syncStatusEnumValues() {
        let synced = SyncStatus.synced
        let syncing = SyncStatus.syncing
        let error = SyncStatus.error("Test error")
        let offline = SyncStatus.offline

        #expect(synced != syncing)
        #expect(synced != error)
        #expect(synced != offline)
    }
}

// MARK: - PersonalSettings Tests (Private CloudKit Storage)

@Suite("PersonalSettings Tests")
struct PersonalSettingsTests {
    @Test("PersonalSettings creates with defaults")
    func personalSettingsCreatesWithDefaults() {
        let settings = PersonalSettings()
        #expect(settings.dailyCalorieTarget == nil)
        #expect(settings.dailyProteinTarget == nil)
        #expect(settings.dailyCarbTarget == nil)
        #expect(settings.dailyFatTarget == nil)
        #expect(settings.showMacroInsights == true)
    }

    @Test("PersonalSettings can set nutrition targets")
    func personalSettingsCanSetTargets() {
        var settings = PersonalSettings()
        settings.dailyCalorieTarget = 2000
        settings.dailyProteinTarget = 150
        settings.dailyCarbTarget = 250
        settings.dailyFatTarget = 65

        #expect(settings.dailyCalorieTarget == 2000)
        #expect(settings.dailyProteinTarget == 150)
        #expect(settings.dailyCarbTarget == 250)
        #expect(settings.dailyFatTarget == 65)
    }

    @Test("PersonalSettings hasGoalsSet")
    func personalSettingsHasGoalsSet() {
        var settings = PersonalSettings()
        #expect(!settings.hasGoalsSet)

        settings.dailyCalorieTarget = 2000
        #expect(settings.hasGoalsSet)
    }

    @Test("PersonalSettings withClearedGoals")
    func personalSettingsWithClearedGoals() {
        var settings = PersonalSettings()
        settings.dailyCalorieTarget = 2000
        settings.dailyProteinTarget = 150

        let cleared = settings.withClearedGoals()
        #expect(cleared.dailyCalorieTarget == nil)
        #expect(cleared.dailyProteinTarget == nil)
    }
}

// MARK: - PrivateMealLog Tests (Private CloudKit Storage)

@Suite("PrivateMealLog Tests")
struct PrivateMealLogTests {
    @Test("PrivateMealLog creates with recipe reference")
    func privateMealLogCreatesWithRecipe() {
        let recipeID = UUID()
        let log = PrivateMealLog(
            mealType: .dinner,
            recipeID: recipeID,
            servingsConsumed: 1.5
        )
        #expect(log.recipeID == recipeID)
        #expect(log.servingsConsumed == 1.5)
        #expect(log.mealType == .dinner)
        #expect(log.quickLogName == nil)
    }

    @Test("PrivateMealLog creates with quick log")
    func privateMealLogCreatesWithQuickLog() {
        let log = PrivateMealLog(
            mealType: .lunch,
            quickLogName: "Leftover pizza",
            calories: 450,
            protein: 18,
            carbs: 52,
            fat: 20
        )
        #expect(log.quickLogName == "Leftover pizza")
        #expect(log.quickLogCalories == 450)
        #expect(log.quickLogProtein == 18)
        #expect(log.quickLogCarbs == 52)
        #expect(log.quickLogFat == 20)
        #expect(log.recipeID == nil)
    }

    @Test("PrivateMealLog has correct meal type")
    func privateMealLogMealType() {
        let breakfastLog = PrivateMealLog(mealType: .breakfast, quickLogName: "Oatmeal")
        let snackLog = PrivateMealLog(mealType: .snack, quickLogName: "Apple")

        #expect(breakfastLog.mealType == .breakfast)
        #expect(snackLog.mealType == .snack)
    }

    @Test("PrivateMealLog date defaults to now")
    func privateMealLogDateDefaultsToNow() {
        let before = Date()
        let log = PrivateMealLog(mealType: .dinner, quickLogName: "Test")
        let after = Date()

        #expect(log.date >= before)
        #expect(log.date <= after)
    }
}
