import Foundation

// MARK: - IngredientCategory

/// Categories for organizing ingredients in the grocery list and recipe management.
enum IngredientCategory: String, Codable, CaseIterable, Hashable, Sendable {
    case produce
    case protein
    case dairy
    case grain
    case pantry
    case frozen
    case condiment
    case beverage
    case other

    /// Human-readable display name for the category.
    var displayName: String {
        switch self {
        case .produce: return "Produce"
        case .protein: return "Protein"
        case .dairy: return "Dairy"
        case .grain: return "Grains & Bread"
        case .pantry: return "Pantry"
        case .frozen: return "Frozen"
        case .condiment: return "Condiments & Sauces"
        case .beverage: return "Beverages"
        case .other: return "Other"
        }
    }

    /// SF Symbol icon name for the category.
    var iconName: String {
        switch self {
        case .produce: return "leaf.fill"
        case .protein: return "fish.fill"
        case .dairy: return "cup.and.saucer.fill"
        case .grain: return "birthday.cake.fill"
        case .pantry: return "archivebox.fill"
        case .frozen: return "snowflake"
        case .condiment: return "drop.fill"
        case .beverage: return "wineglass.fill"
        case .other: return "bag.fill"
        }
    }

    /// Sort order for store layout (typical grocery store flow).
    var sortOrder: Int {
        switch self {
        case .produce: return 0
        case .dairy: return 1
        case .protein: return 2
        case .frozen: return 3
        case .grain: return 4
        case .pantry: return 5
        case .condiment: return 6
        case .beverage: return 7
        case .other: return 8
        }
    }
}

// MARK: - MeasurementUnit

/// Units of measurement for recipe ingredients.
enum MeasurementUnit: String, Codable, CaseIterable, Hashable, Identifiable {
    var id: String { rawValue }
    case gram
    case kilogram
    case milliliter
    case liter
    case cup
    case tablespoon
    case teaspoon
    case piece
    case slice
    case clove
    case bunch
    case pinch
    case toTaste

    /// Human-readable display name for the unit.
    var displayName: String {
        switch self {
        case .gram: return "gram"
        case .kilogram: return "kilogram"
        case .milliliter: return "milliliter"
        case .liter: return "liter"
        case .cup: return "cup"
        case .tablespoon: return "tablespoon"
        case .teaspoon: return "teaspoon"
        case .piece: return "piece"
        case .slice: return "slice"
        case .clove: return "clove"
        case .bunch: return "bunch"
        case .pinch: return "pinch"
        case .toTaste: return "to taste"
        }
    }

    /// Abbreviated form for compact display.
    var abbreviation: String {
        switch self {
        case .gram: return "g"
        case .kilogram: return "kg"
        case .milliliter: return "ml"
        case .liter: return "L"
        case .cup: return "cup"
        case .tablespoon: return "tbsp"
        case .teaspoon: return "tsp"
        case .piece: return "pc"
        case .slice: return "slice"
        case .clove: return "clove"
        case .bunch: return "bunch"
        case .pinch: return "pinch"
        case .toTaste: return "to taste"
        }
    }

    /// Pluralized display name for quantities greater than 1.
    func pluralized(for quantity: Double) -> String {
        guard quantity != 1 else { return displayName }

        switch self {
        case .gram: return "grams"
        case .kilogram: return "kilograms"
        case .milliliter: return "milliliters"
        case .liter: return "liters"
        case .cup: return "cups"
        case .tablespoon: return "tablespoons"
        case .teaspoon: return "teaspoons"
        case .piece: return "pieces"
        case .slice: return "slices"
        case .clove: return "cloves"
        case .bunch: return "bunches"
        case .pinch: return "pinches"
        case .toTaste: return "to taste"
        }
    }
}

// MARK: - ArchetypeType

/// System-defined archetype types that describe the character of a meal.
enum ArchetypeType: String, Codable, CaseIterable, Hashable, Sendable, Identifiable {
    var id: String { rawValue }
    case quickWeeknight
    case comfort
    case leftovers
    case newExperimental
    case bigBatch
    case familyFavorite
    case lightFresh
    case slowCook

    /// Human-readable display name for the archetype.
    var displayName: String {
        switch self {
        case .quickWeeknight: return "Quick Weeknight"
        case .comfort: return "Comfort"
        case .leftovers: return "Leftovers"
        case .newExperimental: return "New / Experimental"
        case .bigBatch: return "Big Batch"
        case .familyFavorite: return "Family Favorite"
        case .lightFresh: return "Light & Fresh"
        case .slowCook: return "Slow Cook"
        }
    }

    /// Brief description of the archetype's purpose.
    var description: String {
        switch self {
        case .quickWeeknight: return "30 minutes or less"
        case .comfort: return "Familiar, satisfying"
        case .leftovers: return "Planned reuse"
        case .newExperimental: return "Try something new"
        case .bigBatch: return "Cook once, eat multiple times"
        case .familyFavorite: return "Proven hits"
        case .lightFresh: return "Salads, lighter fare"
        case .slowCook: return "Crockpot, braised"
        }
    }

    /// SF Symbol name for visual representation.
    var iconName: String {
        switch self {
        case .quickWeeknight: return "bolt.fill"
        case .comfort: return "heart.fill"
        case .leftovers: return "arrow.2.squarepath"
        case .newExperimental: return "sparkles"
        case .bigBatch: return "square.stack.3d.up.fill"
        case .familyFavorite: return "star.fill"
        case .lightFresh: return "leaf.fill"
        case .slowCook: return "timer"
        }
    }

    /// Alias for iconName for compatibility.
    var icon: String { iconName }

    /// Accent color hex code for the archetype.
    var colorHex: String {
        switch self {
        case .quickWeeknight: return "#FFB347"  // Orange
        case .comfort: return "#DDA0DD"         // Plum
        case .leftovers: return "#87CEEB"       // Sky Blue
        case .newExperimental: return "#FFD700" // Gold
        case .bigBatch: return "#98D8C8"        // Mint
        case .familyFavorite: return "#F7DC6F"  // Yellow
        case .lightFresh: return "#90EE90"      // Light Green
        case .slowCook: return "#D2691E"        // Chocolate
        }
    }
}

// MARK: - DayOfWeek

/// Days of the week with Monday as the first day (value 1).
enum DayOfWeek: Int, Codable, CaseIterable, Hashable, Sendable {
    case monday = 1
    case tuesday = 2
    case wednesday = 3
    case thursday = 4
    case friday = 5
    case saturday = 6
    case sunday = 7

    /// Human-readable display name for the day.
    var displayName: String {
        switch self {
        case .monday: return "Monday"
        case .tuesday: return "Tuesday"
        case .wednesday: return "Wednesday"
        case .thursday: return "Thursday"
        case .friday: return "Friday"
        case .saturday: return "Saturday"
        case .sunday: return "Sunday"
        }
    }

    /// Alias for displayName for compatibility.
    var fullName: String { displayName }

    /// Short display name (3 characters).
    var shortName: String {
        switch self {
        case .monday: return "Mon"
        case .tuesday: return "Tue"
        case .wednesday: return "Wed"
        case .thursday: return "Thu"
        case .friday: return "Fri"
        case .saturday: return "Sat"
        case .sunday: return "Sun"
        }
    }

    /// Single character abbreviation.
    var initial: String {
        switch self {
        case .monday: return "M"
        case .tuesday: return "T"
        case .wednesday: return "W"
        case .thursday: return "T"
        case .friday: return "F"
        case .saturday: return "S"
        case .sunday: return "S"
        }
    }

    /// Whether this is a weekend day.
    var isWeekend: Bool {
        self == .saturday || self == .sunday
    }
}

// MARK: - MealType

/// Types of meals throughout the day.
enum MealType: String, Codable, CaseIterable, Hashable, Sendable {
    case breakfast
    case lunch
    case dinner
    case snack

    /// Human-readable display name for the meal type.
    var displayName: String {
        switch self {
        case .breakfast: return "Breakfast"
        case .lunch: return "Lunch"
        case .dinner: return "Dinner"
        case .snack: return "Snack"
        }
    }

    /// SF Symbol name for visual representation.
    var iconName: String {
        switch self {
        case .breakfast: return "sunrise.fill"
        case .lunch: return "sun.max.fill"
        case .dinner: return "moon.fill"
        case .snack: return "carrot.fill"
        }
    }

    /// Alias for iconName for compatibility.
    var icon: String { iconName }

    /// Typical sort order for displaying meals chronologically.
    var sortOrder: Int {
        switch self {
        case .breakfast: return 0
        case .lunch: return 1
        case .dinner: return 2
        case .snack: return 3
        }
    }
}

// MARK: - WeekPlanStatus

/// Status of a week's meal plan.
enum WeekPlanStatus: String, Codable, CaseIterable, Hashable {
    case draft
    case active
    case completed

    /// Human-readable display name for the status.
    var displayName: String {
        switch self {
        case .draft: return "Draft"
        case .active: return "Active"
        case .completed: return "Completed"
        }
    }

    /// Brief description of what this status means.
    var description: String {
        switch self {
        case .draft: return "Being planned"
        case .active: return "Current week"
        case .completed: return "Past week"
        }
    }
}

// MARK: - CookingStyle

/// Preferred cooking approach for recipe generation.
enum CookingStyle: String, Codable, CaseIterable, Hashable, Identifiable {
    var id: String { rawValue }

    case scratch
    case shortcut

    /// Human-readable display name for the cooking style.
    var displayName: String {
        switch self {
        case .scratch: return "From Scratch"
        case .shortcut: return "Shortcut"
        }
    }

    /// Brief description of what this style means.
    var description: String {
        switch self {
        case .scratch: return "Full prep, homemade sauces & components"
        case .shortcut: return "Pre-made ingredients & time-saving swaps"
        }
    }

    /// SF Symbol name for visual representation.
    var iconName: String {
        switch self {
        case .scratch: return "hand.raised.fill"
        case .shortcut: return "bolt.fill"
        }
    }
}

// MARK: - TimeAvailability

/// Time available for cooking, used in recipe generation.
enum TimeAvailability: String, Codable, CaseIterable, Hashable, Identifiable {
    var id: String { rawValue }

    case quick
    case moderate
    case leisurely

    /// Human-readable display name for the time availability.
    var displayName: String {
        switch self {
        case .quick: return "Quick"
        case .moderate: return "Moderate"
        case .leisurely: return "Leisurely"
        }
    }

    /// Brief description with time range.
    var description: String {
        switch self {
        case .quick: return "Under 30 minutes"
        case .moderate: return "30–60 minutes"
        case .leisurely: return "Over 60 minutes"
        }
    }

    /// Maximum time in minutes for this availability.
    var maxMinutes: Int {
        switch self {
        case .quick: return 30
        case .moderate: return 60
        case .leisurely: return 120
        }
    }

    /// SF Symbol name for visual representation.
    var iconName: String {
        switch self {
        case .quick: return "hare.fill"
        case .moderate: return "clock.fill"
        case .leisurely: return "tortoise.fill"
        }
    }
}

// MARK: - CuisineType

/// Cuisine or cooking style for recipe generation.
enum CuisineType: String, Codable, CaseIterable, Hashable, Identifiable {
    var id: String { rawValue }

    case indian
    case british
    case eastAfrican
    case chinese
    case italian
    case mediterranean
    case mexican
    case japanese
    case thai
    case american
    case fusion
    case other

    /// Human-readable display name for the cuisine.
    var displayName: String {
        switch self {
        case .indian: return "Indian"
        case .british: return "British"
        case .eastAfrican: return "East African"
        case .chinese: return "Chinese"
        case .italian: return "Italian"
        case .mediterranean: return "Mediterranean"
        case .mexican: return "Mexican"
        case .japanese: return "Japanese"
        case .thai: return "Thai"
        case .american: return "American"
        case .fusion: return "Fusion"
        case .other: return "Other"
        }
    }

    /// SF Symbol name for visual representation (flag or food-related).
    var iconName: String {
        switch self {
        case .indian: return "flame.fill"
        case .british: return "cup.and.saucer.fill"
        case .eastAfrican: return "leaf.fill"
        case .chinese: return "wok.fill"
        case .italian: return "fork.knife"
        case .mediterranean: return "sun.max.fill"
        case .mexican: return "flame.fill"
        case .japanese: return "fish.fill"
        case .thai: return "leaf.fill"
        case .american: return "star.fill"
        case .fusion: return "sparkles"
        case .other: return "globe"
        }
    }

    /// Accent color hex for the cuisine.
    var colorHex: String {
        switch self {
        case .indian: return "#FF9933"      // Saffron
        case .british: return "#003399"      // Royal Blue
        case .eastAfrican: return "#228B22"  // Forest Green
        case .chinese: return "#DE2910"      // Red
        case .italian: return "#008C45"      // Green
        case .mediterranean: return "#1E90FF" // Dodger Blue
        case .mexican: return "#006847"      // Green
        case .japanese: return "#BC002D"     // Crimson
        case .thai: return "#A51931"         // Magenta
        case .american: return "#B22234"     // Red
        case .fusion: return "#9B59B6"       // Purple
        case .other: return "#708090"        // Slate Gray
        }
    }
}

// MARK: - DietaryPreference

/// Dietary preferences or restrictions for recipe generation.
enum DietaryPreference: String, Codable, CaseIterable, Hashable, Identifiable {
    var id: String { rawValue }

    case vegetarian
    case vegan
    case glutenFree
    case dairyFree
    case lowCarb
    case lowSugar
    case nutFree
    case none

    /// Human-readable display name for the preference.
    var displayName: String {
        switch self {
        case .vegetarian: return "Vegetarian"
        case .vegan: return "Vegan"
        case .glutenFree: return "Gluten-Free"
        case .dairyFree: return "Dairy-Free"
        case .lowCarb: return "Low-Carb"
        case .lowSugar: return "Low-Sugar"
        case .nutFree: return "Nut-Free"
        case .none: return "No Restrictions"
        }
    }

    /// SF Symbol name for visual representation.
    var iconName: String {
        switch self {
        case .vegetarian: return "leaf.fill"
        case .vegan: return "leaf.circle.fill"
        case .glutenFree: return "wheat.slash"
        case .dairyFree: return "drop.slash.fill"
        case .lowCarb: return "chart.bar.fill"
        case .lowSugar: return "cube.fill"
        case .nutFree: return "xmark.circle.fill"
        case .none: return "checkmark.circle.fill"
        }
    }
}

// MARK: - FamiliarityLevel

/// How familiar the household is with a recipe based on cooking history.
enum FamiliarityLevel: String, Codable, CaseIterable, Hashable {
    case new
    case tried
    case familiar
    case staple

    /// Human-readable display name for the familiarity level.
    var displayName: String {
        switch self {
        case .new: return "New"
        case .tried: return "Tried"
        case .familiar: return "Familiar"
        case .staple: return "Staple"
        }
    }

    /// Brief description of what this level means.
    var description: String {
        switch self {
        case .new: return "Never cooked"
        case .tried: return "Cooked 1-2 times"
        case .familiar: return "Cooked 3-5 times"
        case .staple: return "Cooked 6+ times"
        }
    }

    /// Determines the familiarity level based on the number of times cooked.
    static func from(timesCooked: Int) -> FamiliarityLevel {
        switch timesCooked {
        case 0: return .new
        case 1...2: return .tried
        case 3...5: return .familiar
        default: return .staple
        }
    }
}
