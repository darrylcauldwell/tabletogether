import SwiftUI
import CoreData

/// Dedicated meal logging tab.
/// Shows a prominent "Log a Meal" button, today's meals, and recent days.
///
/// All meal log data is personal and stored in CloudKit private database.
struct MealLogView: View {
    @Environment(\.privateDataManager) private var privateDataManager
    @FetchRequest(sortDescriptors: [SortDescriptor(\.title)]) private var recipes: FetchedResults<Recipe>
    @FetchRequest(sortDescriptors: [SortDescriptor(\.dayOfWeekRaw), SortDescriptor(\.mealTypeRaw)]) private var mealSlots: FetchedResults<MealSlot>
    @FetchRequest(sortDescriptors: [SortDescriptor(\.displayName)]) private var users: FetchedResults<User>

    @State private var showQuickLogSheet = false
    @State private var logToEdit: PrivateMealLog?
    @State private var logToDelete: PrivateMealLog?
    @State private var showDeleteConfirmation = false

    private var currentUser: User? {
        users.first
    }

    private var weeklyLogs: [PrivateMealLog] {
        return privateDataManager?.mealLogs ?? []
    }

    private var recipeLookup: SimpleRecipeLookup {
        SimpleRecipeLookup(recipes: Array(recipes))
    }

    private var todayLogs: [PrivateMealLog] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return weeklyLogs
            .filter { calendar.startOfDay(for: $0.date) == today }
            .sorted { mealTypeOrder($0.mealType) < mealTypeOrder($1.mealType) }
    }

    /// Today's planned meals (auto-populated, not yet confirmed)
    private var todayPlannedLogs: [PrivateMealLog] {
        todayLogs.filter { $0.status == .planned }
    }

    /// Today's consumed meals
    private var todayConsumedLogs: [PrivateMealLog] {
        todayLogs.filter { $0.status == .consumed }
    }

    /// Today's skipped meals
    private var todaySkippedLogs: [PrivateMealLog] {
        todayLogs.filter { $0.status == .skipped }
    }

    private var recentDays: [(date: Date, logs: [PrivateMealLog])] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        var grouped: [Date: [PrivateMealLog]] = [:]
        for log in weeklyLogs {
            let day = calendar.startOfDay(for: log.date)
            if day < today {
                grouped[day, default: []].append(log)
            }
        }

        return grouped.keys
            .sorted(by: >)
            .prefix(6)
            .map { (date: $0, logs: grouped[$0] ?? []) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Prominent log button
                    Button {
                        showQuickLogSheet = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "plus.circle.fill")
                                .font(AppTypography.title2)
                            Text("Log a Meal")
                                .font(AppTypography.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundStyle(.white)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Theme.Colors.primary)
                        )
                    }
                    .padding(.horizontal)

                    if weeklyLogs.isEmpty {
                        // Empty state
                        emptyState
                            .padding(.horizontal)
                    } else {
                        // Today section
                        todaySection
                            .padding(.horizontal)

                        // Recent days
                        if !recentDays.isEmpty {
                            recentDaysSection
                                .padding(.horizontal)
                        }
                    }

                    Spacer(minLength: 20)
                }
                .padding(.vertical)
            }
            .background(Theme.Colors.background)
            .navigationTitle("Meal Log")
            .sheet(isPresented: $showQuickLogSheet) {
                QuickLogSheet()
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
                            await privateDataManager?.deleteMealLog(log)
                        }
                    }
                    logToDelete = nil
                }
            } message: {
                Text("This meal log entry will be permanently removed.")
            }
            .task {
                await privateDataManager?.fetchCurrentWeekLogs()
                // Auto-populate from plan
                if let manager = privateDataManager, let user = currentUser {
                    await manager.syncPlannedMeals(slots: Array(mealSlots), currentUser: user)
                }
            }
        }
    }

    // MARK: - Today Section

    private var todaySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Today")
                .font(AppTypography.headline)
                .foregroundStyle(Theme.Colors.textPrimary)

            if todayLogs.isEmpty {
                Text("No meals logged yet today.")
                    .font(AppTypography.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 8) {
                    // Planned meals (from plan, not yet confirmed)
                    if !todayPlannedLogs.isEmpty {
                        ForEach(todayPlannedLogs, id: \.id) { log in
                            PlannedMealRow(
                                log: log,
                                recipeLookup: recipeLookup,
                                onConfirm: {
                                    Task {
                                        await privateDataManager?.updateLogStatus(log, status: .consumed)
                                    }
                                },
                                onSkip: {
                                    Task {
                                        await privateDataManager?.updateLogStatus(log, status: .skipped)
                                    }
                                }
                            )
                        }
                    }

                    // Consumed meals
                    ForEach(todayConsumedLogs, id: \.id) { log in
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
                    }

                    // Skipped meals
                    if !todaySkippedLogs.isEmpty {
                        ForEach(todaySkippedLogs, id: \.id) { log in
                            SkippedMealLogRow(log: log, recipeLookup: recipeLookup)
                                .contextMenu {
                                    Button {
                                        Task {
                                            await privateDataManager?.updateLogStatus(log, status: .consumed)
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
                        }
                    }

                    Divider()
                        .background(Theme.Colors.textSecondary.opacity(0.3))

                    DayTotalsRow(totals: todayTotals)
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

    // MARK: - Recent Days Section

    private var recentDaysSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Days")
                .font(AppTypography.headline)
                .foregroundStyle(Theme.Colors.textPrimary)

            ForEach(recentDays, id: \.date) { day in
                DayDetailCard(
                    date: day.date,
                    mealLogs: day.logs,
                    recipeLookup: recipeLookup
                )
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.and.pencil")
                .font(AppTypography.fixed(48))
                .foregroundStyle(Theme.Colors.textSecondary.opacity(0.5))

            Text("Your meal log is empty.")
                .font(AppTypography.body)
                .foregroundStyle(Theme.Colors.textSecondary)

            Text("Tap \"Log a Meal\" to record what you eat. Over time, you'll see patterns in the Insights tab.")
                .font(AppTypography.subheadline)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Theme.Colors.cardBackground)
        )
    }

    // MARK: - Helpers

    private var todayTotals: DayTotals {
        var calories = 0
        var protein = 0
        var carbs = 0
        var fat = 0

        // Only count consumed meals in day totals
        for log in todayConsumedLogs {
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
}
