import SwiftUI
import SwiftData

/// A sheet view for importing recipes from URLs.
/// Displays URL input, parsed recipe preview, archetype selection, and confirm import button.
struct RecipeImportSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query private var households: [Household]
    @StateObject private var parser = RecipeParser()

    @State private var urlString = ""
    @State private var parsedRecipe: ParsedRecipe?
    @State private var editableTitle = ""
    @State private var editableServings = 4
    @State private var editableIngredients: [EditableIngredient] = []
    @State private var editableInstructions: [String] = []
    @State private var selectedArchetypes: Set<ArchetypeType> = []
    @State private var showingError = false
    @State private var errorMessage = ""

    // For tracking editing state
    struct EditableIngredient: Identifiable {
        let id = UUID()
        var original: ParsedIngredient
        var displayText: String
        var isIncluded: Bool = true
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // URL Input Section
                    urlInputSection

                    if parser.isLoading {
                        loadingView
                    } else if parsedRecipe != nil {
                        // Parsed Recipe Preview
                        parsedRecipePreview

                        // Archetype Selection
                        archetypeSelectionSection

                        // Confirm Import Button
                        importButton
                    }
                }
                .padding()
            }
            .background(Color.appBackground)
            .navigationTitle("Import Recipe")
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
            .alert("Import Error", isPresented: $showingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
    }

    // MARK: - URL Input Section

    private var urlInputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recipe URL")
                .font(.headline)
                .foregroundColor(.appTextPrimary)

            HStack {
                TextField("https://example.com/recipe", text: $urlString)
                    .textFieldStyle(.plain)
                    #if os(iOS)
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .autocapitalization(.none)
                    #endif
                    .autocorrectionDisabled()

                if !urlString.isEmpty {
                    Button {
                        urlString = ""
                        parsedRecipe = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.appTextSecondary)
                    }
                }
            }
            .padding()
            .background(Color.systemGray6)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            Button {
                Task {
                    await parseURL()
                }
            } label: {
                HStack {
                    Image(systemName: "arrow.down.doc")
                    Text("Fetch Recipe")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(urlString.isEmpty || parser.isLoading)

            Text("Paste a URL from your favorite recipe website. We support most sites that use standard recipe formats.")
                .font(.caption)
                .foregroundColor(.appTextSecondary)
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)

            Text("Parsing recipe...")
                .font(.subheadline)
                .foregroundColor(.appTextSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Parsed Recipe Preview

    @ViewBuilder
    private var parsedRecipePreview: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Title Section
            VStack(alignment: .leading, spacing: 8) {
                Text("Title")
                    .font(.headline)
                    .foregroundColor(.appTextPrimary)

                TextField("Recipe title", text: $editableTitle)
                    .textFieldStyle(.plain)
                    .padding()
                    .background(Color.systemGray6)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            // Servings Section
            VStack(alignment: .leading, spacing: 8) {
                Text("Servings")
                    .font(.headline)
                    .foregroundColor(.appTextPrimary)

                HStack {
                    #if os(iOS)
                    Stepper(value: $editableServings, in: 1...50) {
                        Text("\(editableServings) servings")
                            .font(.body)
                    }
                    #else
                    // tvOS-compatible stepper alternative
                    HStack(spacing: 12) {
                        Button { if editableServings > 1 { editableServings -= 1 } } label: {
                            Image(systemName: "minus.circle.fill")
                                .font(.title3)
                        }
                        .buttonStyle(.plain)
                        Text("\(editableServings) servings")
                            .font(.body)
                        Button { if editableServings < 50 { editableServings += 1 } } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                        }
                        .buttonStyle(.plain)
                    }
                    #endif
                }
                .padding()
                .background(Color.systemGray6)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            // Time Info
            if let recipe = parsedRecipe {
                HStack(spacing: 16) {
                    if let prepTime = recipe.prepTimeMinutes {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.caption)
                            Text("\(prepTime) min prep")
                                .font(.caption)
                        }
                        .chipStyle(color: .appTextSecondary)
                    }

                    if let cookTime = recipe.cookTimeMinutes {
                        HStack(spacing: 4) {
                            Image(systemName: "flame")
                                .font(.caption)
                            Text("\(cookTime) min cook")
                                .font(.caption)
                        }
                        .chipStyle(color: .appTextSecondary)
                    }
                }
            }

            // Ingredients Section
            ingredientsPreviewSection

            // Instructions Section
            instructionsPreviewSection
        }
        .cardStyle()
        .padding(.horizontal, -16)
        .padding()
    }

    // MARK: - Ingredients Preview Section

    private var ingredientsPreviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Ingredients")
                    .font(.headline)
                    .foregroundColor(.appTextPrimary)

                Spacer()

                Text("\(editableIngredients.filter { $0.isIncluded }.count) items")
                    .font(.caption)
                    .foregroundColor(.appTextSecondary)
            }

            if editableIngredients.isEmpty {
                Text("No ingredients found. You can add them after importing.")
                    .font(.body)
                    .foregroundColor(.appTextSecondary)
                    .italic()
            } else {
                ForEach($editableIngredients) { $ingredient in
                    HStack {
                        Button {
                            ingredient.isIncluded.toggle()
                        } label: {
                            Image(systemName: ingredient.isIncluded ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(ingredient.isIncluded ? .appPrimary : .appTextSecondary)
                        }

                        TextField("Ingredient", text: $ingredient.displayText)
                            .font(.body)
                            .foregroundColor(ingredient.isIncluded ? .appTextPrimary : .appTextSecondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    // MARK: - Instructions Preview Section

    private var instructionsPreviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Instructions")
                    .font(.headline)
                    .foregroundColor(.appTextPrimary)

                Spacer()

                Text("\(editableInstructions.count) steps")
                    .font(.caption)
                    .foregroundColor(.appTextSecondary)
            }

            if editableInstructions.isEmpty {
                Text("No instructions found. You can add them after importing.")
                    .font(.body)
                    .foregroundColor(.appTextSecondary)
                    .italic()
            } else {
                ForEach(Array(editableInstructions.enumerated()), id: \.offset) { index, instruction in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(index + 1).")
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundColor(.appPrimary)
                            .frame(width: 24, alignment: .leading)

                        Text(instruction)
                            .font(.body)
                            .foregroundColor(.appTextPrimary)
                            .lineLimit(3)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    // MARK: - Archetype Selection Section

    private var archetypeSelectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recipe Type")
                .font(.headline)
                .foregroundColor(.appTextPrimary)

            Text("Select the types that best describe this recipe:")
                .font(.caption)
                .foregroundColor(.appTextSecondary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: 8) {
                ForEach(ArchetypeType.allCases) { archetype in
                    ArchetypeSelectionChip(
                        archetype: archetype,
                        isSelected: selectedArchetypes.contains(archetype),
                        action: {
                            if selectedArchetypes.contains(archetype) {
                                selectedArchetypes.remove(archetype)
                            } else {
                                selectedArchetypes.insert(archetype)
                            }
                        }
                    )
                }
            }
        }
        .padding()
        .cardStyle()
        .padding(.horizontal, -16)
        .padding(.horizontal)
    }

    // MARK: - Import Button

    private var importButton: some View {
        Button {
            importRecipe()
        } label: {
            HStack {
                Image(systemName: "checkmark.circle")
                Text("Import Recipe")
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(PrimaryButtonStyle())
        .padding(.top, 8)
    }

    // MARK: - Actions

    private func parseURL() async {
        guard let url = URL(string: urlString) else {
            errorMessage = "Please enter a valid URL."
            showingError = true
            return
        }

        do {
            let recipe = try await parser.parse(url: url)
            parsedRecipe = recipe
            editableTitle = recipe.title
            editableServings = recipe.servings
            editableIngredients = recipe.ingredients.map {
                EditableIngredient(original: $0, displayText: $0.displayString)
            }
            editableInstructions = recipe.instructions
            selectedArchetypes = Set(recipe.suggestedArchetypes)
        } catch let error as RecipeParserError {
            errorMessage = error.localizedDescription
            showingError = true
        } catch {
            errorMessage = "An unexpected error occurred. Please try again."
            showingError = true
        }
    }

    private func importRecipe() {
        guard let parsed = parsedRecipe else { return }

        // Create the Recipe model
        let recipe = Recipe(
            title: editableTitle,
            summary: parsed.summary,
            sourceURL: parsed.sourceURL,
            servings: editableServings,
            prepTimeMinutes: parsed.prepTimeMinutes,
            cookTimeMinutes: parsed.cookTimeMinutes,
            instructions: editableInstructions,
            suggestedArchetypes: Array(selectedArchetypes)
        )

        // Add ingredients
        let includedIngredients = editableIngredients.filter { $0.isIncluded }
        for (index, editable) in includedIngredients.enumerated() {
            let recipeIngredient = RecipeIngredient(
                quantity: editable.original.quantity,
                unit: editable.original.unit,
                preparationNote: editable.original.preparationNote,
                isOptional: editable.original.isOptional,
                order: index,
                customName: editable.original.name
            )
            recipe.recipeIngredients.append(recipeIngredient)
        }

        // Fetch and store image if available
        if let imageURL = parsed.imageURL {
            Task {
                if let imageData = try? await fetchImageData(from: imageURL) {
                    await MainActor.run {
                        recipe.imageData = imageData
                    }
                }
            }
        }

        // Insert into context
        recipe.household = households.first
        modelContext.insert(recipe)

        dismiss()
    }

    private func fetchImageData(from url: URL) async throws -> Data {
        let (data, _) = try await URLSession.shared.data(from: url)
        return data
    }
}

// MARK: - Archetype Selection Chip

struct ArchetypeSelectionChip: View {
    let archetype: ArchetypeType
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: archetype.icon)
                    .font(.caption)
                Text(archetype.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(isSelected ? Color.archetypeColor(for: archetype) : Color.systemGray6)
            .foregroundColor(isSelected ? .white : .appTextPrimary)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

// MARK: - Preview

#Preview {
    RecipeImportSheet()
        .modelContainer(for: [Recipe.self, RecipeIngredient.self, Ingredient.self], inMemory: true)
}
