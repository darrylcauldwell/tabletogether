import SwiftUI
import SwiftData

/// Full recipe detail view with hero image, servings adjuster, macro summary,
/// scaled ingredients, instructions, and action buttons.
struct RecipeDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @Bindable var recipe: Recipe

    @State private var adjustedServings: Int
    @State private var isMacroExpanded = false
    @State private var showingEditor = false
    @State private var showingAddToPlanSheet = false
    @State private var isCookingMode = false

    init(recipe: Recipe) {
        self.recipe = recipe
        _adjustedServings = State(initialValue: recipe.servings)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Hero Image with Title Overlay
                heroImageSection

                VStack(spacing: 24) {
                    // Recipe Meta Row
                    recipeMetaRow

                    // Macro Summary Card
                    if recipe.macrosPerServing != nil {
                        macroSummaryCard
                    }

                    // Ingredients Section
                    ingredientsSection

                    // Instructions Section
                    instructionsSection

                    // Action Buttons
                    actionButtons

                    Spacer(minLength: 40)
                }
                .padding(.horizontal)
            }
        }
        .background(Color.appBackground)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 16) {
                    Button {
                        recipe.isFavorite.toggle()
                        recipe.modifiedAt = Date()
                    } label: {
                        Image(systemName: recipe.isFavorite ? "heart.fill" : "heart")
                            .foregroundColor(recipe.isFavorite ? .appSecondary : .appTextSecondary)
                    }

                    Button {
                        showingEditor = true
                    } label: {
                        Image(systemName: "pencil")
                            .foregroundColor(.appPrimary)
                    }
                }
            }
            #else
            ToolbarItem(placement: .automatic) {
                HStack(spacing: 16) {
                    Button {
                        recipe.isFavorite.toggle()
                        recipe.modifiedAt = Date()
                    } label: {
                        Image(systemName: recipe.isFavorite ? "heart.fill" : "heart")
                            .foregroundColor(recipe.isFavorite ? .appSecondary : .appTextSecondary)
                    }

                    Button {
                        showingEditor = true
                    } label: {
                        Image(systemName: "pencil")
                            .foregroundColor(.appPrimary)
                    }
                }
            }
            #endif
        }
        .sheet(isPresented: $showingEditor) {
            NavigationStack {
                RecipeEditorView(recipe: recipe)
            }
        }
        .sheet(isPresented: $showingAddToPlanSheet) {
            AddToPlanSheet(recipe: recipe, servings: adjustedServings)
        }
        #if os(iOS)
        .fullScreenCover(isPresented: $isCookingMode) {
            CookingModeView(recipe: recipe, servings: adjustedServings)
        }
        #else
        .sheet(isPresented: $isCookingMode) {
            CookingModeView(recipe: recipe, servings: adjustedServings)
        }
        #endif
    }

    // MARK: - Hero Image Section

    private var heroImageSection: some View {
        ZStack(alignment: .bottomLeading) {
            // Image
            #if canImport(UIKit)
            if let imageData = recipe.imageData,
               let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 280)
                    .clipped()
            } else {
                imagePlaceholder
            }
            #elseif canImport(AppKit)
            if let imageData = recipe.imageData,
               let nsImage = NSImage(data: imageData) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 280)
                    .clipped()
            } else {
                imagePlaceholder
            }
            #endif

            // Gradient overlay
            LinearGradient(
                colors: [.clear, .black.opacity(0.6)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 140)
            .frame(maxWidth: .infinity, alignment: .bottom)

            // Title overlay
            VStack(alignment: .leading, spacing: 4) {
                Text(recipe.title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)

                if let sourceURL = recipe.sourceURL {
                    Button {
                        openURL(sourceURL)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "link")
                                .font(.caption)
                            Text(sourceURL.host ?? "Source")
                                .font(.caption)
                        }
                        .foregroundColor(.white.opacity(0.8))
                    }
                }
            }
            .padding()
        }
    }

    private var imagePlaceholder: some View {
        ZStack {
            Color.appPrimary.opacity(0.15)
            Image(systemName: "fork.knife")
                .font(.system(size: 64))
                .foregroundColor(.appPrimary.opacity(0.4))
        }
        .frame(height: 280)
    }

    // MARK: - Recipe Meta Row

    private var recipeMetaRow: some View {
        VStack(spacing: 12) {
            // Servings Adjuster
            ServingsAdjuster(servings: $adjustedServings)

            // Time and Archetype chips - wrapping flow layout
            FlowLayout(spacing: 8) {
                if let prepTime = recipe.formattedPrepTime {
                    chipView(icon: "clock", text: prepTime)
                }

                if let cookTime = recipe.formattedCookTime {
                    chipView(icon: "flame", text: cookTime)
                }

                ForEach(recipe.suggestedArchetypes.prefix(3)) { archetype in
                    ArchetypeBadge(archetype: archetype)
                }
            }
        }
        .padding(.top, 16)
    }

    private func chipView(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
            Text(text)
                .font(.caption)
        }
        .chipStyle(color: .appTextSecondary)
    }

    // MARK: - Macro Summary Card

    private var macroSummaryCard: some View {
        VStack(spacing: 0) {
            // Header
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isMacroExpanded.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: "chart.pie")
                        .foregroundColor(.appPrimary)
                    Text("Nutrition (per serving)")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.appTextPrimary)
                    Spacer()
                    Image(systemName: isMacroExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.appTextSecondary)
                }
                .padding()
            }

            if isMacroExpanded, let macros = recipe.macrosForServings(adjustedServings) {
                Divider()
                    .padding(.horizontal)

                HStack(spacing: 0) {
                    macroItem(label: "Calories", value: macros.formattedCalories, unit: "")
                    Divider()
                        .frame(height: 40)
                    macroItem(label: "Protein", value: macros.protein.map { String(format: "%.0f", $0) } ?? "--", unit: "g")
                    Divider()
                        .frame(height: 40)
                    macroItem(label: "Carbs", value: macros.carbs.map { String(format: "%.0f", $0) } ?? "--", unit: "g")
                    Divider()
                        .frame(height: 40)
                    macroItem(label: "Fat", value: macros.fat.map { String(format: "%.0f", $0) } ?? "--", unit: "g")
                }
                .padding()
            }
        }
        .cardStyle()
    }

    private func macroItem(label: String, value: String, unit: String) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.appTextSecondary)
            HStack(spacing: 2) {
                Text(value)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.appTextPrimary)
                Text(unit)
                    .font(.caption)
                    .foregroundColor(.appTextSecondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Ingredients Section

    private var ingredientsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "list.bullet")
                    .foregroundColor(.appPrimary)
                Text("Ingredients")
                    .font(.headline)
                    .foregroundColor(.appTextPrimary)

                Spacer()

                Text("for \(adjustedServings) servings")
                    .font(.caption)
                    .foregroundColor(.appTextSecondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(recipe.sortedIngredients) { ingredient in
                    IngredientRow(
                        ingredient: ingredient,
                        servings: adjustedServings,
                        baseServings: recipe.servings
                    )
                }

                if recipe.recipeIngredients.isEmpty {
                    Text("No ingredients added yet.")
                        .font(.body)
                        .foregroundColor(.appTextSecondary)
                        .italic()
                }
            }
        }
        .padding()
        .cardStyle()
    }

    // MARK: - Instructions Section

    private var instructionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "text.justify.leading")
                    .foregroundColor(.appPrimary)
                Text("Instructions")
                    .font(.headline)
                    .foregroundColor(.appTextPrimary)
            }

            VStack(alignment: .leading, spacing: 16) {
                if recipe.instructions.isEmpty {
                    Text("No instructions added yet.")
                        .font(.body)
                        .foregroundColor(.appTextSecondary)
                        .italic()
                } else {
                    ForEach(Array(recipe.instructions.enumerated()), id: \.offset) { index, instruction in
                        InstructionStepView(stepNumber: index + 1, text: instruction)
                    }
                }
            }
        }
        .padding()
        .cardStyle()
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button {
                showingAddToPlanSheet = true
            } label: {
                HStack {
                    Image(systemName: "calendar.badge.plus")
                    Text("Add to Plan")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())

            Button {
                isCookingMode = true
            } label: {
                HStack {
                    Image(systemName: "play.fill")
                    Text("Start Cooking")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryButtonStyle())
        }
        .padding(.top, 8)
    }
}

// Note: ServingsAdjuster component is defined in Components.swift

// MARK: - Ingredient Row

struct IngredientRow: View {
    let ingredient: RecipeIngredient
    let servings: Int
    let baseServings: Int

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(ingredient.formattedScaledQuantity(for: servings, baseServings: baseServings))
                .font(.body)
                .fontWeight(.medium)
                .foregroundColor(.appPrimary)
                .frame(width: 80, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(ingredient.displayName)
                        .font(.body)
                        .foregroundColor(.appTextPrimary)

                    if ingredient.isOptional {
                        Text("(optional)")
                            .font(.caption)
                            .foregroundColor(.appTextSecondary)
                    }
                }

                if let note = ingredient.preparationNote, !note.isEmpty {
                    Text(note)
                        .font(.caption)
                        .foregroundColor(.appTextSecondary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(ingredientAccessibilityLabel)
    }

    private var ingredientAccessibilityLabel: String {
        var parts: [String] = []
        parts.append(ingredient.formattedScaledQuantity(for: servings, baseServings: baseServings))
        parts.append(ingredient.displayName)

        if ingredient.isOptional {
            parts.append("optional")
        }

        if let note = ingredient.preparationNote, !note.isEmpty {
            parts.append(note)
        }

        return parts.joined(separator: ", ")
    }
}

// MARK: - Instruction Step View

struct InstructionStepView: View {
    let stepNumber: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(stepNumber)")
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
                .background(Color.appPrimary)
                .clipShape(Circle())

            Text(text)
                .font(.body)
                .foregroundColor(.appTextPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(stepNumber): \(text)")
    }
}

// MARK: - Add to Plan Sheet (Placeholder)

struct AddToPlanSheet: View {
    let recipe: Recipe
    let servings: Int

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Add \"\(recipe.title)\" to your meal plan")
                    .font(.headline)
                    .multilineTextAlignment(.center)

                Text("This feature will be available when the planning module is complete.")
                    .font(.body)
                    .foregroundColor(.appTextSecondary)
                    .multilineTextAlignment(.center)

                Button("Done") {
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            .padding()
            .navigationTitle("Add to Plan")
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
        }
        .presentationDetents([.medium])
    }
}

// Note: CookingModeView is defined in CookingModeView.swift

// MARK: - Preview

private struct RecipeDetailPreviewContent: View {
    @State private var recipe: Recipe?

    var body: some View {
        Group {
            if let recipe = recipe {
                NavigationStack {
                    RecipeDetailView(recipe: recipe)
                }
            } else {
                ProgressView("Loading...")
            }
        }
        .task {
            let newRecipe = Recipe(
                title: "Chicken Stir Fry with Vegetables",
                summary: "A quick and healthy stir fry packed with colorful vegetables and tender chicken.",
                servings: 4,
                prepTimeMinutes: 15,
                cookTimeMinutes: 20,
                instructions: [
                    "Cut chicken breast into bite-sized pieces and season with salt and pepper.",
                    "Heat oil in a large wok or skillet over high heat.",
                    "Add chicken and stir-fry until golden brown, about 5-6 minutes. Remove and set aside.",
                    "Add vegetables to the wok and stir-fry for 3-4 minutes until crisp-tender.",
                    "Return chicken to the wok and add the sauce. Toss to combine.",
                    "Serve immediately over steamed rice."
                ],
                suggestedArchetypes: [.quickWeeknight, .familyFavorite],
                isFavorite: true
            )

            let ingredients = [
                RecipeIngredient(quantity: 1, unit: .kilogram, order: 0, customName: "Chicken breast"),
                RecipeIngredient(quantity: 2, unit: .tablespoon, order: 1, customName: "Soy sauce"),
                RecipeIngredient(quantity: 1, unit: .tablespoon, order: 2, customName: "Sesame oil"),
                RecipeIngredient(quantity: 2, unit: .cup, order: 3, customName: "Broccoli florets"),
                RecipeIngredient(quantity: 1, unit: .piece, preparationNote: "sliced", order: 4, customName: "Bell pepper"),
                RecipeIngredient(quantity: 3, unit: .clove, preparationNote: "minced", order: 5, customName: "Garlic")
            ]

            ingredients.forEach { newRecipe.recipeIngredients.append($0) }
            recipe = newRecipe
        }
    }
}

#Preview {
    RecipeDetailPreviewContent()
        .modelContainer(for: [Recipe.self, RecipeIngredient.self, Ingredient.self], inMemory: true)
}
