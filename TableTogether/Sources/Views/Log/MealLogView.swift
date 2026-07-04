import SwiftUI
import CoreData

/// Dedicated meal logging tab — a per-day view with back/forward date
/// navigation, so personal differences and past gaps can be recorded against
/// any day. Floating add button matches the Recipes tab.
///
/// All meal log data is personal and stored in CloudKit private database.
struct MealLogView: View {
    @Environment(PrivateDataManager.self) private var privateDataManager
    @FetchRequest(sortDescriptors: [SortDescriptor(\.title)]) private var recipes: FetchedResults<Recipe>
    @FetchRequest(sortDescriptors: [SortDescriptor(\.dayOfWeekRaw), SortDescriptor(\.mealTypeRaw)]) private var mealSlots: FetchedResults<MealSlot>
    @FetchRequest(sortDescriptors: [SortDescriptor(\.displayName)]) private var users: FetchedResults<User>

    @State private var showQuickLogSheet = false
    @State private var logToEdit: PrivateMealLog?
    @State private var logToDelete: PrivateMealLog?
    @State private var showDeleteConfirmation = false
    /// The day being viewed/edited. Chevrons step it; personal differences and
    /// backfilled gaps are recorded against whichever day is selected.
    @State private var selectedDate = Calendar.current.startOfDay(for: Date())
    /// Nutrition is the spec's voluntary drill-down layer, pushed from here
    /// rather than holding a tab of its own. Screenshot mode deep-opens it.
    @State private var showInsights = TableTogetherApp.screenshotScreen == "insights"

    private var currentUser: User? {
        User.current(in: users)
    }

    private var weeklyLogs: [PrivateMealLog] {
        return privateDataManager.mealLogs
    }

    private var recipeLookup: SimpleRecipeLookup {
        SimpleRecipeLookup(recipes: Array(recipes))
    }

    /// Logs for the selected day.
    private var dayLogs: [PrivateMealLog] {
        let calendar = Calendar.current
        return weeklyLogs
            .filter { calendar.isDate($0.date, inSameDayAs: selectedDate) }
            .sorted { mealTypeOrder($0.mealType) < mealTypeOrder($1.mealType) }
    }

    private var dayPlannedLogs: [PrivateMealLog] { dayLogs.filter { $0.status == .planned } }
    private var dayConsumedLogs: [PrivateMealLog] { dayLogs.filter { $0.status == .consumed } }
    private var daySkippedLogs: [PrivateMealLog] { dayLogs.filter { $0.status == .skipped } }

    private var isViewingToday: Bool {
        Calendar.current.isDateInToday(selectedDate)
    }

    /// Header label for the selected day: "Today"/"Yesterday"/"Tomorrow" or a date.
    private var dateLabel: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(selectedDate) { return "Today" }
        if calendar.isDateInYesterday(selectedDate) { return "Yesterday" }
        if calendar.isDateInTomorrow(selectedDate) { return "Tomorrow" }
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEE d MMM")
        return formatter.string(from: selectedDate)
    }

    private func stepDay(_ delta: Int) {
        let calendar = Calendar.current
        if let newDate = calendar.date(byAdding: .day, value: delta, to: selectedDate) {
            selectedDate = calendar.startOfDay(for: newDate)
        }
    }

    var body: some View {
        NavigationStack {
            // Same canvas + floating-add pattern as the Recipes tab so the
            // personal surfaces share the shared surfaces' design language.
            ZStack(alignment: .bottomTrailing) {
                ScrollView {
                    VStack(spacing: 20) {
                        if let syncError = privateDataManager.syncError {
                            SyncErrorBanner(
                                error: syncError,
                                onDismiss: { privateDataManager.dismissSyncError() },
                                onRetry: { Task { await privateDataManager.refresh() } }
                            )
                            .padding(.horizontal)
                        }

                        dateNavigationHeader
                            .padding(.horizontal)

                        daySection
                            .padding(.horizontal)

                        Spacer(minLength: 100) // Space for FAB
                    }
                    .padding(.vertical)
                }
                .background(Color.appBackground)

                FloatingActionButton(action: { showQuickLogSheet = true }, accessibilityLabel: "Log a Meal") {
                    Image(systemName: "plus")
                }
                .padding(20)
            }
            .navigationTitle("Meal Log")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showInsights = true
                    } label: {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                    }
                    .help("Nutrition")
                    .accessibilityLabel("Nutrition")
                }
            }
            .navigationDestination(isPresented: $showInsights) {
                InsightsView()
            }
            .sheet(isPresented: $showQuickLogSheet) {
                QuickLogSheet(logDate: selectedDate)
            }
            .sheet(item: $logToEdit) { log in
                MealLogEditorSheet(log: log, privateDataManager: privateDataManager)
            }
            .alert("Delete Entry", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) {
                    logToDelete = nil
                }
                Button("Delete", role: .destructive) {
                    if let log = logToDelete {
                        Task {
                            await privateDataManager.deleteMealLog(log)
                        }
                    }
                    logToDelete = nil
                }
            } message: {
                Text("This meal log entry will be permanently removed.")
            }
            .task {
                // Load a broad window so day-to-day navigation is instant.
                let calendar = Calendar.current
                let start = calendar.date(byAdding: .day, value: -35, to: Date()) ?? Date()
                let end = calendar.date(byAdding: .day, value: 14, to: Date()) ?? Date()
                await privateDataManager.fetchMealLogs(from: start, to: end)
                await seedSelectedDay()
            }
            .task(id: selectedDate) {
                await seedSelectedDay()
            }
        }
    }

    /// Seeds the selected day's planned meals so navigating to it shows the
    /// plan to confirm or override.
    private func seedSelectedDay() async {
        guard let user = currentUser else { return }
        await privateDataManager.seedPlannedMeals(
            slots: Array(mealSlots), currentUser: user, forDays: [selectedDate])
    }

    // MARK: - Date Navigation Header

    private var dateNavigationHeader: some View {
        HStack {
            Button { stepDay(-1) } label: {
                Image(systemName: "chevron.left")
                    .font(AppTypography.headline)
                    .foregroundStyle(Theme.Colors.primary)
            }
            .buttonStyle(.plain)

            Spacer()

            VStack(spacing: 2) {
                Text(dateLabel)
                    .font(AppTypography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                if !isViewingToday {
                    Button("Jump to today") {
                        withAnimation { selectedDate = Calendar.current.startOfDay(for: Date()) }
                    }
                    .font(AppTypography.caption)
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.Colors.primary)
                }
            }

            Spacer()

            Button { stepDay(1) } label: {
                Image(systemName: "chevron.right")
                    .font(AppTypography.headline)
                    .foregroundStyle(Theme.Colors.primary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Today Section

    private var daySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if dayLogs.isEmpty {
                Text(isViewingToday ? "No meals logged yet today." : "No meals logged for this day.")
                    .font(AppTypography.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
            } else {
                VStack(spacing: 8) {
                    // Planned meals (from plan, not yet confirmed)
                    if !dayPlannedLogs.isEmpty {
                        ForEach(dayPlannedLogs, id: \.id) { log in
                            PlannedMealRow(
                                log: log,
                                calories: caloriesFor(log),
                                recipeLookup: recipeLookup,
                                onConfirm: {
                                    Task {
                                        await privateDataManager.updateLogStatus(log, status: .consumed)
                                    }
                                },
                                onSkip: {
                                    Task {
                                        await privateDataManager.updateLogStatus(log, status: .skipped)
                                    }
                                }
                            )
                        }
                    }

                    // Consumed meals
                    ForEach(dayConsumedLogs, id: \.id) { log in
                        MealLogRow(
                            log: log,
                            calories: caloriesFor(log),
                            protein: proteinFor(log),
                            recipeLookup: recipeLookup
                        )
                        .contextMenu {
                            Button {
                                logToEdit = log
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                logToDelete = log
                                showDeleteConfirmation = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .swipeToDelete {
                            logToDelete = log
                            showDeleteConfirmation = true
                        }
                    }

                    // Skipped meals
                    if !daySkippedLogs.isEmpty {
                        ForEach(daySkippedLogs, id: \.id) { log in
                            SkippedMealLogRow(log: log, recipeLookup: recipeLookup)
                                .contextMenu {
                                    Button {
                                        Task {
                                            await privateDataManager.updateLogStatus(log, status: .consumed)
                                        }
                                    } label: {
                                        Label("Mark as Eaten", systemImage: "checkmark.circle")
                                    }
                                    Button {
                                        logToEdit = log
                                    } label: {
                                        Label("Edit", systemImage: "pencil")
                                    }
                                    Button(role: .destructive) {
                                        logToDelete = log
                                        showDeleteConfirmation = true
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                                .swipeToDelete {
                                    logToDelete = log
                                    showDeleteConfirmation = true
                                }
                        }
                    }

                    Divider()
                        .background(Theme.Colors.textSecondary.opacity(0.3))

                    DayTotalsRow(totals: dayTotals)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Theme.Colors.cardBackground)
                        .shadow(color: .black.opacity(0.03), radius: 4, x: 0, y: 1)
                )
            }
        }
    }

    // MARK: - Helpers

    private var dayTotals: DayTotals {
        var calories = 0
        var protein = 0
        var carbs = 0
        var fat = 0

        // Only count consumed meals in day totals
        for log in dayConsumedLogs {
            calories += caloriesFor(log) ?? 0
            protein += proteinFor(log) ?? 0
            carbs += carbsFor(log) ?? 0
            fat += fatFor(log) ?? 0
        }

        return DayTotals(calories: calories, protein: protein, carbs: carbs, fat: fat)
    }

    private func caloriesFor(_ log: PrivateMealLog) -> Int? {
        if let cal = log.quickLogCalories { return cal }
        if let recipeID = log.recipeID,
           let macros = recipeLookup.macrosPerServing(for: recipeID),
           let cal = macros.calories {
            return Int(cal * log.servingsConsumed)
        }
        return nil
    }

    private func proteinFor(_ log: PrivateMealLog) -> Int? {
        if let prot = log.quickLogProtein { return prot }
        if let recipeID = log.recipeID,
           let macros = recipeLookup.macrosPerServing(for: recipeID),
           let prot = macros.protein {
            return Int(prot * log.servingsConsumed)
        }
        return nil
    }

    private func carbsFor(_ log: PrivateMealLog) -> Int? {
        if let carbs = log.quickLogCarbs { return carbs }
        if let recipeID = log.recipeID,
           let macros = recipeLookup.macrosPerServing(for: recipeID),
           let carbs = macros.carbs {
            return Int(carbs * log.servingsConsumed)
        }
        return nil
    }

    private func fatFor(_ log: PrivateMealLog) -> Int? {
        if let fat = log.quickLogFat { return fat }
        if let recipeID = log.recipeID,
           let macros = recipeLookup.macrosPerServing(for: recipeID),
           let fat = macros.fat {
            return Int(fat * log.servingsConsumed)
        }
        return nil
    }

    private func mealTypeOrder(_ type: MealType) -> Int {
        switch type {
        case .breakfast: return 0
        case .lunch: return 1
        case .dinner: return 2
        case .snack: return 3
        }
    }
}

#Preview {
    MealLogView()
        .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
        .environment(PrivateDataManager())
}
