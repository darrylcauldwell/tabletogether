import SwiftUI
import SwiftData
#if os(iOS)
import PhotosUI
#endif

/// A view for creating or editing recipes with title, summary, ingredients, instructions,
/// archetype selection, and photo picker.
struct RecipeEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query private var households: [Household]

    // The recipe being edited, or nil for creating a new recipe
    let recipe: Recipe?

    // Editable state
    @State private var title: String
    @State private var summary: String
    @State private var servings: Int
    @State private var prepTimeMinutes: String
    @State private var cookTimeMinutes: String
    @State private var editableIngredients: [EditableIngredientItem]
    @State private var instructions: [String]
    @State private var selectedArchetypes: Set<ArchetypeType>
    @State private var tags: [String]
    #if os(iOS)
    @State private var selectedPhotoItem: PhotosPickerItem?
    #endif
    @State private var imageData: Data?

    // UI State
    @State private var showingDeleteConfirmation = false
    @State private var newIngredientText = ""
    @State private var newInstructionText = ""
    @State private var newTagText = ""

    // Editable ingredient representation
    struct EditableIngredientItem: Identifiable, Equatable {
        let id: UUID
        var name: String
        var quantity: Double
        var unit: MeasurementUnit
        var preparationNote: String
        var isOptional: Bool

        init(
            id: UUID = UUID(),
            name: String = "",
            quantity: Double = 1,
            unit: MeasurementUnit = .piece,
            preparationNote: String = "",
            isOptional: Bool = false
        ) {
            self.id = id
            self.name = name
            self.quantity = quantity
            self.unit = unit
            self.preparationNote = preparationNote
            self.isOptional = isOptional
        }

        init(from recipeIngredient: RecipeIngredient) {
            self.id = recipeIngredient.id
            self.name = recipeIngredient.displayName
            self.quantity = recipeIngredient.quantity
            self.unit = recipeIngredient.unit
            self.preparationNote = recipeIngredient.preparationNote ?? ""
            self.isOptional = recipeIngredient.isOptional
        }
    }

    var isEditing: Bool { recipe != nil }

    init(recipe: Recipe?) {
        self.recipe = recipe

        // Initialize state from recipe or defaults
        _title = State(initialValue: recipe?.title ?? "")
        _summary = State(initialValue: recipe?.summary ?? "")
        _servings = State(initialValue: recipe?.servings ?? 4)
        _prepTimeMinutes = State(initialValue: recipe?.prepTimeMinutes.map { String($0) } ?? "")
        _cookTimeMinutes = State(initialValue: recipe?.cookTimeMinutes.map { String($0) } ?? "")
        _editableIngredients = State(initialValue: recipe?.sortedIngredients.map { EditableIngredientItem(from: $0) } ?? [])
        _instructions = State(initialValue: recipe?.instructions ?? [])
        _selectedArchetypes = State(initialValue: Set(recipe?.suggestedArchetypes ?? []))
        _tags = State(initialValue: recipe?.tags ?? [])
        _imageData = State(initialValue: recipe?.imageData)
    }

    var body: some View {
        Form {
            // Basic Info Section
            basicInfoSection

            // Photo Section
            photoSection

            // Time Section
            timeSection

            // Archetype Section
            archetypeSection

            // Tags Section
            tagsSection

            // Ingredients Section
            ingredientsSection

            // Instructions Section
            instructionsSection

            // Delete Section (only for existing recipes)
            if isEditing {
                deleteSection
            }
        }
        .navigationTitle(isEditing ? "Edit Recipe" : "New Recipe")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    saveRecipe()
                }
                .fontWeight(.semibold)
                .disabled(title.isEmpty)
            }
        }
        #if os(iOS)
        .onChange(of: selectedPhotoItem) { _, newValue in
            Task {
                if let data = try? await newValue?.loadTransferable(type: Data.self) {
                    imageData = data
                }
            }
        }
        #endif
        .confirmationDialog(
            "Delete Recipe",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                deleteRecipe()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete this recipe? This action cannot be undone.")
        }
    }

    // MARK: - Basic Info Section

    private var basicInfoSection: some View {
        Section {
            TextField("Recipe Title", text: $title)

            TextField("Summary (optional)", text: $summary, axis: .vertical)
                .lineLimit(2...4)

            HStack {
                Text("Servings")
                Spacer()
                #if os(iOS)
                Stepper(value: $servings, in: 1...50) {
                    Text("\(servings)")
                        .foregroundColor(.appTextSecondary)
                }
                #else
                // tvOS-compatible stepper alternative
                HStack(spacing: 12) {
                    Button { if servings > 1 { servings -= 1 } } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                    Text("\(servings)")
                        .foregroundColor(.appTextSecondary)
                        .frame(minWidth: 30)
                    Button { if servings < 50 { servings += 1 } } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                }
                #endif
            }
        } header: {
            Text("Basic Info")
        }
    }

    // MARK: - Photo Section

    #if os(iOS)
    private var photoSection: some View {
        Section {
            VStack(spacing: 12) {
                if let imageData = imageData,
                   let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 180)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    Button(role: .destructive) {
                        self.imageData = nil
                        self.selectedPhotoItem = nil
                    } label: {
                        Label("Remove Photo", systemImage: "trash")
                    }
                } else {
                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        VStack(spacing: 8) {
                            Image(systemName: "photo.badge.plus")
                                .font(.largeTitle)
                                .foregroundColor(.appPrimary)
                            Text("Add Photo")
                                .font(.subheadline)
                                .foregroundColor(.appPrimary)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 120)
                        .background(Color.gray.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }

                if imageData != nil {
                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        Label("Change Photo", systemImage: "photo")
                    }
                }
            }
        } header: {
            Text("Photo")
        }
    }
    #else
    private var photoSection: some View {
        Section {
            if let imageData = imageData,
               let nsImage = NSImage(data: imageData) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 180)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Text("Photo upload not available on this platform")
                    .foregroundColor(.secondary)
            }
        } header: {
            Text("Photo")
        }
    }
    #endif

    // MARK: - Time Section

    private var timeSection: some View {
        Section {
            HStack {
                Text("Prep Time")
                Spacer()
                TextField("min", text: $prepTimeMinutes)
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
                    .multilineTextAlignment(.trailing)
                    .frame(width: 60)
                Text("min")
                    .foregroundColor(.appTextSecondary)
            }

            HStack {
                Text("Cook Time")
                Spacer()
                TextField("min", text: $cookTimeMinutes)
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
                    .multilineTextAlignment(.trailing)
                    .frame(width: 60)
                Text("min")
                    .foregroundColor(.appTextSecondary)
            }
        } header: {
            Text("Time")
        }
    }

    // MARK: - Archetype Section

    private var archetypeSection: some View {
        Section {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130))], spacing: 8) {
                ForEach(ArchetypeType.allCases) { archetype in
                    ArchetypeToggleChip(
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
            .padding(.vertical, 4)
        } header: {
            Text("Recipe Type")
        } footer: {
            Text("Select the types that best describe this recipe for better suggestions.")
        }
    }

    // MARK: - Tags Section

    private var tagsSection: some View {
        Section {
            // Existing tags as chips
            if !tags.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(tags, id: \.self) { tag in
                        TagChip(tag: tag) {
                            tags.removeAll { $0 == tag }
                        }
                    }
                }
            }

            // Add new tag field
            HStack {
                TextField("Add tag...", text: $newTagText)
                    .onSubmit {
                        addTag()
                    }

                Button {
                    addTag()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.appPrimary)
                }
                .disabled(newTagText.isEmpty)
            }
        } header: {
            Text("Tags")
        } footer: {
            Text("Add custom tags like \"vegetarian\", \"kid-friendly\", or \"date night\" for easier searching.")
        }
    }

    private func addTag() {
        let trimmed = newTagText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty, !tags.contains(trimmed) else {
            newTagText = ""
            return
        }
        tags.append(trimmed)
        newTagText = ""
    }

    // MARK: - Ingredients Section

    private var ingredientsSection: some View {
        Section {
            ForEach($editableIngredients) { $ingredient in
                IngredientEditorRow(ingredient: $ingredient)
            }
            .onDelete(perform: deleteIngredients)
            .onMove(perform: moveIngredients)

            // Add new ingredient
            HStack {
                TextField("Add ingredient...", text: $newIngredientText)
                    .onSubmit {
                        addIngredient()
                    }

                Button {
                    addIngredient()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.appPrimary)
                }
                .disabled(newIngredientText.isEmpty)
            }
        } header: {
            HStack {
                Text("Ingredients")
                Spacer()
                #if os(iOS)
                EditButton()
                    .font(.caption)
                #endif
            }
        }
    }

    // MARK: - Instructions Section

    private var instructionsSection: some View {
        Section {
            ForEach(Array(instructions.enumerated()), id: \.offset) { index, instruction in
                HStack(alignment: .top, spacing: 12) {
                    Text("\(index + 1).")
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(.appPrimary)
                        .frame(width: 24, alignment: .leading)

                    TextField("Step \(index + 1)", text: Binding(
                        get: { instructions[index] },
                        set: { instructions[index] = $0 }
                    ), axis: .vertical)
                    .lineLimit(1...5)
                }
            }
            .onDelete(perform: deleteInstructions)
            .onMove(perform: moveInstructions)

            // Add new instruction
            HStack {
                TextField("Add step...", text: $newInstructionText, axis: .vertical)
                    .lineLimit(1...3)
                    .onSubmit {
                        addInstruction()
                    }

                Button {
                    addInstruction()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.appPrimary)
                }
                .disabled(newInstructionText.isEmpty)
            }
        } header: {
            HStack {
                Text("Instructions")
                Spacer()
                #if os(iOS)
                EditButton()
                    .font(.caption)
                #endif
            }
        }
    }

    // MARK: - Delete Section

    private var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                showingDeleteConfirmation = true
            } label: {
                HStack {
                    Spacer()
                    Label("Delete Recipe", systemImage: "trash")
                    Spacer()
                }
            }
        }
    }

    // MARK: - Actions

    private func addIngredient() {
        guard !newIngredientText.isEmpty else { return }

        let parsed = parseIngredientText(newIngredientText)
        editableIngredients.append(parsed)
        newIngredientText = ""
    }

    private func deleteIngredients(at offsets: IndexSet) {
        editableIngredients.remove(atOffsets: offsets)
    }

    private func moveIngredients(from source: IndexSet, to destination: Int) {
        editableIngredients.move(fromOffsets: source, toOffset: destination)
    }

    private func addInstruction() {
        guard !newInstructionText.isEmpty else { return }
        instructions.append(newInstructionText)
        newInstructionText = ""
    }

    private func deleteInstructions(at offsets: IndexSet) {
        instructions.remove(atOffsets: offsets)
    }

    private func moveInstructions(from source: IndexSet, to destination: Int) {
        instructions.move(fromOffsets: source, toOffset: destination)
    }

    private func saveRecipe() {
        if let existingRecipe = recipe {
            // Update existing recipe
            existingRecipe.title = title
            existingRecipe.summary = summary.isEmpty ? nil : summary
            existingRecipe.servings = servings
            existingRecipe.prepTimeMinutes = Int(prepTimeMinutes)
            existingRecipe.cookTimeMinutes = Int(cookTimeMinutes)
            existingRecipe.instructions = instructions
            existingRecipe.suggestedArchetypes = Array(selectedArchetypes)
            existingRecipe.tags = tags
            existingRecipe.imageData = imageData
            existingRecipe.modifiedAt = Date()

            // Update ingredients
            // Remove old ingredients
            for ingredient in existingRecipe.recipeIngredients {
                modelContext.delete(ingredient)
            }
            existingRecipe.recipeIngredients.removeAll()

            // Add updated ingredients
            for (index, editable) in editableIngredients.enumerated() {
                let recipeIngredient = RecipeIngredient(
                    quantity: editable.quantity,
                    unit: editable.unit,
                    preparationNote: editable.preparationNote.isEmpty ? nil : editable.preparationNote,
                    isOptional: editable.isOptional,
                    order: index,
                    customName: editable.name
                )
                existingRecipe.recipeIngredients.append(recipeIngredient)
            }
        } else {
            // Create new recipe
            let newRecipe = Recipe(
                title: title,
                summary: summary.isEmpty ? nil : summary,
                servings: servings,
                prepTimeMinutes: Int(prepTimeMinutes),
                cookTimeMinutes: Int(cookTimeMinutes),
                instructions: instructions,
                tags: tags,
                suggestedArchetypes: Array(selectedArchetypes),
                imageData: imageData
            )

            // Add ingredients
            for (index, editable) in editableIngredients.enumerated() {
                let recipeIngredient = RecipeIngredient(
                    quantity: editable.quantity,
                    unit: editable.unit,
                    preparationNote: editable.preparationNote.isEmpty ? nil : editable.preparationNote,
                    isOptional: editable.isOptional,
                    order: index,
                    customName: editable.name
                )
                newRecipe.recipeIngredients.append(recipeIngredient)
            }

            newRecipe.household = households.first
            modelContext.insert(newRecipe)
        }

        dismiss()
    }

    private func deleteRecipe() {
        if let recipe = recipe {
            modelContext.delete(recipe)
        }
        dismiss()
    }

    // MARK: - Parsing Helpers

    private func parseIngredientText(_ text: String) -> EditableIngredientItem {
        // Simple parsing - tries to extract quantity and unit from text
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Pattern: "2 cups flour" or "1/2 tsp salt" or just "butter"
        let patterns: [(String, MeasurementUnit)] = [
            (#"^([\d./]+)\s*(?:cups?|c\.?)\s+"#, .cup),
            (#"^([\d./]+)\s*(?:tablespoons?|tbsp?\.?|T\.?)\s+"#, .tablespoon),
            (#"^([\d./]+)\s*(?:teaspoons?|tsp?\.?|t\.?)\s+"#, .teaspoon),
            (#"^([\d./]+)\s*(?:grams?|g\.?)\s+"#, .gram),
            (#"^([\d./]+)\s*(?:kg|kilograms?)\s+"#, .kilogram),
            (#"^([\d./]+)\s*(?:ml|milliliters?)\s+"#, .milliliter),
            (#"^([\d./]+)\s*(?:l|liters?)\s+"#, .liter),
            (#"^([\d./]+)\s+"#, .piece) // Fallback for just a number
        ]

        var quantity: Double = 1
        var unit: MeasurementUnit = .piece
        var name = trimmed

        for (pattern, matchedUnit) in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: trimmed, options: [], range: NSRange(trimmed.startIndex..., in: trimmed)) {

                if let quantityRange = Range(match.range(at: 1), in: trimmed) {
                    let quantityStr = String(trimmed[quantityRange])
                    quantity = parseFraction(quantityStr)
                }

                unit = matchedUnit
                name = String(trimmed[trimmed.index(trimmed.startIndex, offsetBy: match.range.length)...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }

        // Check for preparation note (after comma)
        var preparationNote = ""
        if let commaIndex = name.firstIndex(of: ",") {
            preparationNote = String(name[name.index(after: commaIndex)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            name = String(name[..<commaIndex])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return EditableIngredientItem(
            name: name,
            quantity: quantity,
            unit: unit,
            preparationNote: preparationNote
        )
    }

    private func parseFraction(_ string: String) -> Double {
        let components = string.components(separatedBy: " ")
        var total: Double = 0

        for component in components {
            if component.contains("/") {
                let fractionParts = component.components(separatedBy: "/")
                if fractionParts.count == 2,
                   let numerator = Double(fractionParts[0]),
                   let denominator = Double(fractionParts[1]),
                   denominator != 0 {
                    total += numerator / denominator
                }
            } else if let num = Double(component) {
                total += num
            }
        }

        return total > 0 ? total : 1
    }
}

// MARK: - Ingredient Editor Row

struct IngredientEditorRow: View {
    @Binding var ingredient: RecipeEditorView.EditableIngredientItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                // Quantity
                TextField("Qty", value: $ingredient.quantity, format: .number)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                    #endif
                    .frame(width: 50)

                // Unit picker
                Picker("Unit", selection: $ingredient.unit) {
                    ForEach(MeasurementUnit.allCases) { unit in
                        Text(unit.displayName).tag(unit)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 80)

                // Name
                TextField("Ingredient name", text: $ingredient.name)
            }

            HStack {
                TextField("Preparation note (e.g., diced)", text: $ingredient.preparationNote)
                    .font(.caption)
                    .foregroundColor(.appTextSecondary)

                Toggle("Optional", isOn: $ingredient.isOptional)
                    #if os(iOS)
                    .toggleStyle(.switch)
                    .scaleEffect(0.8)
                    #endif
                    .labelsHidden()

                if ingredient.isOptional {
                    Text("Optional")
                        .font(.caption)
                        .foregroundColor(.appTextSecondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Tag Chip

struct TagChip: View {
    let tag: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(tag)
                .font(.caption)
                .foregroundColor(.appTextPrimary)

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.appTextSecondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.systemGray5)
        .clipShape(Capsule())
    }
}

// MARK: - Archetype Toggle Chip

struct ArchetypeToggleChip: View {
    let archetype: ArchetypeType
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: archetype.icon)
                    .font(.caption2)
                Text(archetype.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(isSelected ? Color.archetypeColor(for: archetype).opacity(0.2) : Color.systemGray6)
            .foregroundColor(isSelected ? Color.archetypeColor(for: archetype) : .appTextSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.archetypeColor(for: archetype) : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview("New Recipe") {
    NavigationStack {
        RecipeEditorView(recipe: nil)
    }
    .modelContainer(for: [Recipe.self, RecipeIngredient.self, Ingredient.self], inMemory: true)
}

private struct RecipeEditorEditPreview: View {
    @State private var recipe: Recipe?

    var body: some View {
        Group {
            if let recipe = recipe {
                NavigationStack {
                    RecipeEditorView(recipe: recipe)
                }
            } else {
                ProgressView("Loading...")
            }
        }
        .task {
            let newRecipe = Recipe(
                title: "Test Recipe",
                summary: "A test recipe for preview",
                servings: 4,
                prepTimeMinutes: 15,
                cookTimeMinutes: 30,
                instructions: ["Step 1", "Step 2", "Step 3"],
                suggestedArchetypes: [.quickWeeknight, .familyFavorite]
            )

            let ingredients = [
                RecipeIngredient(quantity: 2, unit: .cup, order: 0, customName: "Flour"),
                RecipeIngredient(quantity: 1, unit: .cup, order: 1, customName: "Sugar"),
                RecipeIngredient(quantity: 2, unit: .piece, order: 2, customName: "Eggs")
            ]

            ingredients.forEach { newRecipe.recipeIngredients.append($0) }
            recipe = newRecipe
        }
    }
}

#Preview("Edit Mode") {
    RecipeEditorEditPreview()
        .modelContainer(for: [Recipe.self, RecipeIngredient.self, Ingredient.self], inMemory: true)
}
