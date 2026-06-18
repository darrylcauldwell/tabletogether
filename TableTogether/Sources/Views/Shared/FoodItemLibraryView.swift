import SwiftUI
import CoreData

// MARK: - FoodItemLibraryView
//
// Browse, search, filter, and edit FoodItem master records (#59 Phase 7).
// Reachable from Settings → Libraries → Food Item Library.
//
// Mirrors IngredientLibraryView in structure but the field set is different:
// FoodItem carries USDA-sourced nutrition data plus brand metadata, and is
// referenced by MealSlotComponent (the trinary meal-slot-component system).

struct FoodItemLibraryView: View {
    @Environment(\.managedObjectContext) private var viewContext

    @FetchRequest(
        sortDescriptors: [SortDescriptor(\.displayName)],
        animation: .default
    )
    private var foodItems: FetchedResults<FoodItem>

    @State private var searchText: String = ""
    @State private var selectedSource: SourceFilter = .all
    @State private var sortBy: SortOption = .name

    enum SourceFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case usda = "USDA"
        case branded = "Branded"
        case userCreated = "Custom"
        var id: String { rawValue }
    }

    enum SortOption: String, CaseIterable, Identifiable {
        case name = "Name"
        case usage = "Most Used"
        var id: String { rawValue }
    }

    private var filteredItems: [FoodItem] {
        var result = Array(foodItems)

        // Search by displayName OR alias OR usdaDescription
        if !searchText.isEmpty {
            let q = searchText.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            result = result.filter { item in
                item.normalizedName.contains(q) ||
                item.userAliasesList.contains(where: { $0.contains(q) }) ||
                item.usdaDescription.lowercased().contains(q)
            }
        }

        // Filter by source
        switch selectedSource {
        case .all:
            break
        case .usda:
            result = result.filter { isUSDASource($0) }
        case .branded:
            result = result.filter { $0.dataType == "Branded" }
        case .userCreated:
            result = result.filter { !isUSDASource($0) && $0.dataType != "Branded" }
        }

        // Sort
        switch sortBy {
        case .name:
            result.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        case .usage:
            result.sort { mealSlotCount($0) > mealSlotCount($1) }
        }

        return result
    }

    private func isUSDASource(_ item: FoodItem) -> Bool {
        ["Foundation", "SR Legacy", "Survey (FNDDS)"].contains(item.dataType)
    }

    private func mealSlotCount(_ item: FoodItem) -> Int {
        ((item.mealSlotComponents?.allObjects as? [MealSlotComponent]) ?? []).count
    }

    var body: some View {
        Group {
            if foodItems.isEmpty {
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

                        Picker("Source", selection: $selectedSource) {
                            ForEach(SourceFilter.allCases) { source in
                                Text(source.rawValue).tag(source)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    Section {
                        ForEach(filteredItems, id: \.objectID) { item in
                            NavigationLink {
                                FoodItemDetailView(foodItem: item)
                            } label: {
                                FoodItemLibraryRow(foodItem: item, mealSlotCount: mealSlotCount(item))
                            }
                        }
                    } header: {
                        Text("\(filteredItems.count) food item\(filteredItems.count == 1 ? "" : "s")")
                    }
                }
                #if os(iOS)
                .listStyle(.insetGrouped)
                #endif
                .searchable(text: $searchText, prompt: "Search name, alias, or USDA description")
            }
        }
        .navigationTitle("Food Item Library")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "fork.knife.circle")
                .font(AppTypography.fixed(48))
                .foregroundStyle(Theme.Colors.textSecondary)
            Text("No Food Items Yet")
                .font(AppTypography.title3)
                .fontWeight(.medium)
            Text("Food items are cached when you log meals — TableTogether queries USDA when you describe what you ate, and saves the result here for next time.")
                .font(AppTypography.subheadline)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - FoodItemLibraryRow

private struct FoodItemLibraryRow: View {
    let foodItem: FoodItem
    let mealSlotCount: Int

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: sourceIcon)
                .font(AppTypography.body)
                .foregroundStyle(Theme.Colors.primary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(foodItem.displayName)
                    .font(AppTypography.body)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if let brand = foodItem.brandOwner, !brand.isEmpty {
                        Text(brand)
                            .font(AppTypography.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .lineLimit(1)
                    } else {
                        Text(foodItem.dataType)
                            .font(AppTypography.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    if !foodItem.userAliasesList.isEmpty {
                        Text("• \(foodItem.userAliasesList.count) alias\(foodItem.userAliasesList.count == 1 ? "" : "es")")
                            .font(AppTypography.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
            }

            Spacer()

            if mealSlotCount > 0 {
                Text("\(mealSlotCount)")
                    .font(AppTypography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Theme.Colors.primary.opacity(0.12))
                    .clipShape(Capsule())
            }
        }
    }

    private var sourceIcon: String {
        switch foodItem.dataType {
        case "Branded": return "tag.fill"
        case "Foundation", "SR Legacy", "Survey (FNDDS)": return "leaf.circle.fill"
        default: return "fork.knife.circle"
        }
    }
}
