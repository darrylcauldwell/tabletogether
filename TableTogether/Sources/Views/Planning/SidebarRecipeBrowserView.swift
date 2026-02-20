import SwiftUI
import SwiftData

/// Sidebar recipe browser for iPad, showing a searchable, draggable list of recipes.
/// Displayed when the user toggles the sidebar to "Recipes" mode while on the Plan section.
struct SidebarRecipeBrowserView: View {
    @Binding var sidebarMode: SidebarMode
    @Query(sort: \Recipe.title) private var recipes: [Recipe]

    @State private var searchText: String = ""
    @State private var selectedArchetype: ArchetypeType?

    private var filteredRecipes: [Recipe] {
        var result = recipes

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
                .font(.caption)
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
            // Thumbnail
            #if canImport(UIKit)
            if let imageData = recipe.imageData, let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                RecipePlaceholderImage(size: 44)
            }
            #elseif canImport(AppKit)
            if let imageData = recipe.imageData, let nsImage = NSImage(data: imageData) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                RecipePlaceholderImage(size: 44)
            }
            #endif

            VStack(alignment: .leading, spacing: 2) {
                Text(recipe.title)
                    .font(.subheadline)
                    .lineLimit(1)
                    .foregroundStyle(.primary)

                if let totalTime = recipe.totalTimeMinutes {
                    Text("\(totalTime) min")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Drag grip indicator
            Image(systemName: "line.3.horizontal")
                .font(.caption)
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
        .modelContainer(for: [Recipe.self, MealArchetype.self], inMemory: true)
}
