import SwiftUI
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

// MARK: - DraggableRecipeCard

/// Compact recipe card that can be dragged to meal slots.
/// Shows recipe thumbnail, title, and relevant metadata.
struct DraggableRecipeCard: View {
    let recipe: Recipe
    var isNew: Bool = false

    @State private var isDragging: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Recipe thumbnail with optional "new" badge
            ZStack(alignment: .topTrailing) {
                RecipeThumbnail(imageData: recipe.imageData)

                if isNew {
                    NewBadge()
                }
            }

            // Recipe title
            Text(recipe.title)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .foregroundColor(.primary)

            // Metadata row
            RecipeMetadataRow(recipe: recipe)
        }
        .frame(width: 120)
        .padding(8)
        .background(Theme.Colors.background)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: Color.black.opacity(isDragging ? 0.2 : 0.1), radius: isDragging ? 8 : 4)
        .scaleEffect(isDragging ? 1.05 : 1.0)
        #if os(iOS)
        .draggable(recipe.id.uuidString) {
            // Drag preview
            DragPreviewCard(recipe: recipe)
                .onAppear {
                    isDragging = true
                }
        }
        .onDrop(of: [.text], isTargeted: nil) { _ in
            isDragging = false
            return false
        }
        #endif
    }
}

// MARK: - RecipeThumbnail

struct RecipeThumbnail: View {
    let imageData: Data?

    var body: some View {
        Group {
            #if canImport(UIKit)
            if let imageData = imageData, let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                placeholderView
            }
            #else
            placeholderView
            #endif
        }
        .frame(width: 104, height: 70)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var placeholderView: some View {
        ZStack {
            Color.gray.opacity(0.15)

            Image(systemName: "fork.knife")
                .font(.title2)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - NewBadge

struct NewBadge: View {
    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "sparkles")
                .font(.system(size: 8))

            Text("NEW")
                .font(.system(size: 8, weight: .bold))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color.orange)
        .clipShape(Capsule())
        .offset(x: -4, y: 4)
    }
}

// MARK: - RecipeMetadataRow

struct RecipeMetadataRow: View {
    let recipe: Recipe

    var body: some View {
        HStack(spacing: 4) {
            if let totalTime = recipe.totalTimeMinutes {
                HStack(spacing: 2) {
                    Image(systemName: "clock")
                        .font(.system(size: 9))

                    Text("\(totalTime)m")
                        .font(.system(size: 10))
                }
                .foregroundColor(.secondary)
            }

            Spacer()

            if recipe.isFavorite {
                Image(systemName: "heart.fill")
                    .font(.system(size: 9))
                    .foregroundColor(.red)
            }
        }
    }
}

// MARK: - DragPreviewCard

/// Preview card shown while dragging
struct DragPreviewCard: View {
    let recipe: Recipe

    var body: some View {
        HStack(spacing: 8) {
            // Thumbnail
            dragPreviewThumbnail

            // Title
            VStack(alignment: .leading, spacing: 2) {
                Text(recipe.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)

                if let totalTime = recipe.totalTimeMinutes {
                    Text("\(totalTime) min")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .padding(8)
        .frame(width: 180)
        .background(Theme.Colors.background)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: Color.black.opacity(0.2), radius: 8)
        .opacity(0.9)
    }

    @ViewBuilder
    private var dragPreviewThumbnail: some View {
        #if canImport(UIKit)
        if let imageData = recipe.imageData, let uiImage = UIImage(data: imageData) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 50, height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            thumbnailPlaceholder
        }
        #else
        thumbnailPlaceholder
        #endif
    }

    private var thumbnailPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.gray.opacity(0.15))

            Image(systemName: "fork.knife")
                .foregroundColor(.secondary)
        }
        .frame(width: 50, height: 50)
    }
}

// Note: Recipe Transferable conformance and UTType extension are defined in Recipe.swift

// MARK: - Preview

#Preview("Single Card") {
    let recipe = Recipe(
        title: "Chicken Stir Fry with Vegetables",
        summary: "A quick and healthy dinner",
        servings: 4,
        prepTimeMinutes: 15,
        cookTimeMinutes: 20,
        instructions: ["Step 1", "Step 2"],
        tags: ["quick", "healthy"],
        suggestedArchetypes: [.quickWeeknight],
        isFavorite: true,
        timesCooked: 5,
        lastCookedDate: Date()
    )

    DraggableRecipeCard(recipe: recipe)
        .padding()
        .background(Color.gray.opacity(0.1))
}

#Preview("New Recipe Card") {
    let recipe = Recipe(
        title: "Thai Basil Chicken",
        summary: "An authentic Thai recipe",
        servings: 2,
        prepTimeMinutes: 10,
        cookTimeMinutes: 15,
        instructions: ["Step 1", "Step 2"],
        tags: ["thai", "spicy"],
        suggestedArchetypes: [.newExperimental]
    )

    DraggableRecipeCard(recipe: recipe, isNew: true)
        .padding()
        .background(Color.gray.opacity(0.1))
}

#Preview("Row of Cards") {
    ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 12) {
            ForEach(0..<5) { index in
                let recipe = Recipe(
                    title: "Recipe \(index + 1)",
                    servings: 4,
                    prepTimeMinutes: 10 + index * 5,
                    cookTimeMinutes: 20 + index * 5,
                    isFavorite: index == 0,
                    timesCooked: index * 2
                )
                DraggableRecipeCard(recipe: recipe, isNew: index == 4)
            }
        }
        .padding()
    }
    .background(Color.gray.opacity(0.1))
}
