import SwiftUI
import SwiftData

/// Sheet view for manually adding a new grocery item
struct AddGroceryItemView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let weekPlan: WeekPlan?

    @State private var itemName = ""
    @State private var quantity: Double = 1
    @State private var selectedUnit: MeasurementUnit = .piece
    @State private var selectedCategory: IngredientCategory = .other
    @State private var searchText = ""

    @Query private var ingredients: [Ingredient]

    /// Filtered ingredients based on search
    private var filteredIngredients: [Ingredient] {
        guard !searchText.isEmpty else { return [] }
        return ingredients.filter { ingredient in
            ingredient.name.localizedCaseInsensitiveContains(searchText) ||
            ingredient.normalizedName.contains(searchText.lowercased())
        }
        .prefix(10)
        .map { $0 }
    }

    /// Whether the form is valid for submission
    private var isFormValid: Bool {
        !itemName.trimmingCharacters(in: .whitespaces).isEmpty && weekPlan != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                // Item name section with ingredient search
                itemNameSection

                // Quantity and unit section
                quantitySection

                // Category picker section
                categorySection
            }
            .navigationTitle("Add Item")
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
                    Button("Add") {
                        addItem()
                    }
                    .disabled(!isFormValid)
                }
            }
        }
    }

    // MARK: - Sections

    private var itemNameSection: some View {
        Section {
            TextField("Item name", text: $itemName)
                .autocorrectionDisabled()
                .onChange(of: itemName) { _, newValue in
                    searchText = newValue
                }

            // Ingredient suggestions
            if !filteredIngredients.isEmpty {
                ForEach(filteredIngredients) { ingredient in
                    Button {
                        selectIngredient(ingredient)
                    } label: {
                        HStack {
                            Label {
                                Text(ingredient.name)
                            } icon: {
                                Image(systemName: ingredient.category.iconName)
                                    .foregroundStyle(ingredient.category.color)
                            }

                            Spacer()

                            Text(ingredient.category.displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            Text("Item")
        } footer: {
            Text("Type to search existing ingredients or enter a custom item name.")
        }
    }

    private var quantitySection: some View {
        Section("Quantity") {
            HStack {
                Text("Amount")
                Spacer()

                // Decrease button
                Button {
                    if quantity > 0.5 {
                        quantity -= 0.5
                    }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                // Quantity input
                TextField("Qty", value: $quantity, format: .number)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
                    .multilineTextAlignment(.center)
                    .frame(width: 60)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.systemGray6)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                // Increase button
                Button {
                    quantity += 0.5
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Picker("Unit", selection: $selectedUnit) {
                ForEach(MeasurementUnit.allCases, id: \.self) { unit in
                    Text(unit.displayName).tag(unit)
                }
            }
            .pickerStyle(.menu)
        }
    }

    private var categorySection: some View {
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

            // Quick category buttons for common categories
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(IngredientCategory.allCases.prefix(6), id: \.self) { category in
                        CategoryChip(
                            category: category,
                            isSelected: selectedCategory == category
                        ) {
                            selectedCategory = category
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Actions

    private func selectIngredient(_ ingredient: Ingredient) {
        itemName = ingredient.name
        selectedCategory = ingredient.category
        selectedUnit = ingredient.defaultUnit
        searchText = "" // Clear search to hide suggestions
    }

    private func addItem() {
        guard let weekPlan = weekPlan else { return }

        let trimmedName = itemName.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        // Check if there's a matching ingredient
        let matchingIngredient = ingredients.first { $0.normalizedName == trimmedName.lowercased() }

        let newItem = GroceryItem.create(
            ingredient: matchingIngredient,
            customName: matchingIngredient == nil ? trimmedName : nil,
            quantity: quantity,
            unit: selectedUnit,
            category: matchingIngredient?.category ?? selectedCategory,
            weekPlan: weekPlan
        )

        modelContext.insert(newItem)
        weekPlan.groceryItems.append(newItem)
        dismiss()
    }
}

// MARK: - Category Chip

/// Quick-select chip for common categories
struct CategoryChip: View {
    let category: IngredientCategory
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: category.iconName)
                    .font(.caption)
                Text(category.displayName)
                    .font(.caption)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? category.color.opacity(0.2) : Color.systemGray6)
            .foregroundStyle(isSelected ? category.color : .secondary)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(isSelected ? category.color : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - GroceryItem Factory

extension GroceryItem {
    /// Factory method for creating grocery items with ingredient or custom name
    static func create(
        ingredient: Ingredient? = nil,
        customName: String? = nil,
        quantity: Double,
        unit: MeasurementUnit,
        category: IngredientCategory,
        weekPlan: WeekPlan
    ) -> GroceryItem {
        if let ingredient = ingredient {
            let item = GroceryItem(
                ingredient: ingredient,
                quantity: quantity,
                unit: unit,
                weekPlan: weekPlan
            )
            item.isManuallyAdded = true
            item.pantryChecked = true
            return item
        } else {
            let item = GroceryItem(
                customName: customName ?? "Unknown Item",
                quantity: quantity,
                unit: unit,
                category: category,
                weekPlan: weekPlan
            )
            return item
        }
    }
}

// MARK: - Preview

#Preview {
    AddGroceryItemView(weekPlan: nil)
        .modelContainer(for: [Ingredient.self, GroceryItem.self], inMemory: true)
}
