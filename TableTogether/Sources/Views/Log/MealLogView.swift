import SwiftUI
import SwiftData
import Combine

/// Dedicated meal logging tab.
/// Shows a prominent "Log a Meal" button, today's meals, and recent days.
///
/// All meal log data is personal and stored in CloudKit private database.
struct MealLogView: View {
    @Environment(\.privateDataManager) private var privateDataManager
    @Query private var recipes: [Recipe]
    @Query private var mealSlots: [MealSlot]
    @Query private var users: [User]

    @State private var showQuickLogSheet = false
    @State private var logToEdit: PrivateMealLog?
    @State private var logToDelete: PrivateMealLog?
    @State private var showDeleteConfirmation = false
    /// Incremented to force re-render after log status changes.
    /// Needed because @Environment doesn't observe ObservableObject changes.
    @State private var logVersion: Int = 0

    private var currentUser: User? {
        users.first
    }

    private var weeklyLogs: [PrivateMealLog] {
        _ = logVersion // Force SwiftUI dependency on log changes
        return privateDataManager?.mealLogs ?? []
    }

    private var recipeLookup: SimpleRecipeLookup {
        SimpleRecipeLookup(recipes: recipes)
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
                                .font(.title2)
                            Text("Log a Meal")
                                .font(.headline)
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
                    await manager.syncPlannedMeals(slots: mealSlots, currentUser: user)
                }
            }
            .onReceive(privateDataManager?.objectWillChange.eraseToAnyPublisher() ?? Empty<Void, Never>().eraseToAnyPublisher()) { _ in
                logVersion += 1
            }
        }
    }

    // MARK: - Today Section

    private var todaySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Today")
                .font(.headline)
                .foregroundStyle(Theme.Colors.textPrimary)

            if todayLogs.isEmpty {
                Text("No meals logged yet today.")
                    .font(.subheadline)
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
                .font(.headline)
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
                .font(.system(size: 48))
                .foregroundStyle(Theme.Colors.textSecondary.opacity(0.5))

            Text("Your meal log is empty.")
                .font(.body)
                .foregroundStyle(Theme.Colors.textSecondary)

            Text("Tap \"Log a Meal\" to record what you eat. Over time, you'll see patterns in the Insights tab.")
                .font(.subheadline)
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

// MARK: - Planned Meal Row

/// Row for an auto-populated planned meal that hasn't been confirmed yet
struct PlannedMealRow: View {
    let log: PrivateMealLog
    let recipeLookup: RecipeMacroLookup
    let onConfirm: () -> Void
    let onSkip: () -> Void

    private var mealName: String {
        if let recipeID = log.recipeID,
           let name = recipeLookup.recipeName(for: recipeID) {
            return name
        } else if let quickName = log.quickLogName {
            return quickName
        }
        return "Planned meal"
    }

    private var mealTypeIcon: String {
        switch log.mealType {
        case .breakfast: return "sunrise"
        case .lunch: return "sun.max"
        case .dinner: return "moon.stars"
        case .snack: return "leaf"
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: mealTypeIcon)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.Colors.primary.opacity(0.6))
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(mealName)
                        .font(.subheadline)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(1)

                    Text("From plan")
                        .font(.caption2)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }

                Spacer()
            }

            HStack(spacing: 12) {
                Button(action: onConfirm) {
                    Text("Confirm")
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .foregroundStyle(.white)
                        .background(Theme.Colors.primary)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Button(action: onSkip) {
                    Text("Skip")
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .background(Color.systemGray6)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Spacer()
            }
            .padding(.leading, 36)
        }
        .padding(.vertical, 4)
        .background(Theme.Colors.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Skipped Meal Log Row

/// Row for a meal that was skipped - shown greyed out with strikethrough
struct SkippedMealLogRow: View {
    let log: PrivateMealLog
    let recipeLookup: RecipeMacroLookup

    private var mealName: String {
        if let recipeID = log.recipeID,
           let name = recipeLookup.recipeName(for: recipeID) {
            return name
        } else if let quickName = log.quickLogName {
            return quickName
        }
        return "Meal"
    }

    private var mealTypeIcon: String {
        switch log.mealType {
        case .breakfast: return "sunrise"
        case .lunch: return "sun.max"
        case .dinner: return "moon.stars"
        case .snack: return "leaf"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: mealTypeIcon)
                .font(.system(size: 14))
                .foregroundStyle(Theme.Colors.textSecondary.opacity(0.5))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(mealName)
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .strikethrough()
                    .lineLimit(1)

                Text("Skipped")
                    .font(.caption2)
                    .foregroundStyle(Theme.Colors.textSecondary.opacity(0.7))
            }

            Spacer()
        }
        .opacity(0.6)
        .padding(.vertical, 2)
    }
}

// MARK: - Meal Log Editor Sheet

/// Sheet for editing an existing meal log entry
struct MealLogEditorSheet: View {
    let log: PrivateMealLog
    var privateDataManager: PrivateDataManager?

    @Environment(\.dismiss) private var dismiss

    @State private var mealType: MealType
    @State private var servingsConsumed: Double
    @State private var quickLogName: String
    @State private var quickLogCalories: String
    @State private var quickLogProtein: String
    @State private var quickLogCarbs: String
    @State private var quickLogFat: String
    @State private var status: MealLogStatus

    init(log: PrivateMealLog, privateDataManager: PrivateDataManager?) {
        self.log = log
        self.privateDataManager = privateDataManager
        _mealType = State(initialValue: log.mealType)
        _servingsConsumed = State(initialValue: log.servingsConsumed)
        _quickLogName = State(initialValue: log.quickLogName ?? "")
        _quickLogCalories = State(initialValue: log.quickLogCalories.map { String($0) } ?? "")
        _quickLogProtein = State(initialValue: log.quickLogProtein.map { String($0) } ?? "")
        _quickLogCarbs = State(initialValue: log.quickLogCarbs.map { String($0) } ?? "")
        _quickLogFat = State(initialValue: log.quickLogFat.map { String($0) } ?? "")
        _status = State(initialValue: log.status)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Meal Type") {
                    Picker("Meal", selection: $mealType) {
                        ForEach(MealType.allCases, id: \.self) { type in
                            Text(type.rawValue.capitalized).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Status") {
                    Picker("Status", selection: $status) {
                        Text("Eaten").tag(MealLogStatus.consumed)
                        Text("Skipped").tag(MealLogStatus.skipped)
                    }
                    .pickerStyle(.segmented)
                }

                if log.isQuickLog {
                    Section("Meal Name") {
                        TextField("Meal name", text: $quickLogName)
                    }

                    Section("Nutrition") {
                        HStack {
                            Text("Calories")
                            Spacer()
                            TextField("cal", text: $quickLogCalories)
                                .multilineTextAlignment(.trailing)
                                #if os(iOS)
                                .keyboardType(.numberPad)
                                #endif
                                .frame(width: 80)
                        }
                        HStack {
                            Text("Protein (g)")
                            Spacer()
                            TextField("g", text: $quickLogProtein)
                                .multilineTextAlignment(.trailing)
                                #if os(iOS)
                                .keyboardType(.numberPad)
                                #endif
                                .frame(width: 80)
                        }
                        HStack {
                            Text("Carbs (g)")
                            Spacer()
                            TextField("g", text: $quickLogCarbs)
                                .multilineTextAlignment(.trailing)
                                #if os(iOS)
                                .keyboardType(.numberPad)
                                #endif
                                .frame(width: 80)
                        }
                        HStack {
                            Text("Fat (g)")
                            Spacer()
                            TextField("g", text: $quickLogFat)
                                .multilineTextAlignment(.trailing)
                                #if os(iOS)
                                .keyboardType(.numberPad)
                                #endif
                                .frame(width: 80)
                        }
                    }
                } else {
                    Section("Servings") {
                        HStack {
                            Text("Servings eaten")
                            Spacer()
                            #if os(iOS)
                            Stepper(
                                value: $servingsConsumed,
                                in: 0.25...10,
                                step: 0.25
                            ) {
                                Text(String(format: "%.2g", servingsConsumed))
                                    .foregroundStyle(.secondary)
                            }
                            #else
                            HStack(spacing: 12) {
                                Button { if servingsConsumed > 0.25 { servingsConsumed -= 0.25 } } label: {
                                    Image(systemName: "minus.circle.fill")
                                }
                                .buttonStyle(.plain)
                                Text(String(format: "%.2g", servingsConsumed))
                                Button { if servingsConsumed < 10 { servingsConsumed += 0.25 } } label: {
                                    Image(systemName: "plus.circle.fill")
                                }
                                .buttonStyle(.plain)
                            }
                            #endif
                        }
                    }
                }
            }
            .navigationTitle("Edit Entry")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveChanges()
                        dismiss()
                    }
                }
            }
        }
    }

    private func saveChanges() {
        var updated = log
        updated.mealType = mealType
        updated.servingsConsumed = servingsConsumed
        updated.status = status

        if log.isQuickLog {
            updated.quickLogName = quickLogName.isEmpty ? nil : quickLogName
            updated.quickLogCalories = Int(quickLogCalories)
            updated.quickLogProtein = Int(quickLogProtein)
            updated.quickLogCarbs = Int(quickLogCarbs)
            updated.quickLogFat = Int(quickLogFat)
        }

        Task {
            await privateDataManager?.saveMealLog(updated)
        }
    }
}

#Preview {
    MealLogView()
        .modelContainer(for: [Recipe.self, MealSlot.self, User.self], inMemory: true)
}
