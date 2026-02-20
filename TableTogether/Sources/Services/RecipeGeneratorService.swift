import Foundation
import SwiftUI

// MARK: - Recipe Generator Prompt

/// Captures user preferences for recipe generation.
struct RecipeGeneratorPrompt: Equatable {
    var ingredients: [String] = []
    var cookingStyle: CookingStyle = .scratch
    var timeAvailability: TimeAvailability = .moderate
    var cuisines: Set<CuisineType> = []
    var dietaryPreferences: Set<DietaryPreference> = []
    var servings: Int = 4
    var additionalNotes: String = ""

    /// Whether the prompt has enough information to generate a recipe.
    var isValid: Bool {
        !ingredients.isEmpty || !cuisines.isEmpty
    }

    /// Creates a human-readable summary of the prompt.
    var summary: String {
        var parts: [String] = []

        if !ingredients.isEmpty {
            let ingredientList = ingredients.prefix(3).joined(separator: ", ")
            let suffix = ingredients.count > 3 ? " +\(ingredients.count - 3) more" : ""
            parts.append("using \(ingredientList)\(suffix)")
        }

        parts.append(cookingStyle == .scratch ? "from scratch" : "with shortcuts")
        parts.append(timeAvailability.description.lowercased())

        if !cuisines.isEmpty {
            let cuisineList = cuisines.prefix(2).map { $0.displayName }.joined(separator: ", ")
            parts.append(cuisineList + " style")
        }

        return parts.joined(separator: ", ")
    }
}

// MARK: - Generated Recipe Result

/// Represents a generated recipe before it's saved to the database.
struct GeneratedRecipe: Identifiable, Equatable {
    let id = UUID()
    var title: String
    var summary: String
    var servings: Int
    var prepTimeMinutes: Int
    var cookTimeMinutes: Int
    var ingredients: [GeneratedIngredient]
    var instructions: [String]
    var suggestedArchetypes: [ArchetypeType]
    var tags: [String]
    var cuisineType: CuisineType?
    var cookingStyle: CookingStyle

    /// Total cooking time in minutes.
    var totalTimeMinutes: Int {
        prepTimeMinutes + cookTimeMinutes
    }

    /// Formatted total time string.
    var formattedTotalTime: String {
        let total = totalTimeMinutes
        if total >= 60 {
            let hours = total / 60
            let mins = total % 60
            return mins > 0 ? "\(hours) hr \(mins) min" : "\(hours) hr"
        }
        return "\(total) min"
    }

    struct GeneratedIngredient: Identifiable, Equatable {
        let id = UUID()
        var name: String
        var quantity: Double
        var unit: MeasurementUnit
        var preparationNote: String?
        var isOptional: Bool = false
    }
}

// MARK: - Recipe Generator Service

/// Service for generating recipes based on user preferences.
/// Uses on-device generation when available, with a fallback for older devices.
@MainActor
final class RecipeGeneratorService: ObservableObject {

    // MARK: - Published State

    @Published private(set) var isGenerating: Bool = false
    @Published private(set) var generatedRecipes: [GeneratedRecipe] = []
    @Published var errorMessage: String?

    // MARK: - Generation Status

    enum GenerationStatus: Equatable {
        case idle
        case generating
        case success(count: Int)
        case error(String)
    }

    @Published private(set) var status: GenerationStatus = .idle

    // MARK: - Device Capabilities

    /// Whether the device supports on-device AI generation.
    var supportsOnDeviceGeneration: Bool {
        // Check for Apple Intelligence availability (iOS 18.1+)
        if #available(iOS 18.1, *) {
            return true
        }
        return false
    }

    // MARK: - Public API

    /// Generates recipes based on the provided prompt.
    /// - Parameters:
    ///   - prompt: The user's recipe generation preferences
    ///   - count: Number of recipe variations to generate (1-3)
    func generateRecipes(from prompt: RecipeGeneratorPrompt, count: Int = 1) async {
        guard prompt.isValid else {
            errorMessage = "Please add at least one ingredient or select a cuisine."
            status = .error(errorMessage!)
            return
        }

        isGenerating = true
        status = .generating
        errorMessage = nil
        generatedRecipes = []

        do {
            // Generate recipes
            let recipes = try await performGeneration(prompt: prompt, count: min(count, 3))
            generatedRecipes = recipes
            status = .success(count: recipes.count)
        } catch {
            errorMessage = error.localizedDescription
            status = .error(errorMessage!)
            AppLogger.app.error("Recipe generation failed", error: error)
        }

        isGenerating = false
    }

    /// Clears the current generation results.
    func clearResults() {
        generatedRecipes = []
        errorMessage = nil
        status = .idle
    }

    /// Generates a shortcut version of a scratch recipe.
    func generateShortcutVersion(of recipe: GeneratedRecipe) async -> GeneratedRecipe? {
        guard recipe.cookingStyle == .scratch else { return nil }

        var shortcutRecipe = recipe
        shortcutRecipe.cookingStyle = .shortcut

        // Apply shortcut transformations
        shortcutRecipe = applyShortcutTransformations(to: shortcutRecipe)

        return shortcutRecipe
    }

    /// Generates a from-scratch version of a shortcut recipe.
    func generateScratchVersion(of recipe: GeneratedRecipe) async -> GeneratedRecipe? {
        guard recipe.cookingStyle == .shortcut else { return nil }

        var scratchRecipe = recipe
        scratchRecipe.cookingStyle = .scratch

        // Apply scratch transformations
        scratchRecipe = applyScratchTransformations(to: scratchRecipe)

        return scratchRecipe
    }

    // MARK: - Private Generation

    private func performGeneration(prompt: RecipeGeneratorPrompt, count: Int) async throws -> [GeneratedRecipe] {
        // Simulate generation delay for demo purposes
        // In production, this would call Apple Intelligence or a server API
        try await Task.sleep(for: .seconds(1.5))

        var recipes: [GeneratedRecipe] = []

        for i in 0..<count {
            let recipe = createSampleRecipe(from: prompt, variation: i)
            recipes.append(recipe)
        }

        return recipes
    }

    /// Creates a sample recipe based on the prompt.
    /// This is a placeholder that generates contextually-appropriate demo recipes.
    private func createSampleRecipe(from prompt: RecipeGeneratorPrompt, variation: Int) -> GeneratedRecipe {
        let baseTitle = generateTitle(from: prompt, variation: variation)
        let baseSummary = generateSummary(from: prompt)
        let (prepTime, cookTime) = generateTimes(for: prompt.timeAvailability, style: prompt.cookingStyle)
        let ingredients = generateIngredients(from: prompt, variation: variation)
        let instructions = generateInstructions(from: prompt, ingredientCount: ingredients.count)
        let archetypes = suggestArchetypes(for: prompt)
        let tags = generateTags(from: prompt)

        return GeneratedRecipe(
            title: baseTitle,
            summary: baseSummary,
            servings: prompt.servings,
            prepTimeMinutes: prepTime,
            cookTimeMinutes: cookTime,
            ingredients: ingredients,
            instructions: instructions,
            suggestedArchetypes: archetypes,
            tags: tags,
            cuisineType: prompt.cuisines.first,
            cookingStyle: prompt.cookingStyle
        )
    }

    private func generateTitle(from prompt: RecipeGeneratorPrompt, variation: Int) -> String {
        let cuisinePrefix = prompt.cuisines.first?.displayName ?? ""
        let stylePrefix = prompt.cookingStyle == .shortcut ? "Quick " : ""

        // Use main ingredient if available
        if let mainIngredient = prompt.ingredients.first {
            let titles = [
                "\(stylePrefix)\(cuisinePrefix) \(mainIngredient.capitalized)",
                "\(mainIngredient.capitalized) \(cuisinePrefix) Style",
                "Easy \(mainIngredient.capitalized) Delight"
            ]
            return titles[variation % titles.count].trimmingCharacters(in: .whitespaces)
        }

        // Fallback to cuisine-based title
        let cuisineTitles: [CuisineType: [String]] = [
            .indian: ["Fragrant Curry Bowl", "Spiced Comfort Dish", "Tandoori Delight"],
            .italian: ["Rustic Pasta", "Mediterranean Bowl", "Herb-Infused Classic"],
            .chinese: ["Wok-Tossed Delight", "Savory Stir-Fry", "Ginger-Garlic Bowl"],
            .mexican: ["Fiesta Bowl", "Zesty Taco Night", "Chipotle Creation"],
            .british: ["Hearty Comfort Dish", "Classic Supper", "Cozy Kitchen Favorite"]
        ]

        if let cuisine = prompt.cuisines.first, let titles = cuisineTitles[cuisine] {
            return stylePrefix + titles[variation % titles.count]
        }

        return stylePrefix + "Chef's Special"
    }

    private func generateSummary(from prompt: RecipeGeneratorPrompt) -> String {
        var summaryParts: [String] = []

        if let cuisine = prompt.cuisines.first {
            summaryParts.append("A \(cuisine.displayName.lowercased())-inspired dish")
        } else {
            summaryParts.append("A delicious homemade dish")
        }

        if prompt.cookingStyle == .shortcut {
            summaryParts.append("made quick with clever shortcuts")
        } else {
            summaryParts.append("made from scratch with love")
        }

        if !prompt.dietaryPreferences.isEmpty && !prompt.dietaryPreferences.contains(.none) {
            let prefs = prompt.dietaryPreferences.map { $0.displayName.lowercased() }.joined(separator: ", ")
            summaryParts.append("(\(prefs))")
        }

        return summaryParts.joined(separator: " ") + "."
    }

    private func generateTimes(for availability: TimeAvailability, style: CookingStyle) -> (prep: Int, cook: Int) {
        let shortcutMultiplier = style == .shortcut ? 0.7 : 1.0

        switch availability {
        case .quick:
            let prep = Int(Double(10) * shortcutMultiplier)
            let cook = Int(Double(15) * shortcutMultiplier)
            return (prep, cook)
        case .moderate:
            let prep = Int(Double(20) * shortcutMultiplier)
            let cook = Int(Double(30) * shortcutMultiplier)
            return (prep, cook)
        case .leisurely:
            let prep = Int(Double(30) * shortcutMultiplier)
            let cook = Int(Double(60) * shortcutMultiplier)
            return (prep, cook)
        }
    }

    private func generateIngredients(from prompt: RecipeGeneratorPrompt, variation: Int) -> [GeneratedRecipe.GeneratedIngredient] {
        var ingredients: [GeneratedRecipe.GeneratedIngredient] = []

        // Add user-specified ingredients
        for (index, ingredientName) in prompt.ingredients.enumerated() {
            ingredients.append(GeneratedRecipe.GeneratedIngredient(
                name: ingredientName.capitalized,
                quantity: Double([1, 2, 200, 300][index % 4]),
                unit: [.piece, .cup, .gram, .gram][index % 4],
                preparationNote: ["diced", "sliced", nil, "minced"][index % 4]
            ))
        }

        // Add complementary ingredients based on cuisine
        let complementary = getComplementaryIngredients(for: prompt.cuisines.first, style: prompt.cookingStyle)
        for comp in complementary.prefix(5 - ingredients.count) {
            ingredients.append(comp)
        }

        return ingredients
    }

    private func getComplementaryIngredients(for cuisine: CuisineType?, style: CookingStyle) -> [GeneratedRecipe.GeneratedIngredient] {
        let isShortcut = style == .shortcut

        switch cuisine {
        case .indian:
            return [
                GeneratedRecipe.GeneratedIngredient(name: isShortcut ? "Curry paste" : "Garam masala", quantity: isShortcut ? 2 : 1, unit: .tablespoon),
                GeneratedRecipe.GeneratedIngredient(name: "Basmati rice", quantity: 1, unit: .cup),
                GeneratedRecipe.GeneratedIngredient(name: "Coconut milk", quantity: 200, unit: .milliliter),
                GeneratedRecipe.GeneratedIngredient(name: "Fresh cilantro", quantity: 1, unit: .bunch, preparationNote: "chopped")
            ]
        case .italian:
            return [
                GeneratedRecipe.GeneratedIngredient(name: isShortcut ? "Jarred marinara" : "San Marzano tomatoes", quantity: isShortcut ? 1 : 400, unit: isShortcut ? .cup : .gram),
                GeneratedRecipe.GeneratedIngredient(name: "Garlic", quantity: 3, unit: .clove, preparationNote: "minced"),
                GeneratedRecipe.GeneratedIngredient(name: "Fresh basil", quantity: 1, unit: .bunch),
                GeneratedRecipe.GeneratedIngredient(name: "Parmesan", quantity: 50, unit: .gram, preparationNote: "grated")
            ]
        case .chinese:
            return [
                GeneratedRecipe.GeneratedIngredient(name: "Soy sauce", quantity: 2, unit: .tablespoon),
                GeneratedRecipe.GeneratedIngredient(name: "Ginger", quantity: 1, unit: .tablespoon, preparationNote: "grated"),
                GeneratedRecipe.GeneratedIngredient(name: isShortcut ? "Pre-cut stir-fry vegetables" : "Mixed vegetables", quantity: 300, unit: .gram),
                GeneratedRecipe.GeneratedIngredient(name: "Sesame oil", quantity: 1, unit: .teaspoon)
            ]
        default:
            return [
                GeneratedRecipe.GeneratedIngredient(name: "Olive oil", quantity: 2, unit: .tablespoon),
                GeneratedRecipe.GeneratedIngredient(name: "Salt", quantity: 1, unit: .pinch),
                GeneratedRecipe.GeneratedIngredient(name: "Black pepper", quantity: 1, unit: .pinch),
                GeneratedRecipe.GeneratedIngredient(name: "Garlic", quantity: 2, unit: .clove, preparationNote: "minced")
            ]
        }
    }

    private func generateInstructions(from prompt: RecipeGeneratorPrompt, ingredientCount: Int) -> [String] {
        let isShortcut = prompt.cookingStyle == .shortcut

        if isShortcut {
            return [
                "Gather all ingredients and prep any that need cutting.",
                "Heat a large pan or wok over medium-high heat with a drizzle of oil.",
                "Add the main ingredients and cook for 3-4 minutes, stirring occasionally.",
                "Add any sauces or seasonings and toss to combine.",
                "Cook for another 2-3 minutes until everything is heated through.",
                "Taste and adjust seasoning as needed.",
                "Serve immediately and enjoy!"
            ]
        } else {
            return [
                "Begin by preparing all your ingredients: wash, peel, and cut as needed.",
                "If making any sauces or bases from scratch, start those first.",
                "Heat your cooking vessel over medium heat and add oil.",
                "Add aromatics (garlic, onion, ginger) and cook until fragrant, about 2 minutes.",
                "Add the main protein or vegetables and cook until starting to brown.",
                "Pour in any liquids and bring to a simmer.",
                "Reduce heat and let flavors meld for 10-15 minutes, stirring occasionally.",
                "Finish with fresh herbs or a squeeze of citrus.",
                "Plate beautifully and serve with your chosen accompaniment."
            ]
        }
    }

    private func suggestArchetypes(for prompt: RecipeGeneratorPrompt) -> [ArchetypeType] {
        var archetypes: [ArchetypeType] = []

        // Based on time
        switch prompt.timeAvailability {
        case .quick:
            archetypes.append(.quickWeeknight)
        case .leisurely:
            archetypes.append(.slowCook)
        case .moderate:
            break
        }

        // Based on style
        if prompt.cookingStyle == .scratch {
            archetypes.append(.newExperimental)
        }

        // Based on servings
        if prompt.servings >= 6 {
            archetypes.append(.bigBatch)
        }

        // Based on dietary preferences
        if prompt.dietaryPreferences.contains(.vegan) || prompt.dietaryPreferences.contains(.vegetarian) {
            archetypes.append(.lightFresh)
        }

        return Array(Set(archetypes)).sorted { $0.rawValue < $1.rawValue }
    }

    private func generateTags(from prompt: RecipeGeneratorPrompt) -> [String] {
        var tags: [String] = []

        // Add cuisine tags
        for cuisine in prompt.cuisines {
            tags.append(cuisine.displayName.lowercased())
        }

        // Add dietary tags
        for pref in prompt.dietaryPreferences where pref != .none {
            tags.append(pref.displayName.lowercased())
        }

        // Add style tags
        if prompt.cookingStyle == .shortcut {
            tags.append("quick")
            tags.append("easy")
        } else {
            tags.append("homemade")
        }

        // Add time tag
        tags.append(prompt.timeAvailability.displayName.lowercased())

        return Array(Set(tags)).sorted()
    }

    // MARK: - Style Transformations

    private func applyShortcutTransformations(to recipe: GeneratedRecipe) -> GeneratedRecipe {
        var modified = recipe

        // Reduce times
        modified.prepTimeMinutes = Int(Double(recipe.prepTimeMinutes) * 0.6)
        modified.cookTimeMinutes = Int(Double(recipe.cookTimeMinutes) * 0.7)

        // Simplify instructions
        modified.instructions = modified.instructions.filter { !$0.lowercased().contains("from scratch") }
        if modified.instructions.count > 6 {
            modified.instructions = Array(modified.instructions.prefix(6))
        }

        // Update summary
        modified.summary = recipe.summary.replacingOccurrences(of: "from scratch", with: "with time-saving shortcuts")

        return modified
    }

    private func applyScratchTransformations(to recipe: GeneratedRecipe) -> GeneratedRecipe {
        var modified = recipe

        // Increase times
        modified.prepTimeMinutes = Int(Double(recipe.prepTimeMinutes) * 1.5)
        modified.cookTimeMinutes = Int(Double(recipe.cookTimeMinutes) * 1.3)

        // Add more detailed instructions
        var expandedInstructions = modified.instructions
        expandedInstructions.insert("Start by preparing any sauces or bases from scratch.", at: 0)
        modified.instructions = expandedInstructions

        // Update summary
        modified.summary = recipe.summary.replacingOccurrences(of: "with time-saving shortcuts", with: "from scratch with care")

        return modified
    }
}
