import SwiftUI
import CoreData
#if os(iOS)
import PhotosUI
#endif

/// A view for creating or editing recipes with title, summary, ingredients, instructions,
/// archetype selection, and photo picker.
struct RecipeEditorView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @FetchRequest(sortDescriptors: [SortDescriptor(\.name)]) private var households: FetchedResults<Household>

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

    var isEditing: Bool { recipe != nil }

    init(recipe: Recipe?) {
        self.recipe = recipe

        // Initialize state from recipe or defaults
        _title = State(initialValue: recipe?.title ?? "")
        _summary = State(initialValue: recipe?.summary ?? "")
        _servings = State(initialValue: recipe.map { Int($0.servings) } ?? 4)
        _prepTimeMinutes = State(initialValue: recipe.flatMap { $0.prepTimeMinutes > 0 ? String($0.prepTimeMinutes) : nil } ?? "")
        _cookTimeMinutes = State(initialValue: recipe.flatMap { $0.cookTimeMinutes > 0 ? String($0.cookTimeMinutes) : nil } ?? "")
        _editableIngredients = State(initialValue: recipe?.sortedIngredients.map { EditableIngredientItem(from: $0) } ?? [])
        _instructions = State(initialValue: recipe?.instructionsList ?? [])
        _selectedArchetypes = State(initialValue: Set(recipe?.suggestedArchetypes ?? []))
        _tags = State(initialValue: recipe?.tagsList ?? [])
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
        editableIngredients.append(IngredientParser.parse(newIngredientText))
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
            existingRecipe.servings = Int32(servings)
            existingRecipe.prepTimeMinutes = Int32(Int(prepTimeMinutes) ?? 0)
            existingRecipe.cookTimeMinutes = Int32(Int(cookTimeMinutes) ?? 0)
            existingRecipe.instructions = instructions
            existingRecipe.suggestedArchetypes = Array(selectedArchetypes)
            existingRecipe.tags = tags
            existingRecipe.imageData = imageData
            existingRecipe.modifiedAt = Date()

            // Update ingredients
            // Remove old ingredients
            for ingredient in existingRecipe.recipeIngredientsArray {
                viewContext.delete(ingredient)
            }
            existingRecipe.recipeIngredients = NSSet()

            // Add updated ingredients
            for (index, editable) in editableIngredients.enumerated() {
                let recipeIngredient = RecipeIngredient(
                    context: viewContext,
                    quantity: editable.quantity,
                    unit: editable.unit,
                    preparationNote: editable.preparationNote.isEmpty ? nil : editable.preparationNote,
                    isOptional: editable.isOptional,
                    order: index,
                    customName: editable.name
                )
                existingRecipe.addToRecipeIngredients(recipeIngredient)
            }
        } else {
            // Create new recipe
            let newRecipe = Recipe(
                context: viewContext,
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
                    context: viewContext,
                    quantity: editable.quantity,
                    unit: editable.unit,
                    preparationNote: editable.preparationNote.isEmpty ? nil : editable.preparationNote,
                    isOptional: editable.isOptional,
                    order: index,
                    customName: editable.name
                )
                newRecipe.addToRecipeIngredients(recipeIngredient)
            }

            newRecipe.household = households.first
        }

        do {
            try viewContext.save()
        } catch {
            AppLogger.swiftData.error("Failed to save recipe: \(error.localizedDescription)")
        }
        dismiss()
    }

    private func deleteRecipe() {
        if let recipe = recipe {
            viewContext.delete(recipe)
        }
        dismiss()
    }

}

// MARK: - Preview

#Preview("New Recipe") {
    NavigationStack {
        RecipeEditorView(recipe: nil)
    }
    .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
}
