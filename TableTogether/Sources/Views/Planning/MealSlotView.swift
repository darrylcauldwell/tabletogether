import SwiftUI
import SwiftData

// MARK: - MealSlotView

/// Individual meal slot showing archetype badge, recipe card, and assigned users.
/// Supports drop destination for drag and drop recipe assignment.
struct MealSlotView: View {
    @Bindable var slot: MealSlot
    let isCompact: Bool
    let onTapped: () -> Void
    let onRecipeDropped: (String) -> Void  // Receives recipe UUID string
    var currentUser: User? = nil

    @State private var isTargeted: Bool = false
    @State private var showingRecipePicker: Bool = false
    @State private var showingSlotEditor: Bool = false

    /// Whether this slot was recently modified by another user
    private var wasRecentlyModifiedByOther: Bool {
        guard let modifier = slot.modifiedBy,
              let current = currentUser,
              modifier.id != current.id else {
            return false
        }
        // Within last hour
        return Date().timeIntervalSince(slot.modifiedAt) < 3600
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Meal type indicator with archetype badge
            HStack(spacing: 4) {
                MealTypeIndicator(mealType: slot.mealType, isCompact: isCompact)

                if let archetype = slot.archetype {
                    MealArchetypeBadge(archetype: archetype, isCompact: isCompact)
                }

                Spacer()

                // Recent edit indicator
                if wasRecentlyModifiedByOther, let modifier = slot.modifiedBy {
                    RecentEditBadge(userName: modifier.displayName, isCompact: isCompact)
                }
            }

            // Main content area
            SlotContentView(
                slot: slot,
                isCompact: isCompact,
                isTargeted: isTargeted,
                onTapped: onTapped
            )

            // Assigned users row
            if !slot.assignedTo.isEmpty {
                AssignedUsersRow(users: slot.assignedTo, isCompact: isCompact)
            }
        }
        .padding(isCompact ? 12 : 8)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: isCompact ? 12 : 8))
        .overlay(
            RoundedRectangle(cornerRadius: isCompact ? 12 : 8)
                .strokeBorder(slotBorderColor, lineWidth: isTargeted ? 2 : (hasContent && !isCompact ? 0.5 : 0))
        )
        .shadow(color: isTargeted ? Color.accentColor.opacity(0.3) : (hasContent && !isCompact ? Color.black.opacity(0.08) : Color.black.opacity(0.03)), radius: isTargeted ? 8 : (hasContent && !isCompact ? 3 : 1))
        #if os(iOS)
        .dropDestination(for: String.self) { recipeIds, _ in
            guard let recipeId = recipeIds.first else { return false }
            onRecipeDropped(recipeId)
            return true
        } isTargeted: { targeted in
            withAnimation(.easeInOut(duration: 0.2)) {
                isTargeted = targeted
            }
        }
        #endif
        .onTapGesture {
            if slot.recipes.isEmpty && slot.customMealName == nil {
                showingRecipePicker = true
            } else {
                showingSlotEditor = true
            }
        }
        .sheet(isPresented: $showingRecipePicker) {
            RecipePickerSheet(slot: slot)
        }
        .sheet(isPresented: $showingSlotEditor) {
            MealSlotEditorSheet(slot: slot)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(slotAccessibilityLabel)
        .accessibilityHint(slotAccessibilityHint)
    }

    private var slotAccessibilityLabel: String {
        var parts: [String] = []
        parts.append("\(slot.mealType.displayName) on \(slot.dayOfWeek.displayName)")

        if !slot.recipes.isEmpty {
            parts.append(slot.recipes.map(\.title).joined(separator: " and "))
        } else if let customName = slot.customMealName {
            parts.append(customName)
        } else {
            parts.append("No meal planned")
        }

        if let archetype = slot.archetype {
            parts.append(archetype.name)
        }

        if !slot.assignedTo.isEmpty {
            let names = slot.assignedTo.prefix(3).map { $0.displayName }.joined(separator: ", ")
            parts.append("Assigned to \(names)")
        }

        return parts.joined(separator: ". ")
    }

    private var slotAccessibilityHint: String {
        if slot.recipes.isEmpty && slot.customMealName == nil {
            return "Double tap to add a meal"
        }
        return "Double tap to edit"
    }

    private var hasContent: Bool {
        !slot.recipes.isEmpty || slot.customMealName != nil
    }

    private var slotBorderColor: Color {
        if isTargeted {
            return Color.accentColor
        } else if hasContent && !isCompact {
            return Color.secondary.opacity(0.2)
        } else {
            return Color.clear
        }
    }

    private var backgroundColor: Color {
        if isTargeted {
            return Color.accentColor.opacity(0.1)
        } else if hasContent {
            return Color.systemBackground
        } else {
            return Color.systemGray6
        }
    }
}

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

    var body: some View {
        Group {
            if !slot.recipes.isEmpty {
                // Show recipe card(s)
                RecipeSlotCard(recipes: slot.recipes, servings: slot.servingsPlanned, isCompact: isCompact)
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

/// Compact recipe card shown in a meal slot, supports multiple recipes
struct RecipeSlotCard: View {
    let recipes: [Recipe]
    let servings: Int
    let isCompact: Bool

    private var firstRecipe: Recipe? { recipes.first }

    var body: some View {
        HStack(spacing: isCompact ? 8 : 0) {
            // Recipe thumbnail — only show on iPhone (compact) to save space on iPad grid
            if isCompact {
                if let recipe = firstRecipe {
                    #if canImport(UIKit)
                    if let imageData = recipe.imageData, let uiImage = UIImage(data: imageData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 50, height: 50)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    } else {
                        RecipePlaceholderImage(size: 50)
                    }
                    #elseif canImport(AppKit)
                    if let imageData = recipe.imageData, let nsImage = NSImage(data: imageData) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 50, height: 50)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    } else {
                        RecipePlaceholderImage(size: 50)
                    }
                    #endif
                } else {
                    RecipePlaceholderImage(size: 50)
                }
            }

            VStack(alignment: .leading, spacing: isCompact ? 2 : 1) {
                if isCompact {
                    // iPhone: join recipe names on one line
                    Text(recipes.map(\.title).joined(separator: " & "))
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(2)
                } else {
                    // iPad: show each recipe on its own line for readability
                    ForEach(recipes) { recipe in
                        Text(recipe.title)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .lineLimit(1)
                    }
                }

                if isCompact {
                    HStack(spacing: 8) {
                        if let totalTime = recipes.compactMap(\.totalTimeMinutes).reduce(nil, { ($0 ?? 0) + $1 }) {
                            Label("\(totalTime) min", systemImage: "clock")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                        Text("\(servings) servings")
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        if recipes.count > 1 {
                            Text("\(recipes.count) recipes")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
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
                Image(systemName: isTargeted ? "plus.circle.fill" : "plus.circle")
                    .font(.system(size: 11))
                    .foregroundColor(isTargeted ? .accentColor : .secondary)

                Text(isTargeted ? "Drop here" : "Add meal")
                    .font(.system(size: 9))
                    .foregroundColor(isTargeted ? .accentColor : .secondary)
            }

            Spacer(minLength: 0)
        }
        .frame(minHeight: isCompact ? 50 : 20)
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

/// Sheet for picking a recipe to assign to a slot
struct RecipePickerSheet: View {
    @Bindable var slot: MealSlot
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Recipe.title) private var recipes: [Recipe]
    @State private var searchText: String = ""
    @State private var customMealName: String = ""

    private var filteredRecipes: [Recipe] {
        if searchText.isEmpty {
            return recipes
        }
        return recipes.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Or enter custom meal name", text: $customMealName)
                        .onSubmit {
                            if !customMealName.isEmpty {
                                slot.customMealName = customMealName
                                slot.modifiedAt = Date()
                                modelContext.saveWithLogging(context: "custom meal name")
                                dismiss()
                            }
                        }
                }

                Section("Recipes") {
                    ForEach(filteredRecipes) { recipe in
                        Button {
                            slot.recipes.append(recipe)
                            slot.modifiedAt = Date()
                            modelContext.saveWithLogging(context: "recipe selection")
                            dismiss()
                        } label: {
                            RecipeRowView(recipe: recipe)
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search recipes")
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
        }
    }
}

// MARK: - RecipeRowView

struct RecipeRowView: View {
    let recipe: Recipe

    var body: some View {
        HStack(spacing: 12) {
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

// MARK: - Preview

private struct MealSlotViewPreview: View {
    @State private var slot: MealSlot?

    var body: some View {
        Group {
            if let slot = slot {
                VStack(spacing: 16) {
                    MealSlotView(
                        slot: slot,
                        isCompact: true,
                        onTapped: {},
                        onRecipeDropped: { _ in }
                    )
                    .frame(maxWidth: 300)

                    MealSlotView(
                        slot: slot,
                        isCompact: false,
                        onTapped: {},
                        onRecipeDropped: { _ in }
                    )
                    .frame(maxWidth: 150)
                }
                .padding()
            } else {
                ProgressView("Loading...")
            }
        }
        .task {
            slot = MealSlot(
                dayOfWeek: .monday,
                mealType: .dinner,
                servingsPlanned: 4
            )
        }
    }
}

#Preview {
    MealSlotViewPreview()
        .modelContainer(for: [MealSlot.self, WeekPlan.self, Recipe.self, User.self, MealArchetype.self], inMemory: true)
}
