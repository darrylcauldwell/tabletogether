import Foundation
import CoreData

/// Simplified demo data seeder for tvOS screenshots.
/// Creates minimal data to populate the UI for App Store screenshots.
@MainActor
struct TVDemoDataSeeder {

    /// Seeds demo data into the managed object context for screenshots
    static func seedDemoData(into context: NSManagedObjectContext) {
        // Check if demo data already exists
        let recipeRequest = NSFetchRequest<Recipe>(entityName: "Recipe")
        if let existingRecipes = try? context.fetch(recipeRequest), !existingRecipes.isEmpty {
            return // Data already exists
        }

        // Create a household
        let household = Household(context: context, name: "Demo Household")

        // Create demo recipes
        let recipes = [
            createRecipe(context: context, title: "Mushroom Risotto", summary: "Creamy Italian rice dish with porcini mushrooms", prepTime: 15, cookTime: 35, tags: ["Italian", "Vegetarian"], household: household),
            createRecipe(context: context, title: "Grilled Salmon", summary: "Fresh Atlantic salmon with lemon herb butter", prepTime: 10, cookTime: 15, tags: ["Seafood", "Quick"], household: household),
            createRecipe(context: context, title: "Chicken Tikka Masala", summary: "Classic British-Indian curry with tender chicken", prepTime: 20, cookTime: 30, tags: ["Indian", "Curry"], household: household),
            createRecipe(context: context, title: "Sunday Roast", summary: "Traditional roast beef with Yorkshire puddings", prepTime: 30, cookTime: 120, tags: ["British", "Sunday"], household: household),
            createRecipe(context: context, title: "Vegetable Stir Fry", summary: "Quick and healthy Asian-inspired vegetables", prepTime: 10, cookTime: 10, tags: ["Asian", "Vegetarian", "Quick"], household: household),
            createRecipe(context: context, title: "Pasta Carbonara", summary: "Classic Roman pasta with eggs, cheese, and pancetta", prepTime: 10, cookTime: 15, tags: ["Italian", "Quick"], household: household)
        ]

        // Create a week plan
        let weekPlan = WeekPlan(
            context: context,
            weekStartDate: WeekPlan.normalizeToMonday(Date()),
            status: .active
        )
        weekPlan.household = household

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
                context: context,
                dayOfWeek: day,
                mealType: mealType,
                servingsPlanned: 4,
                customMealName: customName
            )
            if let recipe = recipe {
                slot.addToRecipes(recipe)
            }
            slot.weekPlan = weekPlan
            weekPlan.addToSlots(slot)
        }

        try? context.save()
    }

    private static func createRecipe(
        context: NSManagedObjectContext,
        title: String,
        summary: String,
        prepTime: Int,
        cookTime: Int,
        tags: [String],
        household: Household
    ) -> Recipe {
        let recipe = Recipe(
            context: context,
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
