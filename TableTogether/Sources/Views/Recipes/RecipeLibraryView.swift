import SwiftUI
import SwiftData

/// The main recipe library view displaying all recipes in the user's collection.
/// Supports search, filtering by archetype, and toggle between grid and list views.
struct RecipeLibraryView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Recipe.title)
    private var recipes: [Recipe]

    @State private var searchText = ""
    @State private var selectedArchetypes: Set<ArchetypeType> = []
    @State private var sortOption: SortOption = .title
    @State private var isGridView = true
    @State private var showingAddMenu = false
    @State private var showingImportSheet = false
    @State private var showingEditorSheet = false
    @State private var showingGeneratorSheet = false
    @State private var selectedRecipe: Recipe?

    enum SortOption: String, CaseIterable, Identifiable {
        case title = "Alphabetical"
        case recent = "Most Recent"
        case mostCooked = "Most Cooked"
        case favorite = "Favorites First"

        var id: String { rawValue }
    }

    // MARK: - Filtered and Sorted Recipes

    private var filteredRecipes: [Recipe] {
        var result = recipes

        // Apply search filter
        if !searchText.isEmpty {
            result = result.filter { recipe in
                recipe.title.localizedCaseInsensitiveContains(searchText) ||
                (recipe.summary?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                recipe.tags.contains { $0.localizedCaseInsensitiveContains(searchText) }
            }
        }

        // Apply archetype filter
        if !selectedArchetypes.isEmpty {
            result = result.filter { recipe in
                !Set(recipe.suggestedArchetypes).isDisjoint(with: selectedArchetypes)
            }
        }

        // Apply sorting
        switch sortOption {
        case .title:
            result.sort { $0.title.localizedCompare($1.title) == .orderedAscending }
        case .recent:
            result.sort { $0.createdAt > $1.createdAt }
        case .mostCooked:
            result.sort { $0.timesCooked > $1.timesCooked }
        case .favorite:
            result.sort { ($0.isFavorite ? 0 : 1) < ($1.isFavorite ? 0 : 1) }
        }

        return result
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                VStack(spacing: 0) {
                    // Search and Filter Bar
                    searchAndFilterBar
                        .padding()

                    // Content
                    if recipes.isEmpty {
                        emptyStateView
                    } else if filteredRecipes.isEmpty {
                        noResultsView
                    } else {
                        recipeContent
                    }
                }
                .background(Color.appBackground)

                // Floating Action Button
                FloatingActionButton {
                    showingAddMenu = true
                } content: {
                    Image(systemName: "plus")
                }
                .padding(20)
            }
            .navigationTitle("Recipes")
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 16) {
                        // Sort menu
                        Menu {
                            ForEach(SortOption.allCases) { option in
                                Button {
                                    sortOption = option
                                } label: {
                                    HStack {
                                        Text(option.rawValue)
                                        if sortOption == option {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            Image(systemName: "arrow.up.arrow.down")
                                .foregroundColor(.appPrimary)
                        }

                        // Grid/List toggle
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isGridView.toggle()
                            }
                        } label: {
                            Image(systemName: isGridView ? "list.bullet" : "square.grid.2x2")
                                .foregroundColor(.appPrimary)
                        }
                    }
                }
                #else
                ToolbarItem(placement: .automatic) {
                    HStack(spacing: 16) {
                        // Sort menu
                        Menu {
                            ForEach(SortOption.allCases) { option in
                                Button {
                                    sortOption = option
                                } label: {
                                    HStack {
                                        Text(option.rawValue)
                                        if sortOption == option {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            Image(systemName: "arrow.up.arrow.down")
                                .foregroundColor(.appPrimary)
                        }

                        // Grid/List toggle
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isGridView.toggle()
                            }
                        } label: {
                            Image(systemName: isGridView ? "list.bullet" : "square.grid.2x2")
                                .foregroundColor(.appPrimary)
                        }
                    }
                }
                #endif
            }
            .navigationDestination(item: $selectedRecipe) { recipe in
                RecipeDetailView(recipe: recipe)
            }
            .confirmationDialog("Add Recipe", isPresented: $showingAddMenu) {
                Button {
                    showingGeneratorSheet = true
                } label: {
                    Label("Generate with AI", systemImage: "wand.and.stars")
                }
                Button("Import from URL") {
                    showingImportSheet = true
                }
                Button("Create Manually") {
                    showingEditorSheet = true
                }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(isPresented: $showingImportSheet) {
                RecipeImportSheet()
            }
            .sheet(isPresented: $showingEditorSheet) {
                NavigationStack {
                    RecipeEditorView(recipe: nil)
                }
            }
            .sheet(isPresented: $showingGeneratorSheet) {
                RecipeGeneratorView()
            }
        }
    }

    // MARK: - Search and Filter Bar

    private var searchAndFilterBar: some View {
        VStack(spacing: 12) {
            // Search field
            SearchBar(text: $searchText, placeholder: "Search recipes")

            // Archetype filter chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // "All" chip
                    FilterChip(
                        title: "All",
                        isSelected: selectedArchetypes.isEmpty,
                        action: {
                            selectedArchetypes.removeAll()
                        }
                    )

                    ForEach(ArchetypeType.allCases) { archetype in
                        FilterChip(
                            title: archetype.displayName,
                            isSelected: selectedArchetypes.contains(archetype),
                            icon: archetype.icon,
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
            }
        }
    }

    // MARK: - Recipe Content

    @ViewBuilder
    private var recipeContent: some View {
        if isGridView {
            gridView
        } else {
            listView
        }
    }

    private var gridView: some View {
        let columns = [
            GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 16)
        ]

        return ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(filteredRecipes) { recipe in
                    Button {
                        selectedRecipe = recipe
                    } label: {
                        RecipeCardView(recipe: recipe, style: .grid)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        recipeContextMenu(for: recipe)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 100) // Space for FAB
        }
    }

    private var listView: some View {
        List {
            ForEach(filteredRecipes) { recipe in
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
                .contextMenu {
                    recipeContextMenu(for: recipe)
                }
            }
        }
        .listStyle(.plain)
        #if os(iOS)
        .scrollContentBackground(.hidden)
        #endif
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func recipeContextMenu(for recipe: Recipe) -> some View {
        Button {
            toggleFavorite(recipe)
        } label: {
            Label(
                recipe.isFavorite ? "Remove from Favorites" : "Add to Favorites",
                systemImage: recipe.isFavorite ? "heart.slash" : "heart"
            )
        }

        Button {
            // Edit recipe
            selectedRecipe = recipe
        } label: {
            Label("Edit", systemImage: "pencil")
        }

        Divider()

        Button(role: .destructive) {
            deleteRecipe(recipe)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    // MARK: - Empty States

    private var emptyStateView: some View {
        EmptyStateView(
            icon: "book.closed",
            title: "Your Recipe Collection Awaits",
            message: "Import your first recipe to get started. You can import from a URL or create one manually.",
            action: {
                showingAddMenu = true
            },
            actionLabel: "Add Recipe"
        )
    }

    private var noResultsView: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.appTextSecondary)

            Text("No Recipes Found")
                .font(.appHeading)
                .foregroundColor(.appTextPrimary)

            Text("Try adjusting your search or filters.")
                .font(.appBody)
                .foregroundColor(.appTextSecondary)

            Button("Clear Filters") {
                searchText = ""
                selectedArchetypes.removeAll()
            }
            .buttonStyle(SecondaryButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func toggleFavorite(_ recipe: Recipe) {
        recipe.isFavorite.toggle()
        recipe.modifiedAt = Date()
    }

    private func deleteRecipe(_ recipe: Recipe) {
        modelContext.delete(recipe)
    }
}

// MARK: - Preview

#Preview {
    RecipeLibraryView()
        .modelContainer(for: Recipe.self, inMemory: true)
}
