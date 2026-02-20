import SwiftUI

/// Mode for grocery item row display and interaction
enum GroceryRowMode {
    case pantryCheck
    case shopping
}

/// A single grocery item row with checkbox, details, and swipe actions
struct GroceryItemRow: View {
    @Bindable var item: GroceryItem

    var displayQuantity: Double? = nil
    var mode: GroceryRowMode = .shopping
    let onToggle: () -> Void
    let onDelete: () -> Void

    @State private var showingEditSheet = false
    @State private var showingMealsPopover = false

    /// The display name for the item (customName overrides ingredient name when set)
    private var itemName: String {
        if let customName = item.customName, !customName.isEmpty {
            return customName
        }
        return item.ingredient?.name ?? "Unknown Item"
    }

    /// Formatted quantity string (uses displayQuantity override when provided)
    private var quantityText: String {
        let qty = displayQuantity ?? item.quantity
        let quantityStr = qty.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", qty)
            : String(format: "%.1f", qty)
        return "\(quantityStr) \(item.unit.abbreviation)"
    }

    /// Source meals for this item
    private var sourceMeals: [MealSlot] {
        item.sourceSlots
    }

    /// Whether this item comes from planned meals
    private var hasSourceMeals: Bool {
        !sourceMeals.isEmpty
    }

    /// Whether the row's toggle state is active (checked or in-pantry depending on mode)
    private var isToggled: Bool {
        switch mode {
        case .pantryCheck: return item.isInPantry
        case .shopping: return item.isChecked
        }
    }

    /// Accessibility label for VoiceOver
    private var accessibilityLabelText: String {
        var parts: [String] = []

        // Item name and quantity
        parts.append("\(itemName), \(quantityText)")

        // Check status
        switch mode {
        case .pantryCheck:
            if item.isInPantry {
                parts.append("Already have")
            }
        case .shopping:
            if item.isChecked {
                parts.append("Checked")
            }
        }

        // Source meals
        if hasSourceMeals {
            let mealCount = sourceMeals.count
            if mealCount == 1 {
                parts.append("Needed for 1 meal")
            } else {
                parts.append("Needed for \(mealCount) meals")
            }
        }

        // Manual indicator
        if item.isManuallyAdded {
            parts.append("Manually added")
        }

        return parts.joined(separator: ". ")
    }

    var body: some View {
        HStack(spacing: 12) {
            // Pantry mode: explicit Have/Need buttons. Shopping mode: checkbox.
            switch mode {
            case .pantryCheck:
                pantryActionButton
            case .shopping:
                checkboxButton
            }

            // Item details
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    // Item name
                    Text(itemName)
                        .font(.body)
                        .foregroundStyle(isToggled ? .secondary : .primary)
                        .strikethrough(mode == .shopping && item.isChecked)

                    // Quantity badge
                    Text(quantityText)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(Capsule())
                }

                // Source meals indicator
                if hasSourceMeals && !isToggled {
                    sourceMealsIndicator
                }
            }

            Spacer()

            // Manual add indicator
            if item.isManuallyAdded {
                Image(systemName: "hand.draw.fill")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .opacity(isToggled ? 0.6 : 1.0)
        #if os(iOS)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                showingEditSheet = true
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(.blue)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                onToggle()
            } label: {
                if mode == .pantryCheck {
                    Label(
                        item.isInPantry ? "Need it" : "Have it",
                        systemImage: item.isInPantry ? "arrow.uturn.backward" : "checkmark"
                    )
                } else {
                    Label(
                        item.isChecked ? "Uncheck" : "Check",
                        systemImage: item.isChecked ? "arrow.uturn.backward" : "checkmark"
                    )
                }
            }
            .tint(isToggled ? .orange : .green)
        }
        #endif
        .contextMenu {
            Button {
                showingEditSheet = true
            } label: {
                Label("Edit", systemImage: "pencil")
            }

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            EditGroceryItemView(item: item)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabelText)
        .accessibilityHint(isToggled ? "Double tap to unmark" : "Double tap to mark")
        .accessibilityAddTraits(isToggled ? .isSelected : [])
        .accessibilityAction(named: isToggled ? "Unmark" : "Mark") {
            onToggle()
        }
        .accessibilityAction(named: "Edit") {
            showingEditSheet = true
        }
        .accessibilityAction(named: "Delete") {
            onDelete()
        }
    }

    // MARK: - Subviews

    /// Pantry mode: two explicit buttons — "Have" and "Need"
    private var pantryActionButton: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                onToggle()
            }
        } label: {
            Text(item.isInPantry ? "Need" : "Have")
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .foregroundStyle(item.isInPantry ? Color.primary : Color.white)
                .background(item.isInPantry ? Color.secondary.opacity(0.15) : Color.orange)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    /// Shopping mode: standard checkbox
    private var checkboxButton: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                onToggle()
            }
        } label: {
            Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundStyle(item.isChecked ? .green : .secondary)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
    }

    private var sourceMealsIndicator: some View {
        Button {
            showingMealsPopover = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "fork.knife")
                    .font(.caption2)

                Text(sourceMealsText)
                    .font(.caption)
            }
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        #if os(iOS)
        .popover(isPresented: $showingMealsPopover) {
            sourceMealsPopoverContent
        }
        #else
        .sheet(isPresented: $showingMealsPopover) {
            sourceMealsPopoverContent
        }
        #endif
    }

    private var sourceMealsText: String {
        let count = sourceMeals.count
        if count == 1 {
            if let slot = sourceMeals.first {
                return slotDescription(slot)
            }
            return "1 meal"
        }
        return "\(count) meals"
    }

    private var sourceMealsPopoverContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Needed for:")
                .font(.headline)

            ForEach(sourceMeals) { slot in
                HStack(spacing: 8) {
                    Image(systemName: "calendar")
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(slotDescription(slot))
                            .font(.subheadline)

                        if !slot.recipes.isEmpty {
                            Text(slot.recipes.map(\.title).joined(separator: ", "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if let customName = slot.customMealName {
                            Text(customName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding()
        .presentationCompactAdaptation(.popover)
    }

    private func slotDescription(_ slot: MealSlot) -> String {
        let day = slot.dayOfWeek.shortName
        let meal = slot.mealType.rawValue.capitalized
        return "\(day) \(meal)"
    }
}

// MARK: - Edit Grocery Item View

/// Sheet for editing a grocery item's details
struct EditGroceryItemView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var item: GroceryItem

    @State private var itemName: String = ""
    @State private var quantity: Double = 1
    @State private var selectedUnit: MeasurementUnit = .piece
    @State private var selectedCategory: IngredientCategory = .other

    var body: some View {
        NavigationStack {
            Form {
                Section("Item Details") {
                    TextField("Item name", text: $itemName)

                    HStack {
                        Text("Quantity")
                        Spacer()

                        Button {
                            if quantity > 1 { quantity -= 1 }
                        } label: {
                            Image(systemName: "minus.circle")
                                .font(.title3)
                                .foregroundStyle(quantity > 1 ? .primary : .tertiary)
                        }
                        .buttonStyle(.plain)
                        .disabled(quantity <= 1)

                        TextField("Qty", value: $quantity, format: .number)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.center)
                            #endif
                            .frame(width: 60)

                        Button {
                            quantity += 1
                        } label: {
                            Image(systemName: "plus.circle")
                                .font(.title3)
                        }
                        .buttonStyle(.plain)
                    }

                    Picker("Unit", selection: $selectedUnit) {
                        ForEach(MeasurementUnit.allCases, id: \.self) { unit in
                            Text(unit.displayName).tag(unit)
                        }
                    }
                }

                Section("Category") {
                    Picker("Category", selection: $selectedCategory) {
                        ForEach(IngredientCategory.allCases, id: \.self) { category in
                            Label(category.displayName, systemImage: category.iconName)
                                .tag(category)
                        }
                    }
                    #if os(iOS)
                    .pickerStyle(.navigationLink)
                    #else
                    .pickerStyle(.menu)
                    #endif
                }
            }
            .navigationTitle("Edit Item")
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
                        saveChanges()
                        dismiss()
                    }
                }
            }
            .onAppear {
                loadCurrentValues()
            }
        }
    }

    private func loadCurrentValues() {
        itemName = item.customName ?? item.ingredient?.name ?? ""
        quantity = item.quantity
        selectedUnit = item.unit
        selectedCategory = item.category
    }

    private func saveChanges() {
        let trimmedName = itemName.trimmingCharacters(in: .whitespaces)
        // Set customName as override if it differs from the ingredient name, or always for manual items
        if item.ingredient == nil {
            item.customName = trimmedName
        } else if trimmedName != item.ingredient?.name {
            item.customName = trimmedName
        } else {
            item.customName = nil // Clear override if it matches ingredient name
        }
        item.quantity = quantity
        item.unit = selectedUnit
        item.category = selectedCategory
    }
}

// Note: MeasurementUnit.displayName and abbreviation are defined in Enums.swift
// Note: DayOfWeek.shortName is defined in Enums.swift

// MARK: - Preview

#Preview {
    List {
        // Preview would require mock data
        Text("GroceryItemRow Preview")
    }
    #if os(iOS)
    .listStyle(.insetGrouped)
    #endif
}
