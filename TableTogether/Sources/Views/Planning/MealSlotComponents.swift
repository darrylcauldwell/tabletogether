import SwiftUI
import CoreData

// MARK: - MealTypeIndicator

struct MealTypeIndicator: View {
    let mealType: MealType
    let isCompact: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: mealType.icon)
                .font(isCompact ? .caption : .system(size: 9))

            Text(mealType.displayName)
                .font(isCompact ? .caption : .system(size: 9))
        }
        .foregroundColor(.secondary)
    }
}

// Note: ArchetypeBadge component using ArchetypeType is defined in Components.swift
// For MealArchetype objects, use ArchetypeBadge(archetype: mealArchetype.systemType!)

/// Badge for showing MealArchetype model with color from its colorHex
struct MealArchetypeBadge: View {
    let archetype: MealArchetype
    let isCompact: Bool

    private var archetypeColor: Color {
        if let systemType = archetype.systemType {
            return systemType.color
        }
        return Color(hex: archetype.colorHex)
    }

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: archetype.icon)
                .font(.caption2)

            if isCompact {
                Text(archetype.name)
                    .font(.caption2)
                    .lineLimit(1)
            }
        }
        .foregroundColor(archetypeColor)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(archetypeColor.opacity(0.15))
        .clipShape(Capsule())
    }
}

// MARK: - RecentEditBadge

/// Badge showing that another household member recently edited this slot
struct RecentEditBadge: View {
    let userName: String
    let isCompact: Bool

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "pencil.circle.fill")
                .font(.caption2)

            if isCompact {
                Text(userName)
                    .font(.caption2)
                    .lineLimit(1)
            }
        }
        .foregroundColor(.orange)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.orange.opacity(0.15))
        .clipShape(Capsule())
        .help("Recently edited by \(userName)")
    }
}

// MARK: - SlotContentView

/// Main content area of the meal slot
struct SlotContentView: View {
    let slot: MealSlot
    let isCompact: Bool
    let isTargeted: Bool
    let onTapped: () -> Void

    /// Resolved display names for the slot, drawn from MealSlotComponents
    /// when present (the new path from #45) or from the legacy recipes
    /// relationship as a fallback. Empty if the slot has neither.
    private var resolvedNames: [String] {
        let stored = slot.storedComponents
        if !stored.isEmpty {
            return stored.map(\.displayName)
        }
        return slot.recipesArray.map(\.title)
    }

    /// Recipe used for the thumbnail image — prefers the first stored
    /// component's recipe if any, otherwise the first legacy recipe.
    private var thumbnailRecipe: Recipe? {
        if let firstStoredRecipe = slot.storedComponents.compactMap(\.recipe).first {
            return firstStoredRecipe
        }
        return slot.recipesArray.first
    }

    /// Total cook+prep time across all recipe components, in minutes.
    /// Ingredients and foodItems don't have times, so they're skipped.
    private var totalTimeMinutes: Int? {
        let stored = slot.storedComponents
        let recipes: [Recipe]
        if !stored.isEmpty {
            recipes = stored.compactMap(\.recipe)
        } else {
            recipes = slot.recipesArray
        }
        let total = recipes.compactMap(\.totalTimeMinutes).reduce(0, +)
        return total > 0 ? total : nil
    }

    var body: some View {
        Group {
            let names = resolvedNames
            if !names.isEmpty {
                // Show recipe card(s) with multi-component layout
                RecipeSlotCard(
                    primaryName: names[0],
                    secondaryNames: Array(names.dropFirst()),
                    thumbnailRecipe: thumbnailRecipe,
                    totalTimeMinutes: totalTimeMinutes,
                    servings: Int(slot.servingsPlanned),
                    isCompact: isCompact
                )
            } else if let customName = slot.customMealName, !customName.isEmpty {
                // Show custom meal name
                CustomMealCard(name: customName, isCompact: isCompact)
            } else {
                // Show empty placeholder
                DropTargetPlaceholder(isTargeted: isTargeted, isCompact: isCompact)
            }
        }
    }
}

// MARK: - RecipeSlotCard

/// Compact recipe card shown in a meal slot. Supports multi-component meals
/// (a primary recipe plus optional sides/branded foods) by showing the primary
/// name on its own line and a dim secondary line listing the additional
/// components when there are any. With a single component the secondary line
/// is hidden — the layout collapses gracefully back to today's appearance.
struct RecipeSlotCard: View {
    let primaryName: String
    let secondaryNames: [String]
    let thumbnailRecipe: Recipe?
    let totalTimeMinutes: Int?
    let servings: Int
    let isCompact: Bool

    /// Inline summary of additional components, e.g. "+ Rice + Naan + Raita".
    /// When there are 4+ extras, truncates to "+ Rice, Naan, +N more".
    private var secondaryLine: String {
        guard !secondaryNames.isEmpty else { return "" }
        if secondaryNames.count <= 3 {
            return "+ " + secondaryNames.joined(separator: " + ")
        }
        let firstTwo = secondaryNames.prefix(2).joined(separator: ", ")
        let rest = secondaryNames.count - 2
        return "+ \(firstTwo), +\(rest) more"
    }

    var body: some View {
        HStack(spacing: isCompact ? 8 : 0) {
            // Recipe thumbnail — only show on iPhone (compact) to save space on iPad grid
            if isCompact {
                if let recipe = thumbnailRecipe {
                    RecipeImageView(imageData: recipe.imageData, imageURL: recipe.imageURL)
                        .frame(width: 50, height: 50)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    RecipePlaceholderImage(size: 50)
                }
            }

            VStack(alignment: .leading, spacing: isCompact ? 2 : 1) {
                // Primary line — first component
                Text(primaryName)
                    .font(isCompact ? .subheadline : .caption2)
                    .fontWeight(.medium)
                    .lineLimit(isCompact ? 2 : 1)

                // Secondary line — additional components, dimmed
                if !secondaryNames.isEmpty {
                    Text(secondaryLine)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                if isCompact {
                    HStack(spacing: 8) {
                        if let totalTime = totalTimeMinutes {
                            Label("\(totalTime) min", systemImage: "clock")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                        Text("\(servings) servings")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}

// MARK: - RecipePlaceholderImage

struct RecipePlaceholderImage: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.systemGray5)

            Image(systemName: "fork.knife")
                .font(.system(size: size * 0.4))
                .foregroundColor(.secondary)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - CustomMealCard

struct CustomMealCard: View {
    let name: String
    let isCompact: Bool

    var body: some View {
        HStack(spacing: isCompact ? 8 : 4) {
            if isCompact {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.systemGray5)

                    Image(systemName: "pencil")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(width: 50, height: 50)
            } else {
                Image(systemName: "pencil")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }

            Text(name)
                .font(isCompact ? .subheadline : .caption2)
                .foregroundColor(.primary)
                .lineLimit(isCompact ? 2 : 2)

            Spacer(minLength: 0)
        }
    }
}

// MARK: - DropTargetPlaceholder
// Note: EmptySlotPlaceholder for tap interactions is in Components.swift

struct DropTargetPlaceholder: View {
    let isTargeted: Bool
    let isCompact: Bool

    var body: some View {
        HStack(spacing: 4) {
            Spacer(minLength: 0)

            if isCompact {
                VStack(spacing: 4) {
                    Image(systemName: isTargeted ? "plus.circle.fill" : "plus.circle")
                        .font(.title3)
                        .foregroundColor(isTargeted ? .accentColor : .secondary)

                    Text(isTargeted ? "Drop recipe here" : "Add meal")
                        .font(.caption)
                        .foregroundColor(isTargeted ? .accentColor : .secondary)
                }
            } else {
                // iPad: was 9pt system text — barely readable. Bumped to .caption
                // (~12pt) and .body icon, plus a soft sage-tinted background to
                // give the empty slot visual weight without shouting.
                Image(systemName: isTargeted ? "plus.circle.fill" : "plus.circle")
                    .font(.body)
                    .foregroundColor(isTargeted ? .accentColor : .secondary)

                Text(isTargeted ? "Drop here" : "Add meal")
                    .font(.caption)
                    .foregroundColor(isTargeted ? .accentColor : .secondary)
            }

            Spacer(minLength: 0)
        }
        .frame(minHeight: isCompact ? 50 : 32)
        .background(
            isCompact
                ? Color.clear
                : Theme.Colors.primary.opacity(isTargeted ? 0.10 : 0.04)
        )
    }
}

// MARK: - AssignedUsersRow

/// Row showing avatars of assigned users
struct AssignedUsersRow: View {
    let users: [User]
    let isCompact: Bool

    var body: some View {
        HStack(spacing: -6) {
            ForEach(users.prefix(4)) { user in
                UserAvatarView(user: user, size: isCompact ? 24 : 18)
            }

            if users.count > 4 {
                Text("+\(users.count - 4)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.leading, 8)
            }
        }
        .padding(.top, 4)
    }
}

// MARK: - UserAvatarView

struct UserAvatarView: View {
    let user: User
    let size: CGFloat

    private var backgroundColor: Color {
        Color(hex: user.avatarColorHex)
    }

    /// Computed initials from user's display name
    private var initials: String {
        let components = user.displayName.trimmingCharacters(in: .whitespaces).split(separator: " ")
        if components.isEmpty {
            return "?"
        } else if components.count == 1 {
            return String(components[0].prefix(1)).uppercased()
        } else {
            let first = String(components[0].prefix(1))
            let last = String(components[components.count - 1].prefix(1))
            return (first + last).uppercased()
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(backgroundColor)

            if user.avatarEmoji.isEmpty {
                Text(initials)
                    .font(.system(size: size * 0.4, weight: .medium, design: .rounded))
                    .foregroundColor(.white)
            } else {
                Text(user.avatarEmoji)
                    .font(.system(size: size * 0.6))
            }
        }
        .frame(width: size, height: size)
        .overlay(
            Circle()
                .strokeBorder(Color.systemBackground, lineWidth: 1)
        )
    }
}

// MARK: - RecipePickerSheet

/// Sheet for picking a recipe to assign to a slot. A single inline
/// text field at the top of the list filters the recipe list as the
/// user types. If nothing matches, a "Use '<text>' as custom meal"
/// fallback row appears above the (now-empty) recipe list so there's
/// always a useful next action.
///
/// Previously used two separate inputs (a custom-meal TextField plus a
/// .searchable modifier in the navigation area), which was confusing —
/// typing in the top field didn't filter, and the nav-area search field
/// was easy to miss on Mac Catalyst. A single obvious inline TextField
/// is what muscle memory expects.
struct RecipePickerSheet: View {
    @ObservedObject var slot: MealSlot
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @FetchRequest(sortDescriptors: [SortDescriptor(\.title)]) private var recipes: FetchedResults<Recipe>
    @State private var searchText: String = ""
    @FocusState private var searchFocused: Bool

    private var trimmedQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredRecipes: [Recipe] {
        if trimmedQuery.isEmpty {
            return Array(recipes)
        }
        return recipes.filter { $0.title.localizedCaseInsensitiveContains(trimmedQuery) }
    }

    /// Show the "use as custom meal" fallback only when the user has typed
    /// something that doesn't match any recipe title — so there's always
    /// one useful thing to do with their input.
    private var showCustomMealFallback: Bool {
        !trimmedQuery.isEmpty && filteredRecipes.isEmpty
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(Theme.Colors.textSecondary)
                        TextField("Search recipes or type a custom meal name", text: $searchText)
                            #if os(iOS)
                            .textInputAutocapitalization(.sentences)
                            .autocorrectionDisabled(false)
                            #endif
                            .focused($searchFocused)
                            .submitLabel(.search)
                        if !searchText.isEmpty {
                            Button {
                                searchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(Theme.Colors.textSecondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if showCustomMealFallback {
                    Section {
                        Button {
                            slot.customMealName = trimmedQuery
                            slot.modifiedAt = Date()
                            viewContext.saveWithLogging(context: "custom meal name")
                            dismiss()
                        } label: {
                            HStack {
                                Image(systemName: "pencil.circle.fill")
                                    .foregroundStyle(Theme.Colors.primary)
                                Text("Use \"\(trimmedQuery)\" as custom meal")
                                    .foregroundStyle(.primary)
                                Spacer()
                            }
                        }
                    } footer: {
                        Text("No matching recipes — save as a one-off meal name.")
                    }
                }

                Section("Recipes") {
                    if filteredRecipes.isEmpty && trimmedQuery.isEmpty {
                        Text("No recipes yet — add some from the Recipes tab.")
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .font(.subheadline)
                    } else {
                        ForEach(filteredRecipes) { recipe in
                            Button {
                                slot.addToRecipes(recipe)
                                slot.modifiedAt = Date()
                                viewContext.saveWithLogging(context: "recipe selection")
                                dismiss()
                            } label: {
                                RecipeRowView(recipe: recipe)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add Meal")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                // Auto-focus so the user can start typing immediately
                // without needing to click into the search field first.
                searchFocused = true
            }
        }
    }
}

// MARK: - RecipeRowView

struct RecipeRowView: View {
    let recipe: Recipe

    var body: some View {
        HStack(spacing: 12) {
            RecipeImageView(imageData: recipe.imageData, imageURL: recipe.imageURL)
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                Text(recipe.title)
                    .font(.body)
                    .foregroundColor(.primary)

                if let totalTime = recipe.totalTimeMinutes {
                    Text("\(totalTime) min")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if recipe.isFavorite {
                Image(systemName: "heart.fill")
                    .foregroundColor(.red)
                    .font(.caption)
            }
        }
    }
}

// Note: Color(hex:) initializer is defined in Theme.swift
