import SwiftUI
import CoreData

/// Shopping list interface — shows all items still needed across all week plans.
/// Items are aggregated by ingredient so the same item from multiple weeks shows once with combined quantity.
/// Users check off items while shopping. Manual items can be added here.
struct GroceryListView: View {
    @Environment(\.managedObjectContext) private var viewContext

    @FetchRequest(sortDescriptors: [SortDescriptor(\.weekStartDate, order: .reverse)]) private var weekPlans: FetchedResults<WeekPlan>

    @State private var showingAddItem = false
    @State private var checkedItemsExpanded = false

    // MARK: - Aggregation

    /// The week plan to use as the default target for new manual grocery items.
    /// Picks the week containing today if one exists, otherwise the most
    /// recent week plan. (Previously filtered by `status == .active`, but the
    /// status concept was removed — nothing ever transitioned plans to
    /// `.active` so the filter always fell through to this same sort-by-date
    /// fallback anyway.)
    private var primaryWeekPlan: WeekPlan? {
        let calendar = Calendar.current
        if let currentWeek = weekPlans.first(where: {
            calendar.isDate(Date(), equalTo: $0.weekStartDate, toGranularity: .weekOfYear)
        }) {
            return currentWeek
        }
        return weekPlans.sorted { $0.weekStartDate > $1.weekStartDate }.first
    }

    /// Grouping key for an item — ingredient ID for recipe items, customName for manual items
    private func groupingKey(for item: GroceryItem) -> String {
        if let ingredientID = item.ingredient?.id {
            return ingredientID.uuidString
        }
        return "manual-\(item.customName ?? item.id.uuidString)"
    }

    /// Shopping items grouped by ingredient across ALL week plans
    private var shoppingItemGroups: [String: [GroceryItem]] {
        var groups: [String: [GroceryItem]] = [:]
        for plan in weekPlans {
            for item in plan.shoppingListItems {
                let key = groupingKey(for: item)
                groups[key, default: []].append(item)
            }
        }
        return groups
    }

    /// One representative item per ingredient group
    private var shoppingItems: [GroceryItem] {
        shoppingItemGroups.values.compactMap { $0.first }
    }

    /// Summed quantities keyed by representative item ID
    private var aggregatedQuantities: [UUID: Double] {
        var quantities: [UUID: Double] = [:]
        for (_, items) in shoppingItemGroups {
            if let first = items.first {
                quantities[first.id] = items.reduce(0) { $0 + $1.quantity }
            }
        }
        return quantities
    }

    /// Map from representative item ID to all items in its group
    private var itemGroupMap: [UUID: [GroceryItem]] {
        var map: [UUID: [GroceryItem]] = [:]
        for (_, items) in shoppingItemGroups {
            if let first = items.first {
                map[first.id] = items
            }
        }
        return map
    }

    /// Whether there are pantry items but no shopping items
    private var hasPantryItemsOnly: Bool {
        let pantryCount = weekPlans.reduce(0) { $0 + $1.inPantryItems.count }
        return pantryCount > 0 && shoppingItems.isEmpty
    }

    /// Items that haven't been checked off yet
    private var uncheckedItems: [GroceryItem] {
        shoppingItems.filter { !$0.isChecked }
    }

    /// Items that have been checked off
    private var checkedItems: [GroceryItem] {
        shoppingItems.filter { $0.isChecked }
    }

    /// Items grouped by ingredient category
    private var itemsByCategory: [IngredientCategory: [GroceryItem]] {
        Dictionary(grouping: uncheckedItems) { $0.category }
    }

    /// Sorted categories for consistent display order
    private var sortedCategories: [IngredientCategory] {
        IngredientCategory.allCases.filter { itemsByCategory[$0] != nil }
    }

    /// Progress calculation
    private var totalItems: Int {
        shoppingItems.count
    }

    private var completedItems: Int {
        checkedItems.count
    }

    var body: some View {
        VStack(spacing: 0) {
            // Progress header
            if totalItems > 0 {
                ShoppingProgressHeader(
                    completedItems: completedItems,
                    totalItems: totalItems
                )
            }

            if hasPantryItemsOnly {
                pantryOnlyEmptyStateView
            } else if shoppingItems.isEmpty {
                emptyStateView
            } else {
                groceryListContent
            }
        }
        .navigationTitle("Shopping List")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAddItem = true
                } label: {
                    Image(systemName: "plus")
                }
            }
            #else
            ToolbarItem(placement: .automatic) {
                Button {
                    showingAddItem = true
                } label: {
                    Image(systemName: "plus")
                }
            }
            #endif

            #if os(iOS)
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(
                    item: generateShareText(),
                    subject: Text("Shopping List"),
                    message: Text("Here's our shopping list")
                ) {
                    Image(systemName: "square.and.arrow.up")
                }
            }
            #endif
        }
        .sheet(isPresented: $showingAddItem) {
            AddGroceryItemView(weekPlan: primaryWeekPlan)
        }
    }

    // MARK: - Subviews

    private var emptyStateView: some View {
        EmptyStateView(
            icon: "cart",
            title: "No Shopping Items",
            message: "No items to buy yet. Plan some meals and check your pantry to build your list.",
            action: { showingAddItem = true },
            actionLabel: "Add Item Manually"
        )
    }

    private var pantryOnlyEmptyStateView: some View {
        EmptyStateView(
            icon: "checkmark.circle",
            title: "All Items in Pantry",
            message: "Check your pantry to see what you still need to buy.",
            action: { showingAddItem = true },
            actionLabel: "Add Item Manually"
        )
    }

    private var groceryListContent: some View {
        List {
            // Category sections for unchecked items
            ForEach(sortedCategories, id: \.self) { category in
                if let items = itemsByCategory[category] {
                    GroceryCategorySection(
                        category: category,
                        items: items,
                        displayQuantities: aggregatedQuantities,
                        onToggleItem: toggleItem,
                        onDeleteItem: deleteItem
                    )
                }
            }

            // Collapsible checked items section
            if !checkedItems.isEmpty {
                Section {
                    #if os(iOS)
                    DisclosureGroup(
                        isExpanded: $checkedItemsExpanded,
                        content: {
                            ForEach(checkedItems) { item in
                                GroceryItemRow(
                                    item: item,
                                    displayQuantity: aggregatedQuantities[item.id],
                                    onToggle: { toggleItem(item) },
                                    onDelete: { deleteItem(item) }
                                )
                            }
                        },
                        label: {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.secondary)
                                Text("Checked Items")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(checkedItems.count)")
                                    .font(AppTypography.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.secondary.opacity(0.2))
                                    .clipShape(Capsule())
                            }
                        }
                    )
                    #else
                    // macOS alternative: simple expandable section
                    Button {
                        checkedItemsExpanded.toggle()
                    } label: {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.secondary)
                            Text("Checked Items")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(checkedItems.count)")
                                .font(AppTypography.caption)
                                .foregroundStyle(.secondary)
                            Image(systemName: checkedItemsExpanded ? "chevron.up" : "chevron.down")
                                .font(AppTypography.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)

                    if checkedItemsExpanded {
                        ForEach(checkedItems) { item in
                            GroceryItemRow(
                                item: item,
                                displayQuantity: aggregatedQuantities[item.id],
                                onToggle: { toggleItem(item) },
                                onDelete: { deleteItem(item) }
                            )
                        }
                    }
                    #endif
                }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
    }

    // MARK: - Actions

    private func toggleItem(_ item: GroceryItem) {
        withAnimation {
            let group = itemGroupMap[item.id] ?? [item]
            let newState = !item.isChecked
            for groupItem in group {
                if groupItem.isChecked != newState {
                    groupItem.isChecked = newState
                    if newState {
                        groupItem.checkedAt = Date()
                    } else {
                        groupItem.checkedAt = nil
                        groupItem.checkedBy = nil
                    }
                }
            }
        }
    }

    private func deleteItem(_ item: GroceryItem) {
        withAnimation {
            let group = itemGroupMap[item.id] ?? [item]
            for groupItem in group {
                viewContext.delete(groupItem)
            }
        }
    }

    private func generateShareText() -> String {
        var text = "Shopping List\n\n"

        for category in sortedCategories {
            if let items = itemsByCategory[category] {
                text += "\(category.displayName):\n"
                for item in items {
                    let name = (item.customName?.isEmpty == false ? item.customName : nil) ?? item.ingredient?.name ?? "Unknown"
                    let qty = aggregatedQuantities[item.id] ?? item.quantity
                    let quantity = formatQuantity(qty, unit: item.unit)
                    text += "  - \(name) \(quantity)\n"
                }
                text += "\n"
            }
        }

        return text
    }

    private func formatQuantity(_ quantity: Double, unit: MeasurementUnit) -> String {
        let quantityStr = quantity.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", quantity)
            : String(format: "%.1f", quantity)
        return "(\(quantityStr) \(unit.abbreviation))"
    }
}

// MARK: - Shopping Progress Header

/// Simple progress indicator for the shopping list
private struct ShoppingProgressHeader: View {
    let completedItems: Int
    let totalItems: Int

    private var progressPercent: Double {
        guard totalItems > 0 else { return 0 }
        return Double(completedItems) / Double(totalItems)
    }

    var body: some View {
        let percent = Int(progressPercent * 100)
        let progressTint: Color = progressPercent == 1.0 ? .green : .accentColor
        VStack(spacing: 4) {
            HStack {
                Text("\(completedItems) of \(totalItems) items")
                    .font(AppTypography.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(percent)%")
                    .font(AppTypography.subheadline)
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: progressPercent)
                .tint(progressTint)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(Color.systemGroupedBackground)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Shopping progress: \(completedItems) of \(totalItems) items completed, \(percent) percent")
    }
}

// MARK: - Preview

#Preview {
    GroceryListView()
        .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
}
