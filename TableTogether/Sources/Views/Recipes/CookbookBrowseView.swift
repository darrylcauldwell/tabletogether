import SwiftUI
import CoreData

// MARK: - CookbookBrowseView
//
// A bookshelf-style browse view that groups the recipe library by the
// existing `Recipe.cookbook` string field. Surfaces the cookbook attribution
// already populated by the Paprika importer (#58) as a discoverable browsing
// experience.
//
// Scoped intentionally small per #63 — uses the existing string field, no
// Core Data changes. The bigger vision (user-created collections,
// many-to-many, cover images) lives in #25.

struct CookbookBrowseView: View {
    @FetchRequest(sortDescriptors: [SortDescriptor(\.title)])
    private var recipes: FetchedResults<Recipe>

    /// Sentinel name used for recipes that have no cookbook attribution.
    /// Kept private so callers can't accidentally use it as a real name.
    private static let uncategorisedKey = "__uncategorised__"

    /// Recipes grouped by their cookbook field. The uncategorised group, if
    /// present, is keyed by `uncategorisedKey` so it can be sorted to the end.
    private var groupedRecipes: [(name: String, recipes: [Recipe])] {
        var groups: [String: [Recipe]] = [:]
        for recipe in recipes {
            let key = recipe.cookbook?.trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty ?? Self.uncategorisedKey
            groups[key, default: []].append(recipe)
        }

        // Sort cookbook names alphabetically, with the uncategorised group last.
        return groups
            .sorted { a, b in
                if a.key == Self.uncategorisedKey { return false }
                if b.key == Self.uncategorisedKey { return true }
                return a.key.localizedCompare(b.key) == .orderedAscending
            }
            .map { (name: $0.key, recipes: $0.value) }
    }

    private var hasAnyCookbook: Bool {
        recipes.contains { ($0.cookbook?.nilIfEmpty) != nil }
    }

    var body: some View {
        Group {
            if recipes.isEmpty {
                EmptyStateView(
                    icon: "books.vertical",
                    title: "No Recipes Yet",
                    message: "Import recipes from a cookbook or add them manually to start building your shelf.",
                    action: nil,
                    actionLabel: nil
                )
            } else if !hasAnyCookbook {
                EmptyStateView(
                    icon: "books.vertical",
                    title: "No Cookbook Attributions",
                    message: "Recipes you import from Paprika carry their source as a cookbook. You can also set one manually in the recipe editor.",
                    action: nil,
                    actionLabel: nil
                )
            } else {
                cookbookList
            }
        }
        .background(Color.appBackground)
        .navigationTitle("Cookbooks")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var cookbookList: some View {
        List {
            ForEach(groupedRecipes, id: \.name) { group in
                NavigationLink {
                    CookbookDetailView(
                        cookbookName: group.name == Self.uncategorisedKey ? "Other Recipes" : group.name,
                        recipes: group.recipes
                    )
                } label: {
                    cookbookRow(name: group.name, count: group.recipes.count)
                }
            }
        }
        .listStyle(.plain)
        #if os(iOS)
        .scrollContentBackground(.hidden)
        #endif
    }

    private func cookbookRow(name: String, count: Int) -> some View {
        let isUncategorised = name == Self.uncategorisedKey
        let displayName = isUncategorised ? "Other Recipes" : name

        return HStack(spacing: 14) {
            Image(systemName: isUncategorised ? "tray" : "book.closed.fill")
                .font(.title3)
                .foregroundStyle(Theme.Colors.primary)
                .frame(width: 32, height: 32)
                .background(Theme.Colors.primary.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(.body)
                    .fontWeight(isUncategorised ? .regular : .semibold)
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text("\(count) \(count == 1 ? "recipe" : "recipes")")
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(displayName), \(count) \(count == 1 ? "recipe" : "recipes")")
    }
}

// MARK: - CookbookDetailView
//
// Shows all recipes from a single cookbook. Reuses the existing
// `RecipeCardView` (list style) so it visually matches the recipe library.

struct CookbookDetailView: View {
    let cookbookName: String
    let recipes: [Recipe]

    @State private var selectedRecipe: Recipe?

    private var sortedRecipes: [Recipe] {
        recipes.sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
    }

    var body: some View {
        List {
            ForEach(sortedRecipes) { recipe in
                Button {
                    selectedRecipe = recipe
                } label: {
                    RecipeCardView(recipe: recipe, style: .list)
                }
                .buttonStyle(.plain)
                #if os(iOS)
                .listRowSeparator(.hidden)
                #endif
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        #if os(iOS)
        .scrollContentBackground(.hidden)
        #endif
        .background(Color.appBackground)
        .navigationTitle(cookbookName)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .navigationDestination(item: $selectedRecipe) { recipe in
            RecipeDetailView(recipe: recipe)
        }
    }
}

// MARK: - String helper

private extension String {
    /// Returns nil if the string is empty after trimming whitespace, else self.
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        CookbookBrowseView()
    }
    .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
}
