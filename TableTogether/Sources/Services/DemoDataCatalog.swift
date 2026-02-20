import Foundation
import SwiftData

/// Static catalog containing all demo data definitions.
/// All demo data uses predictable UUIDs starting with "DE000000-" for easy identification and removal.
enum DemoDataCatalog {

    // MARK: - UUID Prefix

    /// All demo data UUIDs start with this prefix for easy identification
    static let uuidPrefix = "DE000000-"

    /// Checks if a UUID is demo data
    static func isDemoData(_ uuid: UUID) -> Bool {
        uuid.uuidString.hasPrefix(uuidPrefix)
    }

    // MARK: - Demo Users

    struct DemoUser {
        let id: UUID
        let displayName: String
        let avatarEmoji: String
        let avatarColorHex: String
    }

    static let users: [DemoUser] = [
        DemoUser(
            id: UUID(uuidString: "DE000000-0001-0000-0000-000000000001")!,
            displayName: "Sarah",
            avatarEmoji: "",
            avatarColorHex: "34C759" // Apple Green
        ),
        DemoUser(
            id: UUID(uuidString: "DE000000-0001-0000-0000-000000000002")!,
            displayName: "Michael",
            avatarEmoji: "",
            avatarColorHex: "007AFF" // Apple Blue
        ),
        DemoUser(
            id: UUID(uuidString: "DE000000-0001-0000-0000-000000000003")!,
            displayName: "Emma Chen",
            avatarEmoji: "",
            avatarColorHex: "FF9500" // Apple Orange
        ),
        DemoUser(
            id: UUID(uuidString: "DE000000-0001-0000-0000-000000000004")!,
            displayName: "James",
            avatarEmoji: "",
            avatarColorHex: "AF52DE" // Apple Purple
        )
    ]

    // MARK: - Demo Ingredients

    struct DemoIngredient {
        let id: UUID
        let name: String
        let category: IngredientCategory
        let defaultUnit: MeasurementUnit
        let caloriesPer100g: Double?
        let proteinPer100g: Double?
        let carbsPer100g: Double?
        let fatPer100g: Double?
    }

    static let ingredients: [DemoIngredient] = [
        DemoIngredient(
            id: UUID(uuidString: "DE000000-0002-0000-0000-000000000001")!,
            name: "Suspiciously Fresh Avocado",
            category: .produce,
            defaultUnit: .piece,
            caloriesPer100g: 160,
            proteinPer100g: 2,
            carbsPer100g: 9,
            fatPer100g: 15
        ),
        DemoIngredient(
            id: UUID(uuidString: "DE000000-0002-0000-0000-000000000002")!,
            name: "Optimistic Banana",
            category: .produce,
            defaultUnit: .piece,
            caloriesPer100g: 89,
            proteinPer100g: 1.1,
            carbsPer100g: 23,
            fatPer100g: 0.3
        ),
        DemoIngredient(
            id: UUID(uuidString: "DE000000-0002-0000-0000-000000000003")!,
            name: "Garlic (vampire deterrent)",
            category: .produce,
            defaultUnit: .clove,
            caloriesPer100g: 149,
            proteinPer100g: 6.4,
            carbsPer100g: 33,
            fatPer100g: 0.5
        ),
        DemoIngredient(
            id: UUID(uuidString: "DE000000-0002-0000-0000-000000000004")!,
            name: "Chicken Breast (the boring cut)",
            category: .protein,
            defaultUnit: .gram,
            caloriesPer100g: 165,
            proteinPer100g: 31,
            carbsPer100g: 0,
            fatPer100g: 3.6
        ),
        DemoIngredient(
            id: UUID(uuidString: "DE000000-0002-0000-0000-000000000005")!,
            name: "Cheese (excessive amount)",
            category: .dairy,
            defaultUnit: .gram,
            caloriesPer100g: 402,
            proteinPer100g: 25,
            carbsPer100g: 1.3,
            fatPer100g: 33
        ),
        DemoIngredient(
            id: UUID(uuidString: "DE000000-0002-0000-0000-000000000006")!,
            name: "Premium Cereal",
            category: .grain,
            defaultUnit: .gram,
            caloriesPer100g: 379,
            proteinPer100g: 6,
            carbsPer100g: 84,
            fatPer100g: 1.5
        ),
        DemoIngredient(
            id: UUID(uuidString: "DE000000-0002-0000-0000-000000000007")!,
            name: "Frozen Burrito (trusty)",
            category: .frozen,
            defaultUnit: .piece,
            caloriesPer100g: 210,
            proteinPer100g: 8,
            carbsPer100g: 28,
            fatPer100g: 8
        ),
        DemoIngredient(
            id: UUID(uuidString: "DE000000-0002-0000-0000-000000000008")!,
            name: "Ice Cream (medicinal)",
            category: .frozen,
            defaultUnit: .cup,
            caloriesPer100g: 207,
            proteinPer100g: 3.5,
            carbsPer100g: 24,
            fatPer100g: 11
        ),
        DemoIngredient(
            id: UUID(uuidString: "DE000000-0002-0000-0000-000000000009")!,
            name: "Milk (udderly essential)",
            category: .dairy,
            defaultUnit: .milliliter,
            caloriesPer100g: 42,
            proteinPer100g: 3.4,
            carbsPer100g: 5,
            fatPer100g: 1
        ),
        DemoIngredient(
            id: UUID(uuidString: "DE000000-0002-0000-0000-000000000010")!,
            name: "Eggs (nature's little miracles)",
            category: .protein,
            defaultUnit: .piece,
            caloriesPer100g: 155,
            proteinPer100g: 13,
            carbsPer100g: 1.1,
            fatPer100g: 11
        ),
        DemoIngredient(
            id: UUID(uuidString: "DE000000-0002-0000-0000-000000000011")!,
            name: "Bread (carb vehicle)",
            category: .grain,
            defaultUnit: .slice,
            caloriesPer100g: 265,
            proteinPer100g: 9,
            carbsPer100g: 49,
            fatPer100g: 3.2
        ),
        DemoIngredient(
            id: UUID(uuidString: "DE000000-0002-0000-0000-000000000012")!,
            name: "Pasta (endless possibilities)",
            category: .grain,
            defaultUnit: .gram,
            caloriesPer100g: 131,
            proteinPer100g: 5,
            carbsPer100g: 25,
            fatPer100g: 1.1
        ),
        DemoIngredient(
            id: UUID(uuidString: "DE000000-0002-0000-0000-000000000013")!,
            name: "Mystery Fish",
            category: .protein,
            defaultUnit: .gram,
            caloriesPer100g: 84,
            proteinPer100g: 18,
            carbsPer100g: 0,
            fatPer100g: 1
        ),
        DemoIngredient(
            id: UUID(uuidString: "DE000000-0002-0000-0000-000000000014")!,
            name: "Mixed Vegetables (guilt reducer)",
            category: .frozen,
            defaultUnit: .gram,
            caloriesPer100g: 65,
            proteinPer100g: 2.5,
            carbsPer100g: 13,
            fatPer100g: 0.3
        )
    ]

    // MARK: - Demo Recipes

    struct DemoRecipe {
        let id: UUID
        let title: String
        let summary: String
        let servings: Int
        let prepTimeMinutes: Int?
        let cookTimeMinutes: Int?
        let instructions: [String]
        let tags: [String]
        let suggestedArchetypes: [ArchetypeType]
        /// References to ingredient IDs with quantities
        let ingredients: [(ingredientIndex: Int, quantity: Double, unit: MeasurementUnit, preparationNote: String?)]
    }

    static let recipes: [DemoRecipe] = [
        DemoRecipe(
            id: UUID(uuidString: "DE000000-0003-0000-0000-000000000001")!,
            title: "Cereal with Milk (Advanced)",
            summary: "A deceptively complex dish mastered only after years of practice",
            servings: 1,
            prepTimeMinutes: 2,
            cookTimeMinutes: nil,
            instructions: [
                "Select your bowl with intention. The wrong bowl ruins everything.",
                "Pour cereal. Not too much - leave room for milk. Not too little - you're not a bird.",
                "Add milk. The ratio is personal and sacred.",
                "Eat immediately. A soggy cereal is a sad cereal."
            ],
            tags: ["breakfast", "quick", "essential"],
            suggestedArchetypes: [.quickWeeknight],
            ingredients: [
                (5, 50, .gram, nil),   // Premium Cereal
                (8, 200, .milliliter, "cold") // Milk
            ]
        ),
        DemoRecipe(
            id: UUID(uuidString: "DE000000-0003-0000-0000-000000000002")!,
            title: "Toast: A Culinary Journey",
            summary: "The bread, transformed",
            servings: 2,
            prepTimeMinutes: 1,
            cookTimeMinutes: 3,
            instructions: [
                "Insert bread into toaster. Contemplate life choices.",
                "Select toast darkness level. This defines who you are as a person.",
                "Wait. This is the hardest part.",
                "Apply butter while still warm. Generosity is key.",
                "Consume while philosophizing about how humans domesticated wheat."
            ],
            tags: ["breakfast", "simple", "timeless"],
            suggestedArchetypes: [.quickWeeknight, .comfort],
            ingredients: [
                (10, 2, .slice, nil) // Bread
            ]
        ),
        DemoRecipe(
            id: UUID(uuidString: "DE000000-0003-0000-0000-000000000003")!,
            title: "Microwave Burrito Meditation",
            summary: "A 3-minute journey to enlightenment",
            servings: 1,
            prepTimeMinutes: 1,
            cookTimeMinutes: 3,
            instructions: [
                "Remove burrito from freezer. Thank the ancient Aztecs for this gift.",
                "Place on microwave-safe plate. Some lessons are learned the hard way.",
                "Microwave for 90 seconds. Flip. Microwave another 90 seconds.",
                "Wait 1 minute. The inside is lava.",
                "Add hot sauce if you're feeling brave."
            ],
            tags: ["quick", "lazy", "satisfying"],
            suggestedArchetypes: [.quickWeeknight],
            ingredients: [
                (6, 1, .piece, nil) // Frozen Burrito
            ]
        ),
        DemoRecipe(
            id: UUID(uuidString: "DE000000-0003-0000-0000-000000000004")!,
            title: "Avocado Toast of the Bourgeoisie",
            summary: "Worth every penny of your future home down payment",
            servings: 2,
            prepTimeMinutes: 5,
            cookTimeMinutes: 3,
            instructions: [
                "Toast the bread to golden perfection.",
                "Cut avocado in half. Remove pit with confidence (and caution).",
                "Scoop avocado onto toast. Mash with fork while feeling fancy.",
                "Season with salt, pepper, and a squeeze of lemon.",
                "Take photo for social media. This is mandatory.",
                "Finally eat it."
            ],
            tags: ["breakfast", "trendy", "instagram"],
            suggestedArchetypes: [.lightFresh],
            ingredients: [
                (0, 1, .piece, "ripe"), // Avocado
                (10, 2, .slice, "toasted") // Bread
            ]
        ),
        DemoRecipe(
            id: UUID(uuidString: "DE000000-0003-0000-0000-000000000005")!,
            title: "Pasta with Audacious Amounts of Garlic",
            summary: "Ward off both vampires and close conversations",
            servings: 4,
            prepTimeMinutes: 10,
            cookTimeMinutes: 15,
            instructions: [
                "Boil water. Add salt like you mean it.",
                "Cook pasta according to package (minus 1 minute for al dente superiority).",
                "Meanwhile, slice an alarming amount of garlic.",
                "Sauté garlic in olive oil until fragrant. Do not burn - this is the only rule.",
                "Toss pasta with garlic oil. Add parmesan.",
                "Serve immediately. Warn dinner companions about the garlic situation."
            ],
            tags: ["dinner", "garlic", "vampire-proof"],
            suggestedArchetypes: [.quickWeeknight, .comfort],
            ingredients: [
                (11, 400, .gram, nil), // Pasta
                (2, 8, .clove, "sliced"), // Garlic
                (4, 50, .gram, "grated") // Cheese
            ]
        ),
        DemoRecipe(
            id: UUID(uuidString: "DE000000-0003-0000-0000-000000000006")!,
            title: "The \"I Swear I'll Go Grocery Shopping Tomorrow\" Omelette",
            summary: "Made with whatever's left",
            servings: 1,
            prepTimeMinutes: 5,
            cookTimeMinutes: 5,
            instructions: [
                "Raid the fridge. Find eggs. You're in business.",
                "Beat eggs with a splash of milk. Add salt and pepper.",
                "Heat butter in pan over medium heat.",
                "Pour eggs. Wait. Resist the urge to stir.",
                "Add whatever cheese and vegetables you found.",
                "Fold when almost set. Plate with pride in your resourcefulness."
            ],
            tags: ["breakfast", "eggs", "improvised"],
            suggestedArchetypes: [.quickWeeknight, .leftovers],
            ingredients: [
                (9, 3, .piece, "beaten"), // Eggs
                (4, 30, .gram, "shredded"), // Cheese
                (8, 50, .milliliter, nil) // Milk
            ]
        ),
        DemoRecipe(
            id: UUID(uuidString: "DE000000-0003-0000-0000-000000000007")!,
            title: "Pan-Seared Chicken of Questionable Tenderness",
            summary: "It's done when the thermometer says so",
            servings: 2,
            prepTimeMinutes: 10,
            cookTimeMinutes: 20,
            instructions: [
                "Pound chicken to even thickness. Take out your frustrations.",
                "Season generously with salt, pepper, and whatever else looks good.",
                "Heat oil in pan until shimmering. Not smoking. Shimmering.",
                "Add chicken. Do not touch it. Seriously.",
                "Flip after 6-7 minutes. Cook until internal temp reaches 165°F.",
                "Rest for 5 minutes. Use this time to wonder if you cooked it right.",
                "Slice and serve. Accept compliments graciously."
            ],
            tags: ["dinner", "protein", "healthy"],
            suggestedArchetypes: [.quickWeeknight, .familyFavorite],
            ingredients: [
                (3, 400, .gram, "boneless, skinless") // Chicken
            ]
        ),
        DemoRecipe(
            id: UUID(uuidString: "DE000000-0003-0000-0000-000000000008")!,
            title: "\"We Have Food at Home\" Stir Fry",
            summary: "A medley of leftovers",
            servings: 4,
            prepTimeMinutes: 15,
            cookTimeMinutes: 10,
            instructions: [
                "Open fridge. Assess the situation. Find vegetables of various ages.",
                "Cut everything into similar-sized pieces. Uniformity is key.",
                "Heat wok or large pan until smoking hot.",
                "Add oil, then vegetables in order of density (hard vegetables first).",
                "Stir fry for 3-4 minutes. Keep things moving.",
                "Add soy sauce, garlic, and a pinch of sugar.",
                "Serve over rice and pretend you planned this all along."
            ],
            tags: ["dinner", "vegetables", "leftover-friendly"],
            suggestedArchetypes: [.quickWeeknight, .leftovers, .lightFresh],
            ingredients: [
                (13, 300, .gram, "mixed"), // Vegetables
                (2, 3, .clove, "minced"), // Garlic
                (3, 200, .gram, "sliced") // Chicken
            ]
        ),
        DemoRecipe(
            id: UUID(uuidString: "DE000000-0003-0000-0000-000000000009")!,
            title: "Ice Cream for Dinner (Self-Care Edition)",
            summary: "Because you're an adult",
            servings: 1,
            prepTimeMinutes: 1,
            cookTimeMinutes: nil,
            instructions: [
                "Confirm that you are, in fact, an adult who makes their own decisions.",
                "Get the ice cream from the freezer.",
                "Select an appropriately large bowl. Or don't use a bowl. No judgment.",
                "Add toppings if desired. This is your journey.",
                "Eat while watching something comforting.",
                "Feel no guilt. This is self-care."
            ],
            tags: ["dinner", "self-care", "no-regrets"],
            suggestedArchetypes: [.comfort],
            ingredients: [
                (7, 2, .cup, nil) // Ice Cream
            ]
        ),
        DemoRecipe(
            id: UUID(uuidString: "DE000000-0003-0000-0000-000000000010")!,
            title: "Mystery Fish Surprise",
            summary: "The surprise is that it turned out edible",
            servings: 2,
            prepTimeMinutes: 10,
            cookTimeMinutes: 12,
            instructions: [
                "Identify the fish. This step is optional but recommended.",
                "Pat fish dry. Season with salt, pepper, and hope.",
                "Heat oil in pan over medium-high heat.",
                "Place fish skin-side down. Press gently to prevent curling.",
                "Cook 4-5 minutes until skin is crispy.",
                "Flip carefully. Cook 2-3 more minutes.",
                "Squeeze lemon over top. Serve immediately.",
                "Accept that you are now a person who cooks fish."
            ],
            tags: ["dinner", "seafood", "adventurous"],
            suggestedArchetypes: [.newExperimental, .lightFresh],
            ingredients: [
                (12, 300, .gram, "skin-on fillet") // Mystery Fish
            ]
        )
    ]

    // MARK: - Demo Week Plan Configuration

    /// Household note for the demo week plan
    static let weekPlanNote = "Last time we made the garlic pasta, the smoke alarm went off. Worth it. Also, Snack Goblin is banned from 'taste testing' before dinner."

    /// Meal slot configurations for the demo week
    struct MealSlotConfig {
        let day: DayOfWeek
        let mealType: MealType
        let recipeIndex: Int?  // nil = custom meal or skipped
        let customMealName: String?
        let notes: String?
        let isSkipped: Bool
        let servings: Int
    }

    static let mealSlots: [MealSlotConfig] = [
        // Monday
        MealSlotConfig(day: .monday, mealType: .breakfast, recipeIndex: 0, customMealName: nil, notes: nil, isSkipped: false, servings: 2),
        MealSlotConfig(day: .monday, mealType: .lunch, recipeIndex: nil, customMealName: "Sad desk lunch", notes: "Leftovers from the weekend", isSkipped: false, servings: 1),
        MealSlotConfig(day: .monday, mealType: .dinner, recipeIndex: 4, customMealName: nil, notes: "No kissing afterwards", isSkipped: false, servings: 4),

        // Tuesday
        MealSlotConfig(day: .tuesday, mealType: .breakfast, recipeIndex: 1, customMealName: nil, notes: nil, isSkipped: false, servings: 2),
        MealSlotConfig(day: .tuesday, mealType: .lunch, recipeIndex: nil, customMealName: nil, notes: nil, isSkipped: true, servings: 2),
        MealSlotConfig(day: .tuesday, mealType: .dinner, recipeIndex: 6, customMealName: nil, notes: "Use the meat thermometer this time", isSkipped: false, servings: 4),

        // Wednesday
        MealSlotConfig(day: .wednesday, mealType: .breakfast, recipeIndex: 5, customMealName: nil, notes: "Chef Chaos's specialty", isSkipped: false, servings: 2),
        MealSlotConfig(day: .wednesday, mealType: .lunch, recipeIndex: 3, customMealName: nil, notes: nil, isSkipped: false, servings: 2),
        MealSlotConfig(day: .wednesday, mealType: .dinner, recipeIndex: 7, customMealName: nil, notes: "Clean out the fridge day", isSkipped: false, servings: 4),

        // Thursday
        MealSlotConfig(day: .thursday, mealType: .breakfast, recipeIndex: 0, customMealName: nil, notes: nil, isSkipped: false, servings: 2),
        MealSlotConfig(day: .thursday, mealType: .lunch, recipeIndex: 2, customMealName: nil, notes: "Meditation time", isSkipped: false, servings: 1),
        MealSlotConfig(day: .thursday, mealType: .dinner, recipeIndex: 9, customMealName: nil, notes: "Fingers crossed", isSkipped: false, servings: 2),

        // Friday
        MealSlotConfig(day: .friday, mealType: .breakfast, recipeIndex: 1, customMealName: nil, notes: nil, isSkipped: false, servings: 2),
        MealSlotConfig(day: .friday, mealType: .lunch, recipeIndex: nil, customMealName: nil, notes: nil, isSkipped: true, servings: 2),
        MealSlotConfig(day: .friday, mealType: .dinner, recipeIndex: nil, customMealName: "Takeout Night - we've earned it", notes: "Rotate who picks the restaurant", isSkipped: false, servings: 4),

        // Saturday
        MealSlotConfig(day: .saturday, mealType: .breakfast, recipeIndex: 3, customMealName: nil, notes: "Weekend brunch vibes", isSkipped: false, servings: 4),
        MealSlotConfig(day: .saturday, mealType: .lunch, recipeIndex: nil, customMealName: nil, notes: nil, isSkipped: true, servings: 2),
        MealSlotConfig(day: .saturday, mealType: .dinner, recipeIndex: 4, customMealName: nil, notes: "Double garlic night. We regret nothing.", isSkipped: false, servings: 4),

        // Sunday
        MealSlotConfig(day: .sunday, mealType: .breakfast, recipeIndex: 5, customMealName: nil, notes: "Whatever's left in the fridge", isSkipped: false, servings: 3),
        MealSlotConfig(day: .sunday, mealType: .lunch, recipeIndex: nil, customMealName: "Family lunch - grandma's bringing food", notes: "Clear the table!", isSkipped: false, servings: 6),
        MealSlotConfig(day: .sunday, mealType: .dinner, recipeIndex: 8, customMealName: nil, notes: "Self-care Sunday", isSkipped: false, servings: 2)
    ]

    // MARK: - Manual Grocery Items

    struct ManualGroceryItem {
        let id: UUID
        let name: String
        let quantity: Double
        let unit: MeasurementUnit
        let category: IngredientCategory
    }

    static let manualGroceryItems: [ManualGroceryItem] = [
        ManualGroceryItem(
            id: UUID(uuidString: "DE000000-0006-0000-0000-000000000001")!,
            name: "Snacks (hide from Snack Goblin)",
            quantity: 1,
            unit: .piece,
            category: .pantry
        ),
        ManualGroceryItem(
            id: UUID(uuidString: "DE000000-0006-0000-0000-000000000002")!,
            name: "Wine (for the chef)",
            quantity: 2,
            unit: .piece,
            category: .beverage
        ),
        ManualGroceryItem(
            id: UUID(uuidString: "DE000000-0006-0000-0000-000000000003")!,
            name: "Something green (for guilt)",
            quantity: 1,
            unit: .bunch,
            category: .produce
        )
    ]

    // MARK: - Demo Personal Settings

    struct DemoPersonalSettings {
        let dailyCalorieTarget: Int
        let dailyProteinTarget: Int
        let dailyCarbTarget: Int
        let dailyFatTarget: Int
    }

    static let personalSettings = DemoPersonalSettings(
        dailyCalorieTarget: 2000,
        dailyProteinTarget: 100,
        dailyCarbTarget: 250,
        dailyFatTarget: 70
    )

    // MARK: - Demo Meal Logs

    struct DemoMealLog {
        let id: UUID
        let dayOffset: Int  // Days from today (negative = past)
        let mealType: MealType
        let recipeIndex: Int?  // nil = quick log
        let quickLogName: String?
        let servingsConsumed: Double
        let quickLogCalories: Int?
        let quickLogProtein: Int?
        let quickLogCarbs: Int?
        let quickLogFat: Int?
    }

    static let mealLogs: [DemoMealLog] = [
        // Today
        DemoMealLog(id: UUID(uuidString: "DE000000-0007-0000-0000-000000000001")!, dayOffset: 0, mealType: .breakfast, recipeIndex: 0, quickLogName: nil, servingsConsumed: 1, quickLogCalories: nil, quickLogProtein: nil, quickLogCarbs: nil, quickLogFat: nil),
        DemoMealLog(id: UUID(uuidString: "DE000000-0007-0000-0000-000000000002")!, dayOffset: 0, mealType: .lunch, recipeIndex: nil, quickLogName: "Sandwich from the cafe", servingsConsumed: 1, quickLogCalories: 450, quickLogProtein: 22, quickLogCarbs: 45, quickLogFat: 18),

        // Yesterday
        DemoMealLog(id: UUID(uuidString: "DE000000-0007-0000-0000-000000000003")!, dayOffset: -1, mealType: .breakfast, recipeIndex: 1, quickLogName: nil, servingsConsumed: 2, quickLogCalories: nil, quickLogProtein: nil, quickLogCarbs: nil, quickLogFat: nil),
        DemoMealLog(id: UUID(uuidString: "DE000000-0007-0000-0000-000000000004")!, dayOffset: -1, mealType: .lunch, recipeIndex: 3, quickLogName: nil, servingsConsumed: 1, quickLogCalories: nil, quickLogProtein: nil, quickLogCarbs: nil, quickLogFat: nil),
        DemoMealLog(id: UUID(uuidString: "DE000000-0007-0000-0000-000000000005")!, dayOffset: -1, mealType: .dinner, recipeIndex: 4, quickLogName: nil, servingsConsumed: 1.5, quickLogCalories: nil, quickLogProtein: nil, quickLogCarbs: nil, quickLogFat: nil),

        // 2 days ago
        DemoMealLog(id: UUID(uuidString: "DE000000-0007-0000-0000-000000000006")!, dayOffset: -2, mealType: .breakfast, recipeIndex: 0, quickLogName: nil, servingsConsumed: 1, quickLogCalories: nil, quickLogProtein: nil, quickLogCarbs: nil, quickLogFat: nil),
        DemoMealLog(id: UUID(uuidString: "DE000000-0007-0000-0000-000000000007")!, dayOffset: -2, mealType: .dinner, recipeIndex: 6, quickLogName: nil, servingsConsumed: 1, quickLogCalories: nil, quickLogProtein: nil, quickLogCarbs: nil, quickLogFat: nil),

        // 3 days ago
        DemoMealLog(id: UUID(uuidString: "DE000000-0007-0000-0000-000000000008")!, dayOffset: -3, mealType: .breakfast, recipeIndex: 5, quickLogName: nil, servingsConsumed: 1, quickLogCalories: nil, quickLogProtein: nil, quickLogCarbs: nil, quickLogFat: nil),
        DemoMealLog(id: UUID(uuidString: "DE000000-0007-0000-0000-000000000009")!, dayOffset: -3, mealType: .lunch, recipeIndex: 2, quickLogName: nil, servingsConsumed: 1, quickLogCalories: nil, quickLogProtein: nil, quickLogCarbs: nil, quickLogFat: nil),
        DemoMealLog(id: UUID(uuidString: "DE000000-0007-0000-0000-000000000010")!, dayOffset: -3, mealType: .dinner, recipeIndex: 7, quickLogName: nil, servingsConsumed: 1, quickLogCalories: nil, quickLogProtein: nil, quickLogCarbs: nil, quickLogFat: nil),

        // 4 days ago
        DemoMealLog(id: UUID(uuidString: "DE000000-0007-0000-0000-000000000011")!, dayOffset: -4, mealType: .breakfast, recipeIndex: 1, quickLogName: nil, servingsConsumed: 1, quickLogCalories: nil, quickLogProtein: nil, quickLogCarbs: nil, quickLogFat: nil),
        DemoMealLog(id: UUID(uuidString: "DE000000-0007-0000-0000-000000000012")!, dayOffset: -4, mealType: .dinner, recipeIndex: nil, quickLogName: "Pizza night!", servingsConsumed: 1, quickLogCalories: 800, quickLogProtein: 30, quickLogCarbs: 90, quickLogFat: 35),

        // 5 days ago
        DemoMealLog(id: UUID(uuidString: "DE000000-0007-0000-0000-000000000013")!, dayOffset: -5, mealType: .breakfast, recipeIndex: 0, quickLogName: nil, servingsConsumed: 1, quickLogCalories: nil, quickLogProtein: nil, quickLogCarbs: nil, quickLogFat: nil),
        DemoMealLog(id: UUID(uuidString: "DE000000-0007-0000-0000-000000000014")!, dayOffset: -5, mealType: .lunch, recipeIndex: 3, quickLogName: nil, servingsConsumed: 1, quickLogCalories: nil, quickLogProtein: nil, quickLogCarbs: nil, quickLogFat: nil),
        DemoMealLog(id: UUID(uuidString: "DE000000-0007-0000-0000-000000000015")!, dayOffset: -5, mealType: .dinner, recipeIndex: 9, quickLogName: nil, servingsConsumed: 1, quickLogCalories: nil, quickLogProtein: nil, quickLogCarbs: nil, quickLogFat: nil),

        // 6 days ago
        DemoMealLog(id: UUID(uuidString: "DE000000-0007-0000-0000-000000000016")!, dayOffset: -6, mealType: .breakfast, recipeIndex: 5, quickLogName: nil, servingsConsumed: 1, quickLogCalories: nil, quickLogProtein: nil, quickLogCarbs: nil, quickLogFat: nil),
        DemoMealLog(id: UUID(uuidString: "DE000000-0007-0000-0000-000000000017")!, dayOffset: -6, mealType: .dinner, recipeIndex: 8, quickLogName: nil, servingsConsumed: 2, quickLogCalories: nil, quickLogProtein: nil, quickLogCarbs: nil, quickLogFat: nil)
    ]

    // MARK: - Week Plan UUID

    static let weekPlanID = UUID(uuidString: "DE000000-0004-0000-0000-000000000001")!
}
