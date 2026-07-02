import SwiftUI
import CoreData

/// Sheet for editing meal slot details including recipe, custom meal, notes, archetype, and assigned users
struct MealSlotEditorSheet: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var slot: MealSlot

    @FetchRequest(sortDescriptors: [SortDescriptor(\.title)]) private var recipes: FetchedResults<Recipe>
    @FetchRequest(sortDescriptors: [SortDescriptor(\.displayName)]) private var users: FetchedResults<User>
    @FetchRequest(sortDescriptors: [SortDescriptor(\.name)]) private var archetypes: FetchedResults<MealArchetype>

    @State private var showingRecipePicker = false
    @State private var customMealName: String = ""
    @State private var notes: String = ""
    @State private var servingsPlanned: Int = 2
    @State private var selectedArchetypeId: UUID?
    @State private var selectedUserIds: Set<UUID> = []

    init(slot: MealSlot) {
        self.slot = slot
        _customMealName = State(initialValue: slot.customMealName ?? "")
        _notes = State(initialValue: slot.notes ?? "")
        _servingsPlanned = State(initialValue: Int(slot.servingsPlanned))
        _selectedArchetypeId = State(initialValue: slot.archetype?.id)
        _selectedUserIds = State(initialValue: Set(slot.assignedToArray.map { $0.id }))
    }

    var body: some View {
        NavigationStack {
            Form {
                headerSection
                mealSection
                servingsSection
                Section("Meal Type") {
                    archetypePicker
                }
                assignedUsersSection
                notesSection
                nutritionSection
            }
            .navigationTitle("Edit Meal")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        saveChanges()
                        dismiss()
                    }
                }

                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        // Edits are applied live to the managed object via onChange, so
                        // Cancel must discard them — otherwise they stay dirty in the
                        // context and get persisted by the next save anywhere. The app
                        // saves after each edit elsewhere, so the context is normally
                        // clean apart from this sheet's pending changes.
                        viewContext.rollback()
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingRecipePicker) {
                RecipePickerView(slot: slot)
            }
        }
    }

    // MARK: - Form Sections

    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text(slot.slotDescription)
                    .font(AppTypography.headline)
                if let weekPlan = slot.weekPlan {
                    Text(weekPlan.shortWeekDisplay)
                        .font(AppTypography.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var mealSection: some View {
        Section("Meal") {
            if !slot.recipesArray.isEmpty {
                ForEach(slot.recipesArray) { recipe in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(recipe.title)
                                .font(AppTypography.body)
                            if let time = recipe.formattedTotalTime {
                                Text(time)
                                    .font(AppTypography.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button(role: .destructive) {
                            slot.removeFromRecipes(recipe)
                            slot.modifiedAt = Date()
                        } label: {
                            Image(systemName: "minus.circle")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Button {
                showingRecipePicker = true
            } label: {
                Label("Add Recipe", systemImage: "plus.circle")
            }

            if slot.recipesArray.isEmpty {
                TextField("Or enter custom meal", text: $customMealName)
                    .onChange(of: customMealName) { _, newValue in
                        slot.customMealName = newValue.isEmpty ? nil : newValue
                        slot.modifiedAt = Date()
                    }
            }
        }
    }

    private var servingsSection: some View {
        Section("Servings") {
            HStack {
                Text("Servings")
                Spacer()
                #if os(iOS)
                Stepper(value: $servingsPlanned, in: 1...20) {
                    Text("\(servingsPlanned)")
                        .foregroundStyle(.secondary)
                }
                .onChange(of: servingsPlanned) { _, newValue in
                    slot.servingsPlanned = Int32(newValue)
                    slot.modifiedAt = Date()
                }
                #else
                HStack(spacing: 12) {
                    Button { if servingsPlanned > 1 { servingsPlanned -= 1 } } label: {
                        Image(systemName: "minus.circle.fill")
                    }
                    .buttonStyle(.plain)
                    Text("\(servingsPlanned)")
                    Button { if servingsPlanned < 20 { servingsPlanned += 1 } } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .buttonStyle(.plain)
                }
                .onChange(of: servingsPlanned) { _, newValue in
                    slot.servingsPlanned = Int32(newValue)
                    slot.modifiedAt = Date()
                }
                #endif
            }
        }
    }

    @ViewBuilder
    private var assignedUsersSection: some View {
        if !users.isEmpty {
            Section("Who's Eating") {
                ForEach(users) { user in
                    userToggleRow(user)
                }
            }
        }
    }

    private var notesSection: some View {
        Section("Notes") {
            TextField("Add a note...", text: $notes, axis: .vertical)
                .lineLimit(3...6)
                .onChange(of: notes) { _, newValue in
                    slot.notes = newValue.isEmpty ? nil : newValue
                    slot.modifiedAt = Date()
                }
        }
    }

    /// Personal drill-down view of the meal's planned macros, aggregated across
    /// all components (or legacy recipes) by `MealSlot.plannedMacros`. Per the
    /// CLAUDE.md sharing spec, macro numbers never appear in the shared planning
    /// grid — only here, when a household member opens a slot to inspect or
    /// edit it. The "no data" case shows a neutral caption without nudge or
    /// judgement.
    private var nutritionSection: some View {
        Section {
            MacroSummaryRow(summary: slot.plannedMacros)
                .padding(.vertical, 4)
        } header: {
            Text("Per serving")
        } footer: {
            Text("Visible only to you. Aggregated across the meal's components.")
                .font(AppTypography.caption2)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }

    // MARK: - Archetype Picker

    private var archetypePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // No archetype option
                archetypeChip(nil, name: "None", icon: "circle.dashed", color: .gray)

                // System archetypes
                ForEach(ArchetypeType.allCases) { archetypeType in
                    archetypeChip(
                        archetypes.first { $0.systemType == archetypeType },
                        name: archetypeType.displayName,
                        icon: archetypeType.icon,
                        color: archetypeType.color
                    )
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private func archetypeChip(_ archetype: MealArchetype?, name: String, icon: String, color: Color) -> some View {
        let isSelected = (archetype == nil && selectedArchetypeId == nil) ||
                         (archetype?.id == selectedArchetypeId)

        return Button {
            selectedArchetypeId = archetype?.id
            slot.archetype = archetype
            slot.modifiedAt = Date()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(AppTypography.caption)
                Text(name)
                    .font(AppTypography.caption)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? color.opacity(0.2) : Color.secondary.opacity(0.1))
            .foregroundStyle(isSelected ? color : .secondary)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(isSelected ? color : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - User Toggle Row

    private func userToggleRow(_ user: User) -> some View {
        let isSelected = selectedUserIds.contains(user.id)

        return Button {
            if isSelected {
                selectedUserIds.remove(user.id)
            } else {
                selectedUserIds.insert(user.id)
            }
            slot.assignedTo = NSSet(array: users.filter { selectedUserIds.contains($0.id) })
            slot.modifiedAt = Date()
        } label: {
            HStack {
                UserAvatar(user: user, size: 32)
                Text(user.displayName)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .green : .secondary)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func saveChanges() {
        viewContext.saveWithLogging(context: "meal slot changes")
    }
}

// MARK: - Recipe Picker View

struct RecipePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var slot: MealSlot

    @FetchRequest(sortDescriptors: [SortDescriptor(\.title)]) private var recipes: FetchedResults<Recipe>
    @State private var searchText = ""

    private var filteredRecipes: [Recipe] {
        if searchText.isEmpty {
            return Array(recipes)
        }
        return recipes.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            List {
                // Not everything is a recipe — "a bag of chips" should be one tap,
                // not a dead end when no recipe matches.
                if !trimmedSearchText.isEmpty {
                    Section {
                        customMealRow(trimmedSearchText)
                    }
                }
                ForEach(filteredRecipes) { recipe in
                    recipeRow(recipe)
                }
            }
            .searchable(text: $searchText, prompt: "Search recipes or type a meal")
            .navigationTitle("Select Recipe")
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
    }

    private func recipeRow(_ recipe: Recipe) -> some View {
        Button {
            slot.addToRecipes(recipe)
            slot.customMealName = nil
            slot.modifiedAt = Date()
            dismiss()
        } label: {
            recipeRowLabel(recipe)
        }
    }

    private func customMealRow(_ name: String) -> some View {
        Button {
            slot.customMealName = name
            slot.recipes = NSSet()
            slot.isSkipped = false
            slot.modifiedAt = Date()
            dismiss()
        } label: {
            Label("Add \u{201C}\(name)\u{201D} as a meal", systemImage: "plus.circle")
                .font(AppTypography.body)
                .foregroundStyle(Theme.Colors.primary)
        }
    }

    private func recipeRowLabel(_ recipe: Recipe) -> some View {
        HStack(spacing: 12) {
            RecipeImageView(imageData: recipe.imageData, imageURL: recipe.imageURL)
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(recipe.title)
                    .font(AppTypography.body)
                    .foregroundStyle(.primary)

                HStack(spacing: 8) {
                    if let time = recipe.formattedTotalTime {
                        Label(time, systemImage: "clock")
                            .font(AppTypography.caption)
                            .foregroundStyle(.secondary)
                    }

                    if recipe.isFavorite {
                        Image(systemName: "heart.fill")
                            .font(AppTypography.caption)
                            .foregroundStyle(.red)
                    }
                }
            }

            Spacer()

            if slot.recipesArray.contains(where: { $0.id == recipe.id }) {
                Image(systemName: "checkmark")
                    .foregroundStyle(.green)
            }
        }
    }
}

// MARK: - Preview

private struct MealSlotEditorPreview: View {
    @State private var slot: MealSlot?

    var body: some View {
        Group {
            if let slot = slot {
                MealSlotEditorSheet(slot: slot)
            } else {
                ProgressView("Loading...")
            }
        }
        .task {
            let context = PersistenceController.preview.viewContext
            slot = MealSlot(context: context, dayOfWeek: .monday, mealType: .dinner)
        }
    }
}

#Preview {
    MealSlotEditorPreview()
        .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
}
