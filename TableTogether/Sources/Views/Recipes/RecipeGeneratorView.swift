import SwiftUI
import SwiftData

/// A view for generating recipes based on user preferences including
/// ingredients, cooking style, time availability, and cuisine type.
struct RecipeGeneratorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query private var households: [Household]
    @StateObject private var generatorService = RecipeGeneratorService()

    // Form state
    @State private var prompt = RecipeGeneratorPrompt()
    @State private var newIngredientText = ""
    @State private var recipesToGenerate = 1

    // UI state
    @State private var showingResults = false
    @State private var selectedRecipe: GeneratedRecipe?

    @Query private var existingIngredients: [Ingredient]

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
        // Create a new Recipe from the generated recipe
        let recipe = Recipe(
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
                quantity: genIngredient.quantity,
                unit: genIngredient.unit,
                preparationNote: genIngredient.preparationNote,
                isOptional: genIngredient.isOptional,
                order: index,
                customName: genIngredient.name
            )
            recipe.recipeIngredients.append(recipeIngredient)
        }

        recipe.household = households.first
        modelContext.insert(recipe)

        showingResults = false
        dismiss()
    }
}

// MARK: - Generator Section

struct GeneratorSection<Content: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder let content: () -> Content

    init(title: String, subtitle: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Ingredient Chip

struct IngredientChip: View {
    let name: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(name.capitalized)
                .font(.subheadline)
                .foregroundStyle(Theme.Colors.textPrimary)

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.Colors.primary.opacity(0.15))
        .clipShape(Capsule())
    }
}

// MARK: - Style Selection Card

struct StyleSelectionCard: View {
    let title: String
    let description: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: Theme.Spacing.sm) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(isSelected ? Theme.Colors.primary : Theme.Colors.textSecondary)

                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(Theme.Colors.textPrimary)

                Text(description)
                    .font(.caption2)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(isSelected ? Theme.Colors.primary.opacity(0.1) : Color.systemGray6)
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.standard))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.standard)
                    .stroke(isSelected ? Theme.Colors.primary : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Time Selection Chip

struct TimeSelectionChip: View {
    let time: TimeAvailability
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: time.iconName)
                    .font(.title3)

                Text(time.displayName)
                    .font(.caption)
                    .fontWeight(.medium)

                Text(time.description)
                    .font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.md)
            .background(isSelected ? Theme.Colors.primary.opacity(0.15) : Color.systemGray6)
            .foregroundStyle(isSelected ? Theme.Colors.primary : Theme.Colors.textSecondary)
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                    .stroke(isSelected ? Theme.Colors.primary : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Cuisine Selection Chip

struct CuisineSelectionChip: View {
    let cuisine: CuisineType
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: cuisine.iconName)
                    .font(.caption)
                Text(cuisine.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(isSelected ? Color(hex: cuisine.colorHex).opacity(0.2) : Color.systemGray6)
            .foregroundStyle(isSelected ? Color(hex: cuisine.colorHex) : Theme.Colors.textSecondary)
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                    .stroke(isSelected ? Color(hex: cuisine.colorHex) : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Dietary Chip

struct DietaryChip: View {
    let preference: DietaryPreference
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: preference.iconName)
                    .font(.caption)
                Text(preference.displayName)
                    .font(.caption)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? Theme.Colors.primary.opacity(0.15) : Color.systemGray6)
            .foregroundStyle(isSelected ? Theme.Colors.primary : Theme.Colors.textSecondary)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(isSelected ? Theme.Colors.primary : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Generated Recipe Results View

struct GeneratedRecipeResultsView: View {
    let recipes: [GeneratedRecipe]
    let onSave: (GeneratedRecipe) -> Void
    let onRegenerate: () -> Void
    let onDismiss: () -> Void

    @State private var selectedRecipeIndex = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Recipe selector if multiple
                if recipes.count > 1 {
                    Picker("Recipe", selection: $selectedRecipeIndex) {
                        ForEach(Array(recipes.enumerated()), id: \.offset) { index, recipe in
                            Text("Option \(index + 1)").tag(index)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding()
                }

                // Recipe preview
                if selectedRecipeIndex < recipes.count {
                    GeneratedRecipePreview(recipe: recipes[selectedRecipeIndex])
                }

                Spacer()

                // Action buttons
                VStack(spacing: Theme.Spacing.sm) {
                    Button {
                        if selectedRecipeIndex < recipes.count {
                            onSave(recipes[selectedRecipeIndex])
                        }
                    } label: {
                        Label("Save to My Recipes", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Theme.Colors.primary)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
                    }

                    Button {
                        onRegenerate()
                    } label: {
                        Label("Generate Again", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.systemGray6)
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
                    }
                }
                .padding()
            }
            .navigationTitle("Your Recipe")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onDismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Generated Recipe Preview

struct GeneratedRecipePreview: View {
    let recipe: GeneratedRecipe

    @State private var expandedSections: Set<String> = ["ingredients", "instructions"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                // Header
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    HStack {
                        Text(recipe.title)
                            .font(Theme.Typography.title2)
                            .foregroundStyle(Theme.Colors.textPrimary)

                        Spacer()

                        // Cooking style badge
                        HStack(spacing: 4) {
                            Image(systemName: recipe.cookingStyle.iconName)
                            Text(recipe.cookingStyle.displayName)
                        }
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Theme.Colors.secondary.opacity(0.2))
                        .foregroundStyle(Theme.Colors.secondary)
                        .clipShape(Capsule())
                    }

                    Text(recipe.summary)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }

                // Quick info row
                HStack(spacing: Theme.Spacing.lg) {
                    QuickInfoItem(icon: "clock", value: recipe.formattedTotalTime)
                    QuickInfoItem(icon: "person.2", value: "\(recipe.servings) servings")
                    if let cuisine = recipe.cuisineType {
                        QuickInfoItem(icon: cuisine.iconName, value: cuisine.displayName)
                    }
                }
                .padding()
                .background(Color.systemGray6)
                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))

                // Archetypes
                if !recipe.suggestedArchetypes.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(recipe.suggestedArchetypes, id: \.self) { archetype in
                            ArchetypeBadge(archetype: archetype, compact: true)
                        }
                    }
                }

                // Collapsible Ingredients Section
                CollapsibleSection(
                    title: "Ingredients",
                    icon: "basket",
                    isExpanded: expandedSections.contains("ingredients"),
                    toggle: { toggleSection("ingredients") }
                ) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(recipe.ingredients) { ingredient in
                            HStack {
                                Circle()
                                    .fill(Theme.Colors.primary)
                                    .frame(width: 6, height: 6)

                                Text(formatIngredient(ingredient))
                                    .font(Theme.Typography.body)

                                Spacer()

                                if ingredient.isOptional {
                                    Text("optional")
                                        .font(.caption)
                                        .foregroundStyle(Theme.Colors.textSecondary)
                                }
                            }
                        }
                    }
                }

                // Collapsible Instructions Section
                CollapsibleSection(
                    title: "Instructions",
                    icon: "list.number",
                    isExpanded: expandedSections.contains("instructions"),
                    toggle: { toggleSection("instructions") }
                ) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                        ForEach(Array(recipe.instructions.enumerated()), id: \.offset) { index, instruction in
                            HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                                Text("\(index + 1)")
                                    .font(.headline)
                                    .foregroundStyle(Theme.Colors.primary)
                                    .frame(width: 24)

                                Text(instruction)
                                    .font(Theme.Typography.body)
                            }
                        }
                    }
                }

                // Tags
                if !recipe.tags.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(recipe.tags, id: \.self) { tag in
                            Text("#\(tag)")
                                .font(.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                    }
                }
            }
            .padding()
        }
    }

    private func formatIngredient(_ ingredient: GeneratedRecipe.GeneratedIngredient) -> String {
        let quantityStr = ingredient.quantity == floor(ingredient.quantity)
            ? String(format: "%.0f", ingredient.quantity)
            : String(format: "%.1f", ingredient.quantity)

        var result = "\(quantityStr) \(ingredient.unit.abbreviation) \(ingredient.name)"

        if let prep = ingredient.preparationNote {
            result += ", \(prep)"
        }

        return result
    }

    private func toggleSection(_ section: String) {
        if expandedSections.contains(section) {
            expandedSections.remove(section)
        } else {
            expandedSections.insert(section)
        }
    }
}

// MARK: - Quick Info Item

struct QuickInfoItem: View {
    let icon: String
    let value: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(Theme.Colors.textPrimary)
        }
    }
}

// MARK: - Collapsible Section

struct CollapsibleSection<Content: View>: View {
    let title: String
    let icon: String
    let isExpanded: Bool
    let toggle: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Button(action: toggle) {
                HStack {
                    Image(systemName: icon)
                        .foregroundStyle(Theme.Colors.primary)
                    Text(title)
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                content()
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding()
        .background(Color.systemGray6.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.standard))
        .animation(Theme.Animation.standard, value: isExpanded)
    }
}

// MARK: - Preview

#Preview("Recipe Generator") {
    RecipeGeneratorView()
        .modelContainer(for: [Recipe.self, RecipeIngredient.self, Ingredient.self], inMemory: true)
}
