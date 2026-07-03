import SwiftUI
import CoreData

// MARK: - WeekPlannerView

/// Main planning interface showing a week's meal plan with drag and drop support.
/// Adapts layout for iPad (full week view) vs iPhone (scrollable day-by-day).
struct WeekPlannerView: View {
    @Environment(\.managedObjectContext) private var viewContext

    @FetchRequest(sortDescriptors: [SortDescriptor(\.weekStartDate, order: .reverse)]) private var weekPlans: FetchedResults<WeekPlan>
    @FetchRequest(sortDescriptors: [SortDescriptor(\.title)]) private var recipes: FetchedResults<Recipe>
    @FetchRequest(sortDescriptors: [SortDescriptor(\.timesCooked, order: .reverse)]) private var suggestionMemories: FetchedResults<SuggestionMemory>
    @FetchRequest(sortDescriptors: [SortDescriptor(\.displayName)]) private var users: FetchedResults<User>
    @FetchRequest(sortDescriptors: [SortDescriptor(\.name)]) private var households: FetchedResults<Household>

    @State private var currentWeekStart: Date = WeekPlannerView.mondayOfCurrentWeek()
    @State private var isSuggestionTrayExpanded: Bool = false
    @State private var showingRecentChanges: Bool = false

    private var currentUser: User? {
        User.current(in: users)
    }

    private var currentWeekPlan: WeekPlan? {
        weekPlans.first { Calendar.current.isDate($0.weekStartDate, inSameDayAs: currentWeekStart) }
    }

    var body: some View {
        VStack(spacing: 0) {
            WeekHeaderView(
                weekStartDate: $currentWeekStart,
                onPreviousWeek: navigateToPreviousWeek,
                onNextWeek: navigateToNextWeek
            )

            // Recent Changes Banner (CloudKit sync is automatic via NSPersistentCloudKitContainer)

            Divider()

            // List-based week view — one row group per day, only populated
            // meal slots shown, quiet per-day "Add meal" affordance. Replaces
            // the previous iPad grid + iPhone day-tab views with a single
            // layout that works at all widths.
            WeekListView(
                weekPlan: currentWeekPlan,
                weekStartDate: currentWeekStart,
                onSlotTapped: handleSlotTapped,
                onRecipeDropped: handleRecipeDropped,
                onAddMeal: materializeSlot,
                onPickerDismissed: cleanupAfterPicker
            )

            Divider()

            SuggestionTrayView(
                isExpanded: $isSuggestionTrayExpanded,
                familiarRecipes: suggestedFamiliarRecipes,
                newRecipes: suggestedNewRecipes
            )

            WeekActionsBar(
                onCopyFromLastWeek: copyFromLastWeek,
                onClearWeek: clearWeek
            )
        }
        .navigationTitle("")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // MARK: - Computed Properties

    private var suggestedFamiliarRecipes: [Recipe] {
        let engine = SuggestionEngine()
        let result = engine.suggestRecipes(
            allRecipes: Array(recipes),
            weekPlan: currentWeekPlan,
            memory: Array(suggestionMemories)
        )
        return result.familiarSuggestions
    }

    private var suggestedNewRecipes: [Recipe] {
        let engine = SuggestionEngine()
        let result = engine.suggestRecipes(
            allRecipes: Array(recipes),
            weekPlan: currentWeekPlan,
            memory: Array(suggestionMemories)
        )
        return result.newSuggestions
    }

    // MARK: - Helper Methods

    static func mondayOfCurrentWeek() -> Date {
        let calendar = Calendar.current
        let today = Date()
        let weekday = calendar.component(.weekday, from: today)
        let daysFromMonday = (weekday + 5) % 7
        return calendar.date(byAdding: .day, value: -daysFromMonday, to: today) ?? today
    }

    private func navigateToPreviousWeek() {
        if let newDate = Calendar.current.date(byAdding: .weekOfYear, value: -1, to: currentWeekStart) {
            currentWeekStart = newDate
        }
    }

    private func navigateToNextWeek() {
        if let newDate = Calendar.current.date(byAdding: .weekOfYear, value: 1, to: currentWeekStart) {
            currentWeekStart = newDate
        }
    }

    /// Materializes the plan + slot on demand when the user adds a meal to an
    /// empty cell. Left unsaved until the picker commits a meal; if the picker
    /// is canceled, cleanupAfterPicker discards the empty slot again (#Change2).
    private func materializeSlot(day: DayOfWeek, mealType: MealType) -> MealSlot? {
        let plan = currentWeekPlan ?? WeekPlan.fetchOrCreate(
            for: currentWeekStart, household: households.first, in: viewContext)
        return plan.fetchOrCreateSlot(day: day, mealType: mealType, in: viewContext)
    }

    /// A canceled picker leaves behind the slot (and possibly the plan) that
    /// materializeSlot created — empty cells must not persist as data.
    private func cleanupAfterPicker(_ slot: MealSlot) {
        guard !slot.isDeleted, slot.isEmpty else { return }
        let plan = slot.weekPlan
        viewContext.delete(slot)
        if let plan, plan.slotsArray.isEmpty, plan.householdNote == nil, plan.groceryItemsArray.isEmpty {
            viewContext.delete(plan)
        }
        if viewContext.hasChanges {
            viewContext.saveWithLogging(context: "discard unused slot")
        }
    }

    private func handleSlotTapped(_ slot: MealSlot) {
        // Handle slot selection - could show recipe picker sheet
    }

    private func handleRecipeDropped(_ recipeId: String, _ slot: MealSlot) {
        // Look up recipe by UUID string
        guard let uuid = UUID(uuidString: recipeId),
              let recipe = recipes.first(where: { $0.id == uuid }) else {
            return
        }
        slot.addToRecipes(recipe)
        slot.customMealName = nil
        slot.modifiedAt = Date()
        viewContext.saveWithLogging(context: "recipe drop to slot")
    }

    private func copyFromLastWeek() {
        guard let previousWeekStart = Calendar.current.date(byAdding: .weekOfYear, value: -1, to: currentWeekStart),
              let previousPlan = weekPlans.first(where: { Calendar.current.isDate($0.weekStartDate, inSameDayAs: previousWeekStart) }),
              let user = currentUser else { return }

        // The destination plan materializes on demand (#Change2). Route through
        // the model mutator so plate components are carried over and modifiedBy
        // is set, instead of inlining a recipes-only copy.
        let currentPlan = currentWeekPlan ?? WeekPlan.fetchOrCreate(
            for: currentWeekStart, household: households.first, in: viewContext)
        currentPlan.copyFrom(previousPlan, by: user)
        viewContext.saveWithLogging(context: "copy from last week")
    }

    private func clearWeek() {
        guard let weekPlan = currentWeekPlan, let user = currentUser else { return }

        // Route through clearAll so plate components are deleted (not orphaned) and
        // modifiedBy is set.
        weekPlan.clearAll(by: user)
        viewContext.saveWithLogging(context: "clear week")
    }
}

// MARK: - WeekHeaderView

/// Header with week navigation controls
struct WeekHeaderView: View {
    @Binding var weekStartDate: Date
    let onPreviousWeek: () -> Void
    let onNextWeek: () -> Void

    private var weekLabel: String {
        let calendar = Calendar.current
        let weekStart = calendar.startOfDay(for: weekStartDate)

        if calendar.isDate(weekStart, inSameDayAs: WeekPlannerView.mondayOfCurrentWeek()) {
            return "This Week"
        } else if let nextWeekStart = calendar.date(byAdding: .weekOfYear, value: 1, to: WeekPlannerView.mondayOfCurrentWeek()),
                  calendar.isDate(weekStart, inSameDayAs: nextWeekStart) {
            return "Next Week"
        } else if let lastWeekStart = calendar.date(byAdding: .weekOfYear, value: -1, to: WeekPlannerView.mondayOfCurrentWeek()),
                  calendar.isDate(weekStart, inSameDayAs: lastWeekStart) {
            return "Last Week"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            let endDate = calendar.date(byAdding: .day, value: 6, to: weekStartDate) ?? weekStartDate
            return "Week of \(formatter.string(from: weekStartDate)) - \(formatter.string(from: endDate))"
        }
    }

    private static func mondayOfCurrentWeek() -> Date {
        let calendar = Calendar.current
        let today = Date()
        let weekday = calendar.component(.weekday, from: today)
        let daysFromMonday = (weekday + 5) % 7
        return calendar.date(byAdding: .day, value: -daysFromMonday, to: today) ?? today
    }

    var body: some View {
        HStack {
            Button(action: onPreviousWeek) {
                Image(systemName: "chevron.left")
                    .font(AppTypography.title3)
                    .foregroundColor(.accentColor)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)

            Spacer()

            Text(weekLabel)
                .font(AppTypography.headline)

            Spacer()

            Button(action: onNextWeek) {
                Image(systemName: "chevron.right")
                    .font(AppTypography.title3)
                    .foregroundColor(.accentColor)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
        }
        .padding(.vertical, 12)
        .padding(.horizontal)
    }
}

// MARK: - WeekActionsBar

/// Bottom action bar with week management actions
struct WeekActionsBar: View {
    let onCopyFromLastWeek: () -> Void
    let onClearWeek: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Button(action: onCopyFromLastWeek) {
                Label("Copy from Last Week", systemImage: "doc.on.doc")
            }

            Spacer()

            Button(role: .destructive, action: onClearWeek) {
                Label("Clear Week", systemImage: "trash")
            }
        }
        .padding()
        .background(Color.systemBackground)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        WeekPlannerView()
    }
    .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
}
