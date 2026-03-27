import SwiftUI
import SwiftData

// MARK: - Generator Section

struct GeneratorSection<Content: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder let content: () -> Content

    init(title: String, subtitle: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Ingredient Chip

struct IngredientChip: View {
    let name: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(name.capitalized)
                .font(.subheadline)
                .foregroundStyle(Theme.Colors.textPrimary)

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.Colors.primary.opacity(0.15))
        .clipShape(Capsule())
    }
}

// MARK: - Style Selection Card

struct StyleSelectionCard: View {
    let title: String
    let description: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: Theme.Spacing.sm) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(isSelected ? Theme.Colors.primary : Theme.Colors.textSecondary)

                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(Theme.Colors.textPrimary)

                Text(description)
                    .font(.caption2)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(isSelected ? Theme.Colors.primary.opacity(0.1) : Color.systemGray6)
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.standard))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.standard)
                    .stroke(isSelected ? Theme.Colors.primary : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Time Selection Chip

struct TimeSelectionChip: View {
    let time: TimeAvailability
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: time.iconName)
                    .font(.title3)

                Text(time.displayName)
                    .font(.caption)
                    .fontWeight(.medium)

                Text(time.description)
                    .font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.md)
            .background(isSelected ? Theme.Colors.primary.opacity(0.15) : Color.systemGray6)
            .foregroundStyle(isSelected ? Theme.Colors.primary : Theme.Colors.textSecondary)
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                    .stroke(isSelected ? Theme.Colors.primary : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Cuisine Selection Chip

struct CuisineSelectionChip: View {
    let cuisine: CuisineType
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: cuisine.iconName)
                    .font(.caption)
                Text(cuisine.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(isSelected ? Color(hex: cuisine.colorHex).opacity(0.2) : Color.systemGray6)
            .foregroundStyle(isSelected ? Color(hex: cuisine.colorHex) : Theme.Colors.textSecondary)
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                    .stroke(isSelected ? Color(hex: cuisine.colorHex) : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Dietary Chip

struct DietaryChip: View {
    let preference: DietaryPreference
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: preference.iconName)
                    .font(.caption)
                Text(preference.displayName)
                    .font(.caption)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? Theme.Colors.primary.opacity(0.15) : Color.systemGray6)
            .foregroundStyle(isSelected ? Theme.Colors.primary : Theme.Colors.textSecondary)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(isSelected ? Theme.Colors.primary : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Generated Recipe Results View

struct GeneratedRecipeResultsView: View {
    let recipes: [GeneratedRecipe]
    let onSave: (GeneratedRecipe) -> Void
    let onRegenerate: () -> Void
    let onDismiss: () -> Void

    @State private var selectedRecipeIndex = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Recipe selector if multiple
                if recipes.count > 1 {
                    Picker("Recipe", selection: $selectedRecipeIndex) {
                        ForEach(Array(recipes.enumerated()), id: \.offset) { index, recipe in
                            Text("Option \(index + 1)").tag(index)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding()
                }

                // Recipe preview
                if selectedRecipeIndex < recipes.count {
                    GeneratedRecipePreview(recipe: recipes[selectedRecipeIndex])
                }

                Spacer()

                // Action buttons
                VStack(spacing: Theme.Spacing.sm) {
                    Button {
                        if selectedRecipeIndex < recipes.count {
                            onSave(recipes[selectedRecipeIndex])
                        }
                    } label: {
                        Label("Save to My Recipes", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Theme.Colors.primary)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
                    }

                    Button {
                        onRegenerate()
                    } label: {
                        Label("Generate Again", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.systemGray6)
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
                    }
                }
                .padding()
            }
            .navigationTitle("Your Recipe")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onDismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Generated Recipe Preview

struct GeneratedRecipePreview: View {
    let recipe: GeneratedRecipe

    @State private var expandedSections: Set<String> = ["ingredients", "instructions"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                // Header
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    HStack {
                        Text(recipe.title)
                            .font(Theme.Typography.title2)
                            .foregroundStyle(Theme.Colors.textPrimary)

                        Spacer()

                        // Cooking style badge
                        HStack(spacing: 4) {
                            Image(systemName: recipe.cookingStyle.iconName)
                            Text(recipe.cookingStyle.displayName)
                        }
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Theme.Colors.secondary.opacity(0.2))
                        .foregroundStyle(Theme.Colors.secondary)
                        .clipShape(Capsule())
                    }

                    Text(recipe.summary)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }

                // Quick info row
                HStack(spacing: Theme.Spacing.lg) {
                    QuickInfoItem(icon: "clock", value: recipe.formattedTotalTime)
                    QuickInfoItem(icon: "person.2", value: "\(recipe.servings) servings")
                    if let cuisine = recipe.cuisineType {
                        QuickInfoItem(icon: cuisine.iconName, value: cuisine.displayName)
                    }
                }
                .padding()
                .background(Color.systemGray6)
                .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))

                // Archetypes
                if !recipe.suggestedArchetypes.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(recipe.suggestedArchetypes, id: \.self) { archetype in
                            ArchetypeBadge(archetype: archetype, compact: true)
                        }
                    }
                }

                // Collapsible Ingredients Section
                CollapsibleSection(
                    title: "Ingredients",
                    icon: "basket",
                    isExpanded: expandedSections.contains("ingredients"),
                    toggle: { toggleSection("ingredients") }
                ) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(recipe.ingredients) { ingredient in
                            HStack {
                                Circle()
                                    .fill(Theme.Colors.primary)
                                    .frame(width: 6, height: 6)

                                Text(formatIngredient(ingredient))
                                    .font(Theme.Typography.body)

                                Spacer()

                                if ingredient.isOptional {
                                    Text("optional")
                                        .font(.caption)
                                        .foregroundStyle(Theme.Colors.textSecondary)
                                }
                            }
                        }
                    }
                }

                // Collapsible Instructions Section
                CollapsibleSection(
                    title: "Instructions",
                    icon: "list.number",
                    isExpanded: expandedSections.contains("instructions"),
                    toggle: { toggleSection("instructions") }
                ) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                        ForEach(Array(recipe.instructions.enumerated()), id: \.offset) { index, instruction in
                            HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                                Text("\(index + 1)")
                                    .font(.headline)
                                    .foregroundStyle(Theme.Colors.primary)
                                    .frame(width: 24)

                                Text(instruction)
                                    .font(Theme.Typography.body)
                            }
                        }
                    }
                }

                // Tags
                if !recipe.tags.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(recipe.tags, id: \.self) { tag in
                            Text("#\(tag)")
                                .font(.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                    }
                }
            }
            .padding()
        }
    }

    private func formatIngredient(_ ingredient: GeneratedRecipe.GeneratedIngredient) -> String {
        let quantityStr = ingredient.quantity == floor(ingredient.quantity)
            ? String(format: "%.0f", ingredient.quantity)
            : String(format: "%.1f", ingredient.quantity)

        var result = "\(quantityStr) \(ingredient.unit.abbreviation) \(ingredient.name)"

        if let prep = ingredient.preparationNote {
            result += ", \(prep)"
        }

        return result
    }

    private func toggleSection(_ section: String) {
        if expandedSections.contains(section) {
            expandedSections.remove(section)
        } else {
            expandedSections.insert(section)
        }
    }
}

// MARK: - Quick Info Item

struct QuickInfoItem: View {
    let icon: String
    let value: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(Theme.Colors.textPrimary)
        }
    }
}

// MARK: - Collapsible Section

struct CollapsibleSection<Content: View>: View {
    let title: String
    let icon: String
    let isExpanded: Bool
    let toggle: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Button(action: toggle) {
                HStack {
                    Image(systemName: icon)
                        .foregroundStyle(Theme.Colors.primary)
                    Text(title)
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                content()
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding()
        .background(Color.systemGray6.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.standard))
        .animation(Theme.Animation.standard, value: isExpanded)
    }
}
