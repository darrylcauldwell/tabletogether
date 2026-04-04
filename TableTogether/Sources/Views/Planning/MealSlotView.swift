import SwiftUI
import CoreData

// MARK: - MealSlotView

/// Individual meal slot showing archetype badge, recipe card, and assigned users.
/// Supports drop destination for drag and drop recipe assignment.
struct MealSlotView: View {
    var slot: MealSlot
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
            if !slot.assignedToArray.isEmpty {
                AssignedUsersRow(users: slot.assignedToArray, isCompact: isCompact)
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
            if slot.recipesArray.isEmpty && slot.customMealName == nil {
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

        if !slot.recipesArray.isEmpty {
            parts.append(slot.recipesArray.map(\.title).joined(separator: " and "))
        } else if let customName = slot.customMealName {
            parts.append(customName)
        } else {
            parts.append("No meal planned")
        }

        if let archetype = slot.archetype {
            parts.append(archetype.name)
        }

        if !slot.assignedToArray.isEmpty {
            let names = slot.assignedToArray.prefix(3).map { $0.displayName }.joined(separator: ", ")
            parts.append("Assigned to \(names)")
        }

        return parts.joined(separator: ". ")
    }

    private var slotAccessibilityHint: String {
        if slot.recipesArray.isEmpty && slot.customMealName == nil {
            return "Double tap to add a meal"
        }
        return "Double tap to edit"
    }

    private var hasContent: Bool {
        !slot.recipesArray.isEmpty || slot.customMealName != nil
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
            let context = PersistenceController.preview.viewContext
            slot = MealSlot(
                context: context,
                dayOfWeek: .monday,
                mealType: .dinner,
                servingsPlanned: 4
            )
        }
    }
}

#Preview {
    MealSlotViewPreview()
        .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
}
