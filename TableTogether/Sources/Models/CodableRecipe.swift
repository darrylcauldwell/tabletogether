import Foundation
import CoreData

/// A portable, Codable representation of a Recipe for JSON export/import.
struct CodableRecipe: Codable {
    var title: String
    var summary: String?
    var sourceURL: String?
    var cookbook: String?
    var imageURL: String?
    var servings: Int
    var prepTimeMinutes: Int
    var cookTimeMinutes: Int
    var instructions: [String]
    var tags: [String]
    var suggestedArchetypes: [String]
    var ingredients: [CodableIngredient]
    var isFavorite: Bool
    var imageDataBase64: String?

    init(from recipe: Recipe) {
        self.title = recipe.title
        self.summary = recipe.summary
        self.sourceURL = recipe.sourceURL?.absoluteString
        self.cookbook = recipe.cookbook
        self.imageURL = recipe.imageURL?.absoluteString
        self.servings = Int(recipe.servings)
        self.prepTimeMinutes = Int(recipe.prepTimeMinutes)
        self.cookTimeMinutes = Int(recipe.cookTimeMinutes)
        self.instructions = recipe.instructionsList
        self.tags = recipe.tagsList
        self.suggestedArchetypes = recipe.suggestedArchetypes.map(\.rawValue)
        self.ingredients = recipe.recipeIngredientsArray.map { CodableIngredient(from: $0) }
        self.isFavorite = recipe.isFavorite
        self.imageDataBase64 = recipe.imageData?.base64EncodedString()
    }

    /// Create a CoreData Recipe from this portable representation.
    ///
    /// When `resolver` is non-nil, each created `RecipeIngredient` is linked to
    /// an `Ingredient` master record via the resolver. When nil (e.g. legacy
    /// callers, simple tests), `RecipeIngredient.ingredient` stays nil and only
    /// `customName` is populated — matching the previous behaviour.
    ///
    /// `@MainActor` is required because `RecipeIngredientResolver` is main-actor
    /// isolated (it walks `NSManagedObjectContext` which is single-threaded per
    /// context). Both existing call sites (`JSONRecipeImporter`, the curated
    /// JSON import path) are already on the main actor.
    @MainActor
    @discardableResult
    func toRecipe(
        context: NSManagedObjectContext,
        household: Household?,
        resolver: RecipeIngredientResolver? = nil
    ) -> Recipe {
        let recipe = Recipe(
            context: context,
            title: title,
            summary: summary,
            sourceURL: sourceURL.flatMap { URL(string: $0) },
            cookbook: cookbook,
            imageURL: imageURL.flatMap { URL(string: $0) },
            servings: servings,
            prepTimeMinutes: prepTimeMinutes > 0 ? prepTimeMinutes : nil,
            cookTimeMinutes: cookTimeMinutes > 0 ? cookTimeMinutes : nil,
            instructions: instructions,
            tags: tags,
            suggestedArchetypes: suggestedArchetypes.compactMap { ArchetypeType(rawValue: $0) },
            imageData: imageDataBase64.flatMap { Data(base64Encoded: $0) },
            isFavorite: isFavorite
        )
        recipe.household = household

        for (index, codableIngredient) in ingredients.enumerated() {
            codableIngredient.toRecipeIngredient(
                context: context,
                recipe: recipe,
                order: index,
                resolver: resolver
            )
        }

        return recipe
    }
}

/// A portable, Codable representation of a RecipeIngredient.
struct CodableIngredient: Codable {
    var name: String
    var quantity: Double
    var unit: String
    var preparationNote: String?
    var isOptional: Bool

    init(from recipeIngredient: RecipeIngredient) {
        self.name = recipeIngredient.displayName
        self.quantity = recipeIngredient.quantity
        self.unit = recipeIngredient.unitRaw
        self.preparationNote = recipeIngredient.preparationNote
        self.isOptional = recipeIngredient.isOptional
    }

    @MainActor
    @discardableResult
    func toRecipeIngredient(
        context: NSManagedObjectContext,
        recipe: Recipe,
        order: Int,
        resolver: RecipeIngredientResolver? = nil
    ) -> RecipeIngredient {
        let ri = RecipeIngredient(
            context: context,
            quantity: quantity,
            unit: MeasurementUnit(rawValue: unit) ?? .gram,
            preparationNote: preparationNote,
            isOptional: isOptional,
            order: order,
            customName: name
        )
        ri.recipe = recipe
        if let resolver, let master = resolver.resolve(name) {
            ri.ingredient = master
        }
        return ri
    }
}
