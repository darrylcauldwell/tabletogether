import SwiftUI
import CoreData

// MARK: - IngredientLibraryView
//
// Browse, search, filter, and edit Ingredient master records (#59 Phase 6).
// Reachable from Settings → Data → Ingredient Library.
//
// The list itself is intentionally sparse — name, category, usage count,
// alias indicator. Curation happens in the detail view.

struct IngredientLibraryView: View {
    @Environment(\.managedObjectContext) private var viewContext

    @FetchRequest(
        sortDescriptors: [SortDescriptor(\.name)],
        animation: .default
    )
    private var ingredients: FetchedResults<Ingredient>

    @State private var searchText: String = ""
    @State private var selectedCategory: IngredientCategory? = nil
    @State private var sortBy: SortOption = .name

    enum SortOption: String, CaseIterable, Identifiable {
        case name = "Name"
        case usage = "Most Used"
        var id: String { rawValue }
    }

    private var filteredIngredients: [Ingredient] {
        var result = Array(ingredients)

        // Search by name OR alias
        if !searchText.isEmpty {
            let q = searchText.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            result = result.filter { ingredient in
                ingredient.normalizedName.contains(q) ||
                ingredient.userAliasesList.contains(where: { $0.contains(q) })
            }
        }

        // Filter by category
        if let category = selectedCategory {
            result = result.filter { $0.category == category }
        }

        // Sort
        switch sortBy {
        case .name:
            result.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .usage:
            result.sort { $0.recipeIngredientsArray.count > $1.recipeIngredientsArray.count }
        }

        return result
    }

    var body: some View {
        Group {
            if ingredients.isEmpty {
                emptyState
            } else {
                List {
                    Section {
                        Picker("Sort", selection: $sortBy) {
                            ForEach(SortOption.allCases) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    Section {
                        categoryCategoryFilterChips
                    }

                    Section {
                        ForEach(filteredIngredients, id: \.objectID) { ingredient in
                            NavigationLink {
                                IngredientDetailView(ingredient: ingredient)
                            } label: {
                                IngredientLibraryRow(ingredient: ingredient)
                            }
                        }
                    } header: {
                        Text("\(filteredIngredients.count) ingredient\(filteredIngredients.count == 1 ? "" : "s")")
                    }
                }
                #if os(iOS)
                .listStyle(.insetGrouped)
                #endif
                .searchable(text: $searchText, prompt: "Search name or alias")
            }
        }
        .navigationTitle("Ingredient Library")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // MARK: - Subviews

    private var categoryCategoryFilterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                CategoryFilterChip(
                    title: "All",
                    icon: nil,
                    isSelected: selectedCategory == nil,
                    action: { selectedCategory = nil }
                )
                ForEach(IngredientCategory.allCases.sorted(by: { $0.sortOrder < $1.sortOrder }), id: \.self) { category in
                    CategoryFilterChip(
                        title: category.displayName,
                        icon: category.iconName,
                        isSelected: selectedCategory == category,
                        action: {
                            selectedCategory = (selectedCategory == category) ? nil : category
                        }
                    )
                }
            }
            .padding(.vertical, 4)
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 0))
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "leaf")
                .font(AppTypography.fixed(48))
                .foregroundStyle(Theme.Colors.textSecondary)
            Text("No Ingredients Yet")
                .font(AppTypography.title3)
                .fontWeight(.medium)
            Text("Ingredient master records are created when you import recipes or run **Reorganise Ingredient Library** in Settings.")
                .font(AppTypography.subheadline)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - IngredientLibraryRow

private struct IngredientLibraryRow: View {
    let ingredient: Ingredient

    private var recipeCount: Int {
        // Distinct recipes (in case the same ingredient appears multiple
        // times in one recipe via different RecipeIngredient rows).
        Set(ingredient.recipeIngredientsArray.compactMap { $0.recipe }).count
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: ingredient.category.iconName)
                .font(AppTypography.body)
                .foregroundStyle(Theme.Colors.primary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(ingredient.name)
                    .font(AppTypography.body)
                    .lineLimit(1)
                if !ingredient.userAliasesList.isEmpty {
                    Text("\(ingredient.userAliasesList.count) alias\(ingredient.userAliasesList.count == 1 ? "" : "es")")
                        .font(AppTypography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }

            Spacer()

            if recipeCount > 0 {
                Text("\(recipeCount)")
                    .font(AppTypography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Theme.Colors.primary.opacity(0.12))
                    .clipShape(Capsule())
            }
        }
    }
}

// MARK: - CategoryFilterChip (lightweight, scoped to this file)
//
// The DesignSystem already exposes a CategoryFilterChip but it has a different
// signature. Inline a tiny one here scoped to library navigation.

private struct CategoryFilterChip: View {
    let title: String
    let icon: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon {
                    Image(systemName: icon)
                        .font(AppTypography.caption)
                }
                Text(title)
                    .font(AppTypography.caption)
                    .fontWeight(isSelected ? .semibold : .regular)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Theme.Colors.primary.opacity(0.2) : Color.clear)
            .overlay(
                Capsule()
                    .strokeBorder(isSelected ? Theme.Colors.primary : Theme.Colors.textSecondary.opacity(0.3), lineWidth: 1)
            )
            .clipShape(Capsule())
            .foregroundStyle(isSelected ? Theme.Colors.primary : Theme.Colors.textSecondary)
        }
        .buttonStyle(.plain)
    }
}
