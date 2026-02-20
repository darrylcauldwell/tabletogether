import SwiftUI
import SwiftData

/// Sheet for editing meal slot details including recipe, custom meal, notes, archetype, and assigned users
struct MealSlotEditorSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Bindable var slot: MealSlot

    @Query private var recipes: [Recipe]
    @Query private var users: [User]
    @Query private var archetypes: [MealArchetype]

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
        _servingsPlanned = State(initialValue: slot.servingsPlanned)
        _selectedArchetypeId = State(initialValue: slot.archetype?.id)
        _selectedUserIds = State(initialValue: Set(slot.assignedTo.map { $0.id }))
    }

    var body: some View {
        NavigationStack {
            Form {
                // Header with slot info
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(slot.slotDescription)
                            .font(.headline)
                        if let weekPlan = slot.weekPlan {
                            Text(weekPlan.shortWeekDisplay)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // Recipe Section
                Section("Meal") {
                    if !slot.recipes.isEmpty {
                        ForEach(slot.recipes) { recipe in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(recipe.title)
                                        .font(.body)
                                    if let time = recipe.formattedTotalTime {
                                        Text(time)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Button(role: .destructive) {
                                    slot.recipes.removeAll { $0.id == recipe.id }
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

                    if slot.recipes.isEmpty {
                        TextField("Or enter custom meal", text: $customMealName)
                            .onChange(of: customMealName) { _, newValue in
                                slot.customMealName = newValue.isEmpty ? nil : newValue
                                slot.modifiedAt = Date()
                            }
                    }
                }

                // Servings Section
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
                            slot.servingsPlanned = newValue
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
                            slot.servingsPlanned = newValue
                            slot.modifiedAt = Date()
                        }
                        #endif
                    }
                }

                // Archetype Section
                Section("Meal Type") {
                    archetypePicker
                }

                // Assigned Users Section
                if !users.isEmpty {
                    Section("Who's Eating") {
                        ForEach(users) { user in
                            userToggleRow(user)
                        }
                    }
                }

                // Notes Section
                Section("Notes") {
                    TextField("Add a note...", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                        .onChange(of: notes) { _, newValue in
                            slot.notes = newValue.isEmpty ? nil : newValue
                            slot.modifiedAt = Date()
                        }
                }
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
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingRecipePicker) {
                RecipePickerView(slot: slot)
            }
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
                    .font(.caption)
                Text(name)
                    .font(.caption)
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
            slot.assignedTo = users.filter { selectedUserIds.contains($0.id) }
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
        modelContext.saveWithLogging(context: "meal slot changes")
    }
}

// MARK: - Recipe Picker View

struct RecipePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var slot: MealSlot

    @Query(sort: \Recipe.title) private var recipes: [Recipe]
    @State private var searchText = ""

    private var filteredRecipes: [Recipe] {
        if searchText.isEmpty {
            return recipes
        }
        return recipes.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filteredRecipes) { recipe in
                    Button {
                        slot.recipes.append(recipe)
                        slot.customMealName = nil
                        slot.modifiedAt = Date()
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            RecipeThumbnailSmall(imageData: recipe.imageData)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(recipe.title)
                                    .font(.body)
                                    .foregroundStyle(.primary)

                                HStack(spacing: 8) {
                                    if let time = recipe.formattedTotalTime {
                                        Label(time, systemImage: "clock")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    if recipe.isFavorite {
                                        Image(systemName: "heart.fill")
                                            .font(.caption)
                                            .foregroundStyle(.red)
                                    }
                                }
                            }

                            Spacer()

                            if slot.recipes.contains(where: { $0.id == recipe.id }) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search recipes")
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
}

// MARK: - Recipe Thumbnail Small

struct RecipeThumbnailSmall: View {
    let imageData: Data?

    var body: some View {
        Group {
            #if canImport(UIKit) && !os(watchOS)
            if let imageData = imageData, let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                placeholderImage
            }
            #else
            placeholderImage
            #endif
        }
        .frame(width: 50, height: 50)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var placeholderImage: some View {
        ZStack {
            Color.gray.opacity(0.2)
            Image(systemName: "fork.knife")
                .foregroundStyle(.secondary)
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
            slot = MealSlot(dayOfWeek: .monday, mealType: .dinner)
        }
    }
}

#Preview {
    MealSlotEditorPreview()
        .modelContainer(for: [MealSlot.self, WeekPlan.self, Recipe.self, User.self, MealArchetype.self], inMemory: true)
}
