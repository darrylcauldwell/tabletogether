import SwiftUI
import CoreData

/// Sidebar recipe browser for iPad, showing a searchable, draggable list of recipes.
/// Displayed when the user toggles the sidebar to "Recipes" mode while on the Plan section.
struct SidebarRecipeBrowserView: View {
    @Binding var sidebarMode: SidebarMode
    @FetchRequest(sortDescriptors: [SortDescriptor(\.title)]) private var recipes: FetchedResults<Recipe>

    @State private var searchText: String = ""
    @State private var selectedArchetype: ArchetypeType?

    private var filteredRecipes: [Recipe] {
        var result = Array(recipes)

        if !searchText.isEmpty {
            result = result.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
        }

        if let archetype = selectedArchetype {
            result = result.filter { $0.suggestedArchetypes.contains(archetype) }
        }

        return result
    }

    var body: some View {
        List {
            Section {
                Picker("Sidebar Mode", selection: $sidebarMode) {
                    Text("Menu").tag(SidebarMode.navigation)
                    Text("Recipes").tag(SidebarMode.recipeBrowser)
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
            }

            Section {
                // Archetype filter chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ArchetypeFilterChip(name: "All", isSelected: selectedArchetype == nil) {
                            selectedArchetype = nil
                        }

                        ForEach(ArchetypeType.allCases) { archetype in
                            ArchetypeFilterChip(
                                name: archetype.displayName,
                                isSelected: selectedArchetype == archetype
                            ) {
                                if selectedArchetype == archetype {
                                    selectedArchetype = nil
                                } else {
                                    selectedArchetype = archetype
                                }
                            }
                        }
                    }
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                .listRowBackground(Color.clear)
            }

            Section {
                ForEach(filteredRecipes) { recipe in
                    SidebarRecipeRow(recipe: recipe)
                }
            }
        }
        #if os(iOS)
        .listStyle(.sidebar)
        #endif
        .searchable(text: $searchText, prompt: "Search recipes")
    }
}

// MARK: - Archetype Filter Chip

struct ArchetypeFilterChip: View {
    let name: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(name)
                .font(AppTypography.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(isSelected ? Color.accentColor.opacity(0.2) : Color.systemGray6)
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - SidebarRecipeRow

/// Compact row for the sidebar recipe browser, supporting drag-and-drop.
struct SidebarRecipeRow: View {
    let recipe: Recipe

    var body: some View {
        HStack(spacing: 10) {
            RecipeImageView(imageData: recipe.imageData, imageURL: recipe.imageURL)
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                Text(recipe.title)
                    .font(AppTypography.subheadline)
                    .lineLimit(1)
                    .foregroundStyle(.primary)

                if let totalTime = recipe.totalTimeMinutes {
                    Text("\(totalTime) min")
                        .font(AppTypography.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Drag grip indicator
            Image(systemName: "line.3.horizontal")
                .font(AppTypography.caption)
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        #if os(iOS)
        .draggable(recipe.id.uuidString) {
            DragPreviewCard(recipe: recipe)
        }
        #endif
    }
}

// MARK: - Preview

#Preview {
    SidebarRecipeBrowserView(sidebarMode: .constant(.recipeBrowser))
        .frame(width: 300)
        .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
}
