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
    /// Suggestions are invited, not ambient: hidden by default, toggled from the
    /// toolbar lightbulb, remembered across launches. The tray's own "Hide"
    /// writes the same flag, so both controls stay in agreement.
    @AppStorage("suggestionsTrayVisible") private var suggestionsVisible = false
    @State private var showingRecentChanges: Bool = false
    /// The current week defaults to remaining days only; the first backward
    /// step reveals its earlier days, the next one leaves the week.
    @State private var showsPastDaysOfCurrentWeek = false

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
                showsPastDays: showsPastDaysOfCurrentWeek,
                onSlotTapped: handleSlotTapped,
                onRecipeDropped: handleRecipeDropped,
                onMealChosen: handleMealChosen,
                onRemoveMeal: handleRemoveMeal
            )

            if suggestionsVisible {
                Divider()

                SuggestionTrayView(
                    isExpanded: $suggestionsVisible,
                    familiarRecipes: suggestedFamiliarRecipes,
                    newRecipes: suggestedNewRecipes
                )
            }

        }
        .navigationTitle("")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        suggestionsVisible.toggle()
                    }
                } label: {
                    Image(systemName: suggestionsVisible ? "lightbulb.fill" : "lightbulb")
                }
                .help(suggestionsVisible ? "Hide meal suggestions" : "Show meal suggestions")
                .accessibilityLabel(suggestionsVisible ? "Hide meal suggestions" : "Show meal suggestions")
            }
            ToolbarItem(placement: .automatic) {
                // Week management is occasional — a menu instead of a
                // permanently visible bottom bar (user request 2026-07-03).
                Menu {
                    Button {
                        copyFromLastWeek()
                    } label: {
                        Label("Copy from Last Week", systemImage: "doc.on.doc")
                    }
                    Button(role: .destructive) {
                        clearWeek()
                    } label: {
                        Label("Clear Week", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .help("Week actions")
                .accessibilityLabel("Week actions")
            }
        }
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

    private var isViewingCurrentWeek: Bool {
        Calendar.current.isDate(Date(), equalTo: currentWeekStart, toGranularity: .weekOfYear)
    }

    private func navigateToPreviousWeek() {
        // From the current week's remaining-days default, the first backward
        // step reveals this week's earlier days; the next one leaves the week.
        if isViewingCurrentWeek && !showsPastDaysOfCurrentWeek {
            withAnimation(.easeInOut(duration: 0.2)) {
                showsPastDaysOfCurrentWeek = true
            }
            return
        }
        if let newDate = Calendar.current.date(byAdding: .weekOfYear, value: -1, to: currentWeekStart) {
            currentWeekStart = newDate
            showsPastDaysOfCurrentWeek = false
        }
    }

    private func navigateToNextWeek() {
        if let newDate = Calendar.current.date(byAdding: .weekOfYear, value: 1, to: currentWeekStart) {
            currentWeekStart = newDate
            showsPastDaysOfCurrentWeek = false
        }
    }

    /// Applies a picked meal to (day, mealType): the plan and slot materialize
    /// here, AFTER the choice lands — never at picker-presentation time, which
    /// mutated the context inside the confirmationDialog action and broke the
    /// sheet's presentation on Catalyst (#Change2 regression). A canceled
    /// picker therefore leaves nothing behind.
    private func handleMealChosen(day: DayOfWeek, mealType: MealType, choice: MealChoice) {
        let plan = currentWeekPlan ?? WeekPlan.fetchOrCreate(
            for: currentWeekStart, household: households.first, in: viewContext)
        let slot = plan.fetchOrCreateSlot(day: day, mealType: mealType, in: viewContext)
        switch choice {
        case .recipe(let recipe):
            slot.addToRecipes(recipe)
        case .custom(let name):
            slot.customMealName = name
        }
        slot.modifiedAt = Date()
        viewContext.saveWithLogging(context: "meal choice")
    }

    /// Clears a meal added in error and deletes the now-empty slot record, so
    /// the cell returns to the addable empty state (empty slots aren't data,
    /// per the lazy-structure design). No-op without a current user.
    private func handleRemoveMeal(_ slot: MealSlot) {
        guard let user = currentUser else { return }
        slot.clear(by: user)
        slot.weekPlan?.removeFromSlots(slot)
        viewContext.delete(slot)
        viewContext.saveWithLogging(context: "remove meal")
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

// MARK: - Preview

#Preview {
    NavigationStack {
        WeekPlannerView()
    }
    .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
}
