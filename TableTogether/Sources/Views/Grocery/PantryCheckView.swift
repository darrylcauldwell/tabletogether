import SwiftUI
import SwiftData

// MARK: - Date Range Preset

enum DateRangePreset: String, CaseIterable {
    case thisWeek = "This Week"
    case twoWeeks = "2 Weeks"
    case custom = "Custom"
}

// MARK: - Date Helpers

func mondayOfCurrentWeek() -> Date {
    let calendar = Calendar.current
    let today = Date()
    let weekday = calendar.component(.weekday, from: today)
    let daysFromMonday = (weekday + 5) % 7
    return calendar.startOfDay(for: calendar.date(byAdding: .day, value: -daysFromMonday, to: today) ?? today)
}

func sundayOfCurrentWeek() -> Date {
    let monday = mondayOfCurrentWeek()
    return Calendar.current.date(byAdding: .day, value: 6, to: monday) ?? monday
}

// MARK: - PantryCheckView

/// Pantry check interface — shows all recipe-derived ingredients grouped by category.
/// Users mark items they already have at home. Remaining items flow to the shopping list.
/// Supports date range selection to aggregate ingredients across multiple week plans.
struct PantryCheckView: View {
    @Environment(\.modelContext) private var modelContext

    @Query private var weekPlans: [WeekPlan]

    @AppStorage("groceryDatePreset") private var presetStorage: String = DateRangePreset.thisWeek.rawValue
    @State private var startDate: Date = mondayOfCurrentWeek()
    @State private var endDate: Date = sundayOfCurrentWeek()
    @State private var selectedPreset: DateRangePreset = .thisWeek
    @State private var inPantryExpanded = false
    @State private var pantryCheckComplete = false
    @AppStorage("hasSeenPantryHint") private var hasSeenPantryHint = false

    // MARK: - Aggregation

    /// Week plans whose weekStartDate falls within the selected date range
    private var relevantWeekPlans: [WeekPlan] {
        let range = startDate...endDate
        return weekPlans.filter { range.contains($0.weekStartDate) }
    }

    /// Grouping key for an item — ingredient ID for recipe items, customName for manual items
    private func groupingKey(for item: GroceryItem) -> String {
        if let ingredientID = item.ingredient?.id {
            return ingredientID.uuidString
        }
        return "manual-\(item.customName ?? item.id.uuidString)"
    }

    /// All pantry check items from relevant week plans, grouped by ingredient
    private var pantryItemGroups: [String: [GroceryItem]] {
        var groups: [String: [GroceryItem]] = [:]
        for plan in relevantWeekPlans {
            for item in plan.pantryCheckItems {
                let key = groupingKey(for: item)
                groups[key, default: []].append(item)
            }
        }
        return groups
    }

    /// One representative item per ingredient group (for display and binding)
    private var aggregatedPantryItems: [GroceryItem] {
        pantryItemGroups.values.compactMap { $0.first }
    }

    /// Summed quantities keyed by representative item ID
    private var aggregatedQuantities: [UUID: Double] {
        var quantities: [UUID: Double] = [:]
        for (_, items) in pantryItemGroups {
            if let first = items.first {
                quantities[first.id] = items.reduce(0) { $0 + $1.quantity }
            }
        }
        return quantities
    }

    /// Map from representative item ID to all items in its group
    private var itemGroupMap: [UUID: [GroceryItem]] {
        var map: [UUID: [GroceryItem]] = [:]
        for (_, items) in pantryItemGroups {
            if let first = items.first {
                map[first.id] = items
            }
        }
        return map
    }

    /// Whether a group is considered in-pantry (any item in group is in pantry)
    private func isGroupInPantry(_ item: GroceryItem) -> Bool {
        guard let group = itemGroupMap[item.id] else { return item.isInPantry }
        return group.contains { $0.isInPantry }
    }

    /// Items not yet marked as in-pantry
    private var neededItems: [GroceryItem] {
        aggregatedPantryItems.filter { !isGroupInPantry($0) }
    }

    /// Items marked as already in pantry
    private var alreadyHaveItems: [GroceryItem] {
        aggregatedPantryItems.filter { isGroupInPantry($0) }
    }

    /// Needed items grouped by category
    private var itemsByCategory: [IngredientCategory: [GroceryItem]] {
        Dictionary(grouping: neededItems) { $0.category }
    }

    /// Sorted categories for consistent display order
    private var sortedCategories: [IngredientCategory] {
        IngredientCategory.allCases.filter { itemsByCategory[$0] != nil }
    }

    /// Progress calculation
    private var totalItems: Int {
        aggregatedPantryItems.count
    }

    private var completedItems: Int {
        alreadyHaveItems.count
    }

    /// Whether any relevant week plans have recipes planned
    private var hasPlannedRecipes: Bool {
        relevantWeekPlans.contains { plan in
            plan.slots.contains { !$0.recipes.isEmpty }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if aggregatedPantryItems.isEmpty {
                emptyStateView
            } else if neededItems.isEmpty || pantryCheckComplete {
                completionStateView
            } else {
                // Date range header only shown during active checking
                PantryDateRangeHeader(
                    startDate: $startDate,
                    endDate: $endDate,
                    selectedPreset: $selectedPreset,
                    completedItems: completedItems,
                    totalItems: totalItems
                )

                // Instruction hint for first-time users
                if !hasSeenPantryHint {
                    hintBanner
                }

                // Mark all remaining as needed action
                markAllNeededBar

                pantryListContent
            }
        }
        .navigationTitle("Pantry Check")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    regenerateAllLists()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
            #else
            ToolbarItem(placement: .automatic) {
                Button {
                    regenerateAllLists()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
            #endif
        }
        .onChange(of: startDate) { _, _ in
            generateForNewPlans()
            syncPantryStates()
        }
        .onChange(of: endDate) { _, _ in
            generateForNewPlans()
            syncPantryStates()
        }
        .onChange(of: selectedPreset) { _, newValue in
            presetStorage = newValue.rawValue
        }
        .onAppear {
            if let stored = DateRangePreset(rawValue: presetStorage), stored != selectedPreset {
                selectedPreset = stored
                applyPreset(stored)
            }
            generateForNewPlans()
        }
    }

    // MARK: - Subviews

    private var hintBanner: some View {
        HStack {
            Text("Tap \"Have\" on items you already have at home")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                withAnimation {
                    hasSeenPantryHint = true
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.08))
    }

    private var markAllNeededBar: some View {
        HStack {
            Spacer()
            Button {
                markAllRemainingAsNeeded()
            } label: {
                Label("All remaining needed", systemImage: "cart.badge.plus")
                    .font(.subheadline)
            }
            .buttonStyle(.bordered)
            .tint(.accentColor)
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
    }

    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("No Ingredients", systemImage: "checklist.checked")
        } description: {
            if hasPlannedRecipes {
                Text("Generate a pantry list from your planned meals.")
            } else {
                Text("Plan some meals first, then generate your pantry list.")
            }
        } actions: {
            if hasPlannedRecipes {
                Button {
                    generatePantryList()
                } label: {
                    Label("Generate Pantry List", systemImage: "checklist.checked")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var completionStateView: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            Text("Pantry check done")
                .font(.title2)
                .fontWeight(.semibold)

            let shoppingCount = neededItems.count
            let pantryCount = alreadyHaveItems.count
            Text("\(shoppingCount) items on your shopping list, \(pantryCount) already in your pantry.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            if pantryCheckComplete {
                Button {
                    withAnimation {
                        pantryCheckComplete = false
                    }
                } label: {
                    Label("Review again", systemImage: "arrow.uturn.backward")
                        .font(.subheadline)
                }
                .buttonStyle(.bordered)
            }

            Spacer()
        }
    }

    private var pantryListContent: some View {
        List {
            // Category sections for items still needed
            ForEach(sortedCategories, id: \.self) { category in
                if let items = itemsByCategory[category] {
                    GroceryCategorySection(
                        category: category,
                        items: items,
                        mode: .pantryCheck,
                        displayQuantities: aggregatedQuantities,
                        onToggleItem: togglePantryItem,
                        onDeleteItem: deleteItem
                    )
                }
            }

            // Collapsible "already have" section
            if !alreadyHaveItems.isEmpty {
                alreadyHaveSection
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
    }

    private var alreadyHaveSection: some View {
        Section {
            #if os(iOS)
            DisclosureGroup(
                isExpanded: $inPantryExpanded,
                content: {
                    ForEach(alreadyHaveItems) { item in
                        GroceryItemRow(
                            item: item,
                            displayQuantity: aggregatedQuantities[item.id],
                            mode: .pantryCheck,
                            onToggle: { togglePantryItem(item) },
                            onDelete: { deleteItem(item) }
                        )
                    }
                },
                label: {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.orange)
                        Text("Already Have")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(alreadyHaveItems.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.secondary.opacity(0.2))
                            .clipShape(Capsule())
                    }
                }
            )
            #else
            Button {
                inPantryExpanded.toggle()
            } label: {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.orange)
                    Text("Already Have")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(alreadyHaveItems.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Image(systemName: inPantryExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            if inPantryExpanded {
                ForEach(alreadyHaveItems) { item in
                    GroceryItemRow(
                        item: item,
                        displayQuantity: aggregatedQuantities[item.id],
                        mode: .pantryCheck,
                        onToggle: { togglePantryItem(item) },
                        onDelete: { deleteItem(item) }
                    )
                }
            }
            #endif
        }
    }

    // MARK: - Actions

    /// Auto-generates grocery items for any relevant week plan that has recipes but no derived items.
    /// Called when the date range changes to include new week plans.
    private func generateForNewPlans() {
        var generated = false
        for plan in relevantWeekPlans {
            let hasDerivedItems = plan.groceryItems.contains { !$0.isManuallyAdded }
            let hasRecipes = plan.slots.contains { !$0.recipes.isEmpty }
            if !hasDerivedItems && hasRecipes {
                plan.generateGroceryList()
                generated = true
            }
        }
        if generated {
            if let plan = relevantWeekPlans.first {
                plan.cleanupOrphanedGroceryItems(context: modelContext)
            }
            modelContext.saveWithLogging(context: "auto-generate for new week plans")
        }
    }

    private func generatePantryList() {
        for plan in relevantWeekPlans {
            if plan.groceryItems.filter({ !$0.isManuallyAdded }).isEmpty {
                plan.generateGroceryList()
            }
        }
        if let plan = relevantWeekPlans.first {
            plan.cleanupOrphanedGroceryItems(context: modelContext)
        }
        modelContext.saveWithLogging(context: "pantry list generation")
        pantryCheckComplete = false
        hasSeenPantryHint = false
    }

    private func regenerateAllLists() {
        for plan in relevantWeekPlans {
            plan.generateGroceryList()
        }
        // Clean up orphaned items left behind by the in-place update strategy
        if let plan = relevantWeekPlans.first {
            plan.cleanupOrphanedGroceryItems(context: modelContext)
        }
        modelContext.saveWithLogging(context: "pantry list regeneration")
        pantryCheckComplete = false
    }

    private func markAllRemainingAsNeeded() {
        withAnimation {
            // Mark all remaining "need" items as pantry-checked so they flow to the shopping list
            for item in neededItems {
                let group = itemGroupMap[item.id] ?? [item]
                for groupItem in group {
                    groupItem.pantryChecked = true
                }
            }
            pantryCheckComplete = true
            hasSeenPantryHint = true
        }
    }

    private func togglePantryItem(_ item: GroceryItem) {
        withAnimation {
            let group = itemGroupMap[item.id] ?? [item]
            let newState = !isGroupInPantry(item)
            for groupItem in group {
                if groupItem.isInPantry != newState {
                    groupItem.isInPantry = newState
                }
                // Mark as pantry-checked so it flows to shopping list when not in pantry
                groupItem.pantryChecked = true
            }
            if !hasSeenPantryHint {
                hasSeenPantryHint = true
            }
        }
    }

    private func deleteItem(_ item: GroceryItem) {
        withAnimation {
            let group = itemGroupMap[item.id] ?? [item]
            for groupItem in group {
                modelContext.delete(groupItem)
            }
        }
    }

    /// Syncs pantry state within ingredient groups when date range expands.
    /// If an ingredient was marked as "have" in one week, mark it in all weeks.
    private func syncPantryStates() {
        var groups: [String: [GroceryItem]] = [:]
        for plan in relevantWeekPlans {
            for item in plan.pantryCheckItems {
                let key = groupingKey(for: item)
                groups[key, default: []].append(item)
            }
        }
        for (_, items) in groups {
            if items.contains(where: { $0.isInPantry }) {
                for item in items where !item.isInPantry {
                    item.isInPantry = true
                }
            }
        }
    }

    /// Applies a preset to the local date state
    private func applyPreset(_ preset: DateRangePreset) {
        let monday = mondayOfCurrentWeek()
        let calendar = Calendar.current
        switch preset {
        case .thisWeek:
            startDate = monday
            endDate = calendar.date(byAdding: .day, value: 6, to: monday) ?? monday
        case .twoWeeks:
            startDate = monday
            endDate = calendar.date(byAdding: .day, value: 13, to: monday) ?? monday
        case .custom:
            break // Keep existing custom dates
        }
    }
}

// MARK: - PantryDateRangeHeader

/// Header with date range presets, custom date pickers, and progress indicator
private struct PantryDateRangeHeader: View {
    @Binding var startDate: Date
    @Binding var endDate: Date
    @Binding var selectedPreset: DateRangePreset
    let completedItems: Int
    let totalItems: Int

    @State private var showCustomPickers = false

    private var progressPercent: Double {
        guard totalItems > 0 else { return 0 }
        return Double(completedItems) / Double(totalItems)
    }

    private var dateRangeLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return "\(formatter.string(from: startDate)) – \(formatter.string(from: endDate))"
    }

    var body: some View {
        VStack(spacing: 12) {
            presetPicker
            dateLabel
            if showCustomPickers { customPickers }
            if totalItems > 0 { progressSection }
        }
        .padding(.vertical, 12)
        .background(Color.systemGroupedBackground)
    }

    private var presetPicker: some View {
        HStack(spacing: 8) {
            ForEach(DateRangePreset.allCases, id: \.self) { preset in
                presetButton(for: preset)
            }
            Spacer()
        }
        .padding(.horizontal)
    }

    private func presetButton(for preset: DateRangePreset) -> some View {
        let isSelected = selectedPreset == preset
        return Button {
            selectPreset(preset)
        } label: {
            Text(preset.rawValue)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.1))
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var dateLabel: some View {
        Text(dateRangeLabel)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
    }

    private var customPickers: some View {
        VStack(spacing: 8) {
            DatePicker("From", selection: $startDate, displayedComponents: .date)
                #if os(iOS)
                .datePickerStyle(.compact)
                #endif
            DatePicker("To", selection: $endDate, in: startDate..., displayedComponents: .date)
                #if os(iOS)
                .datePickerStyle(.compact)
                #endif
        }
        .padding(.horizontal)
    }

    private var progressSection: some View {
        let percent = Int(progressPercent * 100)
        let progressTint: Color = progressPercent == 1.0 ? .green : .orange
        return VStack(spacing: 4) {
            HStack {
                Text("\(completedItems) of \(totalItems) items checked")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(percent)%")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: progressPercent)
                .tint(progressTint)
        }
        .padding(.horizontal)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Pantry check progress: \(completedItems) of \(totalItems) items, \(percent) percent")
    }

    private func selectPreset(_ preset: DateRangePreset) {
        selectedPreset = preset
        let monday = mondayOfCurrentWeek()
        let calendar = Calendar.current

        switch preset {
        case .thisWeek:
            startDate = monday
            endDate = calendar.date(byAdding: .day, value: 6, to: monday) ?? monday
            showCustomPickers = false
        case .twoWeeks:
            startDate = monday
            endDate = calendar.date(byAdding: .day, value: 13, to: monday) ?? monday
            showCustomPickers = false
        case .custom:
            showCustomPickers = true
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        PantryCheckView()
    }
    .modelContainer(for: [WeekPlan.self, GroceryItem.self, Ingredient.self], inMemory: true)
}
