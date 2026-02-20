import SwiftUI
import SwiftData

/// A card view displaying a recipe preview with image, title, archetypes, and time estimate.
/// Used in both grid and list layouts within RecipeLibraryView.
struct RecipeCardView: View {
    let recipe: Recipe
    var style: CardLayoutStyle = .grid

    enum CardLayoutStyle {
        case grid
        case list
    }

    var body: some View {
        Group {
            switch style {
            case .grid:
                gridLayout
            case .list:
                listLayout
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(recipeAccessibilityLabel)
        .accessibilityHint("Double tap to view recipe details")
    }

    private var recipeAccessibilityLabel: String {
        var parts: [String] = [recipe.title]

        if recipe.isFavorite {
            parts.append("Favorite")
        }

        if let time = recipe.formattedTotalTime {
            parts.append(time)
        }

        parts.append("\(recipe.servings) servings")

        if !recipe.suggestedArchetypes.isEmpty {
            let archetypes = recipe.suggestedArchetypes.prefix(2).map { $0.displayName }.joined(separator: " and ")
            parts.append(archetypes)
        }

        return parts.joined(separator: ". ")
    }

    // MARK: - Grid Layout

    private var gridLayout: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Recipe Image
            recipeImage
                .frame(height: 120)
                .clipped()

            VStack(alignment: .leading, spacing: 6) {
                // Title with favorite indicator
                HStack {
                    Text(recipe.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.appTextPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Spacer()

                    if recipe.isFavorite {
                        Image(systemName: "heart.fill")
                            .font(.caption)
                            .foregroundColor(.appSecondary)
                    }
                }

                // Archetype tags
                if !recipe.suggestedArchetypes.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(Array(recipe.suggestedArchetypes.prefix(2)), id: \.self) { archetype in
                                ArchetypeBadge(archetype: archetype, compact: true)
                            }
                        }
                    }
                }

                // Time estimate
                if let time = recipe.formattedTotalTime {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.caption2)
                        Text(time)
                            .font(.caption)
                    }
                    .foregroundColor(.appTextSecondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .background(Color.systemBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 2)
    }

    // MARK: - List Layout

    private var listLayout: some View {
        HStack(spacing: 12) {
            // Recipe Image (smaller for list)
            recipeImage
                .frame(width: 80, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                // Title with favorite indicator
                HStack {
                    Text(recipe.title)
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundColor(.appTextPrimary)
                        .lineLimit(1)

                    Spacer()

                    if recipe.isFavorite {
                        Image(systemName: "heart.fill")
                            .font(.caption)
                            .foregroundColor(.appSecondary)
                    }
                }

                // Archetype tags
                if !recipe.suggestedArchetypes.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(recipe.suggestedArchetypes.prefix(3)) { archetype in
                            ArchetypeBadge(archetype: archetype)
                        }
                    }
                }

                // Time and servings
                HStack(spacing: 12) {
                    if let time = recipe.formattedTotalTime {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.caption2)
                            Text(time)
                                .font(.caption)
                        }
                    }

                    HStack(spacing: 4) {
                        Image(systemName: "person.2")
                            .font(.caption2)
                        Text("\(recipe.servings) servings")
                            .font(.caption)
                    }
                }
                .foregroundColor(.appTextSecondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.appTextSecondary)
        }
        .padding(12)
        .background(Color.systemBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Shared Image View

    @ViewBuilder
    private var recipeImage: some View {
        #if canImport(UIKit)
        if let imageData = recipe.imageData,
           let uiImage = UIImage(data: imageData) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            recipeImagePlaceholder
        }
        #elseif canImport(AppKit)
        if let imageData = recipe.imageData,
           let nsImage = NSImage(data: imageData) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            recipeImagePlaceholder
        }
        #endif
    }

    private var recipeImagePlaceholder: some View {
        ZStack {
            Color.appPrimary.opacity(0.1)
            Image(systemName: "fork.knife")
                .font(.title)
                .foregroundColor(.appPrimary.opacity(0.5))
        }
    }
}

// Note: DraggableRecipeCard is defined in Planning/DraggableRecipeCard.swift

// MARK: - Preview

private struct RecipeCardGridPreview: View {
    @State private var recipe: Recipe?

    var body: some View {
        Group {
            if let recipe = recipe {
                RecipeCardView(recipe: recipe, style: .grid)
                    .frame(width: 180)
                    .padding()
            } else {
                ProgressView("Loading...")
            }
        }
        .task {
            recipe = Recipe(
                title: "Chicken Stir Fry with Vegetables",
                summary: "A quick and healthy stir fry",
                servings: 4,
                prepTimeMinutes: 15,
                cookTimeMinutes: 20,
                suggestedArchetypes: [.quickWeeknight, .familyFavorite],
                isFavorite: true
            )
        }
    }
}

private struct RecipeCardListPreview: View {
    @State private var recipe: Recipe?

    var body: some View {
        Group {
            if let recipe = recipe {
                RecipeCardView(recipe: recipe, style: .list)
                    .padding()
            } else {
                ProgressView("Loading...")
            }
        }
        .task {
            recipe = Recipe(
                title: "Spaghetti Carbonara",
                summary: "Classic Italian pasta dish",
                servings: 4,
                prepTimeMinutes: 10,
                cookTimeMinutes: 20,
                suggestedArchetypes: [.comfort, .quickWeeknight],
                isFavorite: false
            )
        }
    }
}

#Preview("Grid Style") {
    RecipeCardGridPreview()
        .modelContainer(for: Recipe.self, inMemory: true)
}

#Preview("List Style") {
    RecipeCardListPreview()
        .modelContainer(for: Recipe.self, inMemory: true)
}
