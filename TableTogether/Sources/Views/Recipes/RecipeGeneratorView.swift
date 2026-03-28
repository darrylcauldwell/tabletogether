import SwiftUI
import CoreData

/// A view for generating recipes based on user preferences including
/// ingredients, cooking style, time availability, and cuisine type.
struct RecipeGeneratorView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @FetchRequest(sortDescriptors: []) private var households: FetchedResults<Household>
    @State private var generatorService = RecipeGeneratorService()

    // Form state
    @State private var prompt = RecipeGeneratorPrompt()
    @State private var newIngredientText = ""
    @State private var recipesToGenerate = 1

    // UI state
    @State private var showingResults = false
    @State private var selectedRecipe: GeneratedRecipe?

    @FetchRequest(sortDescriptors: []) private var existingIngredients: FetchedResults<Ingredient>

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    // Header
                    headerSection

                    // Ingredients Input
                    ingredientsSection

                    // Cooking Style
                    cookingStyleSection

                    // Time Availability
                    timeSection

                    // Cuisine Selection
                    cuisineSection

                    // Dietary Preferences
                    dietarySection

                    // Servings
                    servingsSection

                    // Additional Notes
                    notesSection

                    // Generate Button
                    generateButton
                }
                .padding()
            }
            .navigationTitle("Generate Recipe")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingResults) {
                GeneratedRecipeResultsView(
                    recipes: generatorService.generatedRecipes,
                    onSave: saveRecipe,
                    onRegenerate: regenerateRecipes,
                    onDismiss: { showingResults = false }
                )
            }
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 40))
                .foregroundStyle(Theme.Colors.primary)

            Text("What would you like to cook?")
                .font(Theme.Typography.title3)
                .foregroundStyle(Theme.Colors.textPrimary)

            Text("Tell us what you have and how you'd like to cook, and we'll create a recipe for you.")
                .font(Theme.Typography.subheadline)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.bottom, Theme.Spacing.md)
    }

    // MARK: - Ingredients Section

    private var ingredientsSection: some View {
        GeneratorSection(title: "Ingredients", subtitle: "What do you have on hand?") {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                // Ingredient chips
                if !prompt.ingredients.isEmpty {
                    FlowLayout(spacing: 8) {
                        ForEach(prompt.ingredients, id: \.self) { ingredient in
                            IngredientChip(name: ingredient) {
                                prompt.ingredients.removeAll { $0 == ingredient }
                            }
                        }
                    }
                }

                // Add ingredient field
                HStack {
                    TextField("Add ingredient...", text: $newIngredientText)
                        #if os(iOS)
                        .textFieldStyle(.roundedBorder)
                        #endif
                        .onSubmit {
                            addIngredient()
                        }

                    Button {
                        addIngredient()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundStyle(Theme.Colors.primary)
                    }
                    .disabled(newIngredientText.isEmpty)
                }

                // Quick suggestions from existing ingredients
                if !existingIngredients.isEmpty && prompt.ingredients.count < 5 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(existingIngredients.prefix(8)) { ingredient in
                                if !prompt.ingredients.contains(ingredient.name.lowercased()) {
                                    Button {
                                        prompt.ingredients.append(ingredient.name.lowercased())
                                    } label: {
                                        Text(ingredient.name)
                                            .font(.caption)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(Color.systemGray6)
                                            .clipShape(Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func addIngredient() {
        let trimmed = newIngredientText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty, !prompt.ingredients.contains(trimmed) else {
            newIngredientText = ""
            return
        }
        prompt.ingredients.append(trimmed)
        newIngredientText = ""
    }

    // MARK: - Cooking Style Section

    private var cookingStyleSection: some View {
        GeneratorSection(title: "Cooking Style", subtitle: "How do you want to cook?") {
            HStack(spacing: Theme.Spacing.md) {
                ForEach(CookingStyle.allCases) { style in
                    StyleSelectionCard(
                        title: style.displayName,
                        description: style.description,
                        icon: style.iconName,
                        isSelected: prompt.cookingStyle == style,
                        action: { prompt.cookingStyle = style }
                    )
                }
            }
        }
    }

    // MARK: - Time Section

    private var timeSection: some View {
        GeneratorSection(title: "Time Available", subtitle: "How much time do you have?") {
            HStack(spacing: Theme.Spacing.sm) {
                ForEach(TimeAvailability.allCases) { time in
                    TimeSelectionChip(
                        time: time,
                        isSelected: prompt.timeAvailability == time,
                        action: { prompt.timeAvailability = time }
                    )
                }
            }
        }
    }

    // MARK: - Cuisine Section

    private var cuisineSection: some View {
        GeneratorSection(title: "Cuisine", subtitle: "What flavors are you in the mood for?") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 8) {
                ForEach(CuisineType.allCases) { cuisine in
                    CuisineSelectionChip(
                        cuisine: cuisine,
                        isSelected: prompt.cuisines.contains(cuisine),
                        action: {
                            if prompt.cuisines.contains(cuisine) {
                                prompt.cuisines.remove(cuisine)
                            } else {
                                prompt.cuisines.insert(cuisine)
                            }
                        }
                    )
                }
            }
        }
    }

    // MARK: - Dietary Section

    private var dietarySection: some View {
        GeneratorSection(title: "Dietary Preferences", subtitle: "Any restrictions?") {
            FlowLayout(spacing: 8) {
                ForEach(DietaryPreference.allCases.filter { $0 != .none }) { pref in
                    DietaryChip(
                        preference: pref,
                        isSelected: prompt.dietaryPreferences.contains(pref),
                        action: {
                            if prompt.dietaryPreferences.contains(pref) {
                                prompt.dietaryPreferences.remove(pref)
                            } else {
                                prompt.dietaryPreferences.insert(pref)
                            }
                        }
                    )
                }
            }
        }
    }

    // MARK: - Servings Section

    private var servingsSection: some View {
        GeneratorSection(title: "Servings", subtitle: "How many people are you cooking for?") {
            ServingsAdjuster(servings: $prompt.servings, minServings: 1, maxServings: 12)
        }
    }

    // MARK: - Notes Section

    private var notesSection: some View {
        GeneratorSection(title: "Additional Notes", subtitle: "Anything else we should know?") {
            TextField("e.g., make it spicy, kid-friendly, use up leftovers...", text: $prompt.additionalNotes, axis: .vertical)
                .lineLimit(2...4)
                #if os(iOS)
                .textFieldStyle(.roundedBorder)
                #endif
        }
    }

    // MARK: - Generate Button

    private var generateButton: some View {
        VStack(spacing: Theme.Spacing.md) {
            // Recipe count selector
            HStack {
                Text("Generate")
                    .foregroundStyle(Theme.Colors.textSecondary)

                Picker("Recipes", selection: $recipesToGenerate) {
                    Text("1 recipe").tag(1)
                    Text("2 recipes").tag(2)
                    Text("3 recipes").tag(3)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 200)
            }

            // Generate button
            Button {
                generateRecipes()
            } label: {
                HStack {
                    if generatorService.isGenerating {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "wand.and.stars")
                    }
                    Text(generatorService.isGenerating ? "Creating your recipe..." : "Generate Recipe")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(prompt.isValid ? Theme.Colors.primary : Theme.Colors.textSecondary)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
            }
            .disabled(!prompt.isValid || generatorService.isGenerating)

            // Prompt summary
            if prompt.isValid {
                Text(prompt.summary)
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }

            // Error message
            if let error = generatorService.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.top, Theme.Spacing.md)
    }

    // MARK: - Actions

    private func generateRecipes() {
        Task {
            await generatorService.generateRecipes(from: prompt, count: recipesToGenerate)
            if !generatorService.generatedRecipes.isEmpty {
                showingResults = true
            }
        }
    }

    private func regenerateRecipes() {
        Task {
            await generatorService.generateRecipes(from: prompt, count: recipesToGenerate)
        }
    }

    private func saveRecipe(_ generated: GeneratedRecipe) {
        // Create a new Recipe from the generated recipe (convenience init inserts into context)
        let recipe = Recipe(
            context: viewContext,
            title: generated.title,
            summary: generated.summary,
            servings: generated.servings,
            prepTimeMinutes: generated.prepTimeMinutes,
            cookTimeMinutes: generated.cookTimeMinutes,
            instructions: generated.instructions,
            tags: generated.tags,
            suggestedArchetypes: generated.suggestedArchetypes
        )

        // Add ingredients
        for (index, genIngredient) in generated.ingredients.enumerated() {
            let recipeIngredient = RecipeIngredient(
                context: viewContext,
                quantity: genIngredient.quantity,
                unit: genIngredient.unit,
                preparationNote: genIngredient.preparationNote,
                isOptional: genIngredient.isOptional,
                order: index,
                customName: genIngredient.name
            )
            recipe.addToRecipeIngredients(recipeIngredient)
        }

        recipe.household = households.first

        showingResults = false
        dismiss()
    }
}

// MARK: - Preview

#Preview("Recipe Generator") {
    RecipeGeneratorView()
        .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
}
