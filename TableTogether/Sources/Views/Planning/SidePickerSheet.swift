import SwiftUI
import CoreData

/// What the user picked in `SidePickerSheet` to add to a plate as a side.
enum SideChoice {
    case ingredient(Ingredient)
    case foodItem(FoodItem)
}

/// Picker for adding a non-recipe **side** to a meal plate — rice, naan, veg, or a
/// branded item. Searches the FoodItem library (reliable macros) and the
/// Ingredient library. Owns no model objects and performs no writes: it emits a
/// `SideChoice` and the caller attaches the component (matching RecipePickerSheet).
struct SidePickerSheet: View {
    let onChoose: (SideChoice) -> Void
    @Environment(\.dismiss) private var dismiss

    @FetchRequest(sortDescriptors: [SortDescriptor(\.displayName)]) private var foodItems: FetchedResults<FoodItem>
    @FetchRequest(sortDescriptors: [SortDescriptor(\.name)]) private var ingredients: FetchedResults<Ingredient>
    @State private var searchText = ""

    private var trimmed: String { searchText.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var filteredFoodItems: [FoodItem] {
        if trimmed.isEmpty { return Array(foodItems.prefix(15)) }
        return foodItems.filter { $0.displayName.localizedCaseInsensitiveContains(trimmed) }
    }

    private var filteredIngredients: [Ingredient] {
        if trimmed.isEmpty { return Array(ingredients.prefix(15)) }
        return ingredients.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
    }

    var body: some View {
        NavigationStack {
            List {
                if !filteredFoodItems.isEmpty {
                    Section("Foods") {
                        ForEach(filteredFoodItems) { food in
                            Button {
                                onChoose(.foodItem(food))
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(food.displayName)
                                        .font(AppTypography.body)
                                        .foregroundStyle(.primary)
                                    if let brand = food.brandOwner, !brand.isEmpty {
                                        Text(brand)
                                            .font(AppTypography.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }

                if !filteredIngredients.isEmpty {
                    Section("Ingredients") {
                        ForEach(filteredIngredients) { ingredient in
                            Button {
                                onChoose(.ingredient(ingredient))
                                dismiss()
                            } label: {
                                HStack {
                                    Text(ingredient.name)
                                        .font(AppTypography.body)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if !ingredient.hasMacroData {
                                        // Calm, informational — not a warning colour.
                                        Text("no macros")
                                            .font(AppTypography.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }

                if filteredFoodItems.isEmpty && filteredIngredients.isEmpty {
                    Text("No matches. Sides come from your Foods and Ingredients libraries.")
                        .font(AppTypography.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .searchable(text: $searchText, prompt: "Search sides")
            .navigationTitle("Add a side")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
