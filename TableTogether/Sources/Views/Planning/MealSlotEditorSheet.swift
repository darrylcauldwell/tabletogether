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
    @State private var showingSidePicker = false
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

    private var currentUser: User? { User.current(in: users) }

    /// Discrete portion steps for a recipe on the plate (½/1/1½/2 servings).
    private static let portionSteps: [Double] = [0.5, 1.0, 1.5, 2.0]
    private func portionLabel(_ scale: Double) -> String {
        switch scale {
        case 0.5: return "½"
        case 1.0: return "1"
        case 1.5: return "1½"
        case 2.0: return "2"
        default: return String(format: "%.1f", scale)
        }
    }

    /// A sensible starting amount for a side, per its unit: one of a countable
    /// thing (naan, egg), else a modest mass/volume.
    static func defaultSideQuantity(for unit: MeasurementUnit) -> Double {
        switch unit {
        case .piece, .slice, .clove, .bunch, .pinch, .toTaste: return 1
        default: return 100
        }
    }

    /// Compact "200g" / "1 naan" style quantity label for a side row.
    private func sideQuantityLabel(_ item: PlateItem) -> String? {
        guard item.kind != .recipe, let qty = item.quantity, let unit = item.unit else { return nil }
        let amount = qty == qty.rounded() ? "\(Int(qty))" : String(format: "%.1f", qty)
        return "\(amount)\(unit == .gram || unit == .milliliter ? unit.abbreviation : " " + unit.abbreviation)"
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
                // Shared picker (also used by the week list's Add meal). Apply
                // the choice to this slot; the editor saves on Done.
                RecipePickerSheet { choice in
                    guard let user = currentUser else { return }
                    switch choice {
                    case .recipe(let recipe):
                        slot.addRecipe(recipe, by: user)
                    case .custom(let name):
                        slot.setCustomMeal(name, by: user)
                    }
                }
            }
            .sheet(isPresented: $showingSidePicker) {
                SidePickerSheet { choice in
                    guard let user = currentUser else { return }
                    switch choice {
                    case .ingredient(let ingredient):
                        let unit = ingredient.defaultUnit
                        slot.addIngredientSide(ingredient, quantity: Self.defaultSideQuantity(for: unit), unit: unit, by: user)
                    case .foodItem(let foodItem):
                        slot.addFoodItemSide(foodItem, quantity: 100, unit: .gram, by: user)
                    }
                }
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
        Section("Plate") {
            ForEach(slot.plateItems) { item in
                plateItemRow(item)
            }

            Button {
                showingRecipePicker = true
            } label: {
                Label("Add dish", systemImage: "plus.circle")
            }

            Button {
                showingSidePicker = true
            } label: {
                Label("Add side", systemImage: "leaf")
            }

            // Custom-meal escape hatch only when the plate is empty ("Friday: pub").
            if slot.plateItems.isEmpty {
                TextField("Or enter custom meal", text: $customMealName)
                    .onChange(of: customMealName) { _, newValue in
                        slot.customMealName = newValue.isEmpty ? nil : newValue
                        slot.modifiedAt = Date()
                    }
            }

            // A single quiet per-serving total — informational, no judgement.
            if let macros = slot.plannedMacros, let cal = macros.calories {
                let perServing = Int((cal / Double(max(slot.servingsPlanned, 1))).rounded())
                HStack {
                    Text("Per serving")
                        .font(AppTypography.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("≈\(perServing) cal")
                        .font(AppTypography.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func plateItemRow(_ item: PlateItem) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName)
                    .font(AppTypography.body)
                HStack(spacing: 6) {
                    if let qty = sideQuantityLabel(item) {
                        Text(qty)
                            .font(AppTypography.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let cal = item.macrosForOneSlotServing?.calories {
                        Text("≈\(Int(cal.rounded())) cal")
                            .font(AppTypography.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            // Recipe rows get a discrete portion menu (½/1/1½/2).
            if item.kind == .recipe, let recipe = item.recipe {
                Menu {
                    ForEach(Self.portionSteps, id: \.self) { scale in
                        Button(portionLabel(scale)) {
                            guard let user = currentUser else { return }
                            slot.setPortionScale(scale, forRecipe: recipe, by: user)
                        }
                    }
                } label: {
                    Text(portionLabel(item.portionScale))
                        .font(AppTypography.caption)
                        .foregroundStyle(Theme.Colors.primary)
                        .frame(minWidth: 28)
                }
            }

            Button(role: .destructive) {
                guard let user = currentUser else { return }
                slot.removePlateItem(id: item.id, by: user)
            } label: {
                Image(systemName: "minus.circle")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
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
