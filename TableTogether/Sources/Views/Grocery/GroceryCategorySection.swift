import SwiftUI

/// A collapsible section displaying grocery items grouped by ingredient category
/// Automatically collapses when all items in the category are checked
struct GroceryCategorySection: View {
    let category: IngredientCategory
    let items: [GroceryItem]
    var mode: GroceryRowMode = .shopping
    var displayQuantities: [UUID: Double] = [:]
    let onToggleItem: (GroceryItem) -> Void
    let onDeleteItem: (GroceryItem) -> Void

    @State private var isExpanded = true

    /// Check if all items in this category are toggled (checked or in-pantry depending on mode)
    private var allItemsToggled: Bool {
        switch mode {
        case .pantryCheck: return items.allSatisfy { $0.isInPantry }
        case .shopping: return items.allSatisfy { $0.isChecked }
        }
    }

    /// Sorted items - untoggled items first, then by name
    private var sortedItems: [GroceryItem] {
        items.sorted { item1, item2 in
            let toggled1 = mode == .pantryCheck ? item1.isInPantry : item1.isChecked
            let toggled2 = mode == .pantryCheck ? item2.isInPantry : item2.isChecked
            if toggled1 != toggled2 {
                return !toggled1
            }
            let name1 = item1.ingredient?.name ?? item1.customName ?? ""
            let name2 = item2.ingredient?.name ?? item2.customName ?? ""
            return name1.localizedCaseInsensitiveCompare(name2) == .orderedAscending
        }
    }

    var body: some View {
        Section {
            if isExpanded {
                ForEach(sortedItems) { item in
                    GroceryItemRow(
                        item: item,
                        displayQuantity: displayQuantities[item.id],
                        mode: mode,
                        onToggle: { onToggleItem(item) },
                        onDelete: { onDeleteItem(item) }
                    )
                }
            }
        } header: {
            categoryHeader
        }
        .onChange(of: allItemsToggled) { _, allToggled in
            // Auto-collapse when all items are toggled
            if allToggled {
                withAnimation {
                    isExpanded = false
                }
            }
        }
    }

    // MARK: - Category Header

    private var categoryHeader: some View {
        Button {
            withAnimation {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 8) {
                // Category icon
                Image(systemName: category.iconName)
                    .font(.body)
                    .foregroundStyle(category.color)
                    .frame(width: 24, height: 24)

                // Category name
                Text(category.displayName)
                    .font(.headline)
                    .foregroundStyle(.primary)

                // Item count badge
                Text("\(items.count)")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15))
                    .clipShape(Capsule())

                Spacer()

                // Completion indicator
                if allItemsToggled {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(mode == .pantryCheck ? .orange : .green)
                }

                // Expand/collapse chevron
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// Note: IngredientCategory extensions are defined in:
// - Enums.swift (displayName, iconName, sortOrder)
// - Color+Extensions.swift (color)

// MARK: - Preview

#Preview {
    List {
        GroceryCategorySection(
            category: .produce,
            items: [],
            onToggleItem: { _ in },
            onDeleteItem: { _ in }
        )
    }
    #if os(iOS)
    .listStyle(.insetGrouped)
    #endif
}
