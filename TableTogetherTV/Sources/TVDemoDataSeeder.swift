import Foundation
import SwiftData

/// Simplified demo data seeder for tvOS screenshots.
/// Creates minimal data to populate the UI for App Store screenshots.
@MainActor
struct TVDemoDataSeeder {

    /// Seeds demo data into the model context for screenshots
    static func seedDemoData(into context: ModelContext) {
        // Check if demo data already exists
        let recipeDescriptor = FetchDescriptor<Recipe>()
        if let existingRecipes = try? context.fetch(recipeDescriptor), !existingRecipes.isEmpty {
            return // Data already exists
        }

        // Create a household
        let household = Household(name: "Demo Household")
        context.insert(household)

        // Create demo recipes
        let recipes = [
            createRecipe(title: "Mushroom Risotto", summary: "Creamy Italian rice dish with porcini mushrooms", prepTime: 15, cookTime: 35, tags: ["Italian", "Vegetarian"], household: household),
            createRecipe(title: "Grilled Salmon", summary: "Fresh Atlantic salmon with lemon herb butter", prepTime: 10, cookTime: 15, tags: ["Seafood", "Quick"], household: household),
            createRecipe(title: "Chicken Tikka Masala", summary: "Classic British-Indian curry with tender chicken", prepTime: 20, cookTime: 30, tags: ["Indian", "Curry"], household: household),
            createRecipe(title: "Sunday Roast", summary: "Traditional roast beef with Yorkshire puddings", prepTime: 30, cookTime: 120, tags: ["British", "Sunday"], household: household),
            createRecipe(title: "Vegetable Stir Fry", summary: "Quick and healthy Asian-inspired vegetables", prepTime: 10, cookTime: 10, tags: ["Asian", "Vegetarian", "Quick"], household: household),
            createRecipe(title: "Pasta Carbonara", summary: "Classic Roman pasta with eggs, cheese, and pancetta", prepTime: 10, cookTime: 15, tags: ["Italian", "Quick"], household: household)
        ]

        for recipe in recipes {
            context.insert(recipe)
        }

        // Create a week plan
        let weekPlan = WeekPlan(
            weekStartDate: WeekPlan.normalizeToMonday(Date()),
            status: .active
        )
        weekPlan.household = household
        context.insert(weekPlan)

        // Create meal slots for the week
        let mealConfigs: [(DayOfWeek, MealType, Recipe?, String?)] = [
            (.monday, .dinner, recipes[0], nil),
            (.tuesday, .dinner, recipes[1], nil),
            (.wednesday, .dinner, recipes[4], nil),
            (.thursday, .dinner, recipes[2], nil),
            (.friday, .dinner, recipes[5], nil),
            (.saturday, .lunch, nil, "Pub Lunch"),
            (.saturday, .dinner, recipes[3], nil),
            (.sunday, .dinner, recipes[3], "Leftover Roast")
        ]

        for (day, mealType, recipe, customName) in mealConfigs {
            let slot = MealSlot(
                dayOfWeek: day,
                mealType: mealType,
                servingsPlanned: 4,
                recipes: recipe.map { [$0] } ?? [],
                customMealName: customName
            )
            slot.weekPlan = weekPlan
            weekPlan.slots.append(slot)
            context.insert(slot)
        }

        try? context.save()
    }

    private static func createRecipe(
        title: String,
        summary: String,
        prepTime: Int,
        cookTime: Int,
        tags: [String],
        household: Household
    ) -> Recipe {
        let recipe = Recipe(
            title: title,
            summary: summary,
            servings: 4,
            prepTimeMinutes: prepTime,
            cookTimeMinutes: cookTime,
            instructions: ["Demo recipe instructions for \(title)."],
            tags: tags,
            suggestedArchetypes: [.quickWeeknight]
        )
        recipe.household = household
        return recipe
    }
}
