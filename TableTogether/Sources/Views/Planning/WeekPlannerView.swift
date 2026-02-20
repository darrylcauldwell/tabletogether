import SwiftUI
import SwiftData

// MARK: - WeekPlannerView

/// Main planning interface showing a week's meal plan with drag and drop support.
/// Adapts layout for iPad (full week view) vs iPhone (scrollable day-by-day).
struct WeekPlannerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.sharingCoordinator) private var sharingCoordinator

    @Query(sort: \WeekPlan.weekStartDate, order: .reverse) private var weekPlans: [WeekPlan]
    @Query private var recipes: [Recipe]
    @Query private var suggestionMemories: [SuggestionMemory]
    @Query private var users: [User]
    @Query private var households: [Household]

    @State private var currentWeekStart: Date = WeekPlannerView.mondayOfCurrentWeek()
    @State private var isSuggestionTrayExpanded: Bool = true
    @State private var selectedDayIndex: Int = 0
    @State private var showingRecentChanges: Bool = false

    private var currentUser: User? {
        users.first // In production, would be based on CloudKit identity
    }

    private var currentWeekPlan: WeekPlan? {
        weekPlans.first { Calendar.current.isDate($0.weekStartDate, inSameDayAs: currentWeekStart) }
    }

    var body: some View {
        VStack(spacing: 0) {
            WeekHeaderView(
                weekStartDate: $currentWeekStart,
                status: currentWeekPlan?.status ?? .draft,
                onPreviousWeek: navigateToPreviousWeek,
                onNextWeek: navigateToNextWeek
            )

            // Recent Changes Banner
            if let coordinator = sharingCoordinator, !coordinator.recentChanges.isEmpty {
                RecentChangesBanner(
                    changes: coordinator.recentChanges,
                    isExpanded: $showingRecentChanges
                )
            }

            Divider()

            if horizontalSizeClass == .regular {
                // iPad: Full week grid view
                WeekGridView(
                    weekPlan: currentWeekPlan,
                    weekStartDate: currentWeekStart,
                    onSlotTapped: handleSlotTapped,
                    onRecipeDropped: handleRecipeDropped
                )
            } else {
                // iPhone: Day-by-day scrollable view
                DayByDayView(
                    weekPlan: currentWeekPlan,
                    weekStartDate: currentWeekStart,
                    selectedDayIndex: $selectedDayIndex,
                    onSlotTapped: handleSlotTapped,
                    onRecipeDropped: handleRecipeDropped
                )
            }

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
        .navigationTitle("Meal Plan")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear {
            ensureWeekPlanExists()
        }
    }

    // MARK: - Computed Properties

    private var suggestedFamiliarRecipes: [Recipe] {
        let engine = SuggestionEngine()
        let result = engine.suggestRecipes(
            allRecipes: recipes,
            weekPlan: currentWeekPlan,
            memory: suggestionMemories
        )
        return result.familiarSuggestions
    }

    private var suggestedNewRecipes: [Recipe] {
        let engine = SuggestionEngine()
        let result = engine.suggestRecipes(
            allRecipes: recipes,
            weekPlan: currentWeekPlan,
            memory: suggestionMemories
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
            ensureWeekPlanExists()
        }
    }

    private func navigateToNextWeek() {
        if let newDate = Calendar.current.date(byAdding: .weekOfYear, value: 1, to: currentWeekStart) {
            currentWeekStart = newDate
            ensureWeekPlanExists()
        }
    }

    private func ensureWeekPlanExists() {
        guard currentWeekPlan == nil else { return }

        let newPlan = WeekPlan(
            weekStartDate: currentWeekStart,
            householdNote: nil,
            status: .draft
        )

        // Create default meal slots for each day and meal type
        for day in DayOfWeek.allCases {
            for mealType in MealType.allCases {
                let slot = MealSlot(
                    dayOfWeek: day,
                    mealType: mealType,
                    servingsPlanned: 2
                )
                slot.weekPlan = newPlan
                newPlan.slots.append(slot)
            }
        }

        newPlan.household = households.first
        modelContext.insert(newPlan)
        modelContext.saveWithLogging(context: "new week plan")
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
        slot.recipes.append(recipe)
        slot.customMealName = nil
        slot.modifiedAt = Date()
        modelContext.saveWithLogging(context: "recipe drop to slot")
    }

    private func copyFromLastWeek() {
        guard let previousWeekStart = Calendar.current.date(byAdding: .weekOfYear, value: -1, to: currentWeekStart),
              let previousPlan = weekPlans.first(where: { Calendar.current.isDate($0.weekStartDate, inSameDayAs: previousWeekStart) }),
              let currentPlan = currentWeekPlan else { return }

        for previousSlot in previousPlan.slots {
            if let currentSlot = currentPlan.slots.first(where: { $0.dayOfWeek == previousSlot.dayOfWeek && $0.mealType == previousSlot.mealType }) {
                currentSlot.recipes = previousSlot.recipes
                currentSlot.archetype = previousSlot.archetype
                currentSlot.customMealName = previousSlot.customMealName
                currentSlot.servingsPlanned = previousSlot.servingsPlanned
                currentSlot.modifiedAt = Date()
            }
        }

        modelContext.saveWithLogging(context: "copy from last week")
    }

    private func clearWeek() {
        guard let weekPlan = currentWeekPlan else { return }

        for slot in weekPlan.slots {
            slot.recipes = []
            slot.archetype = nil
            slot.customMealName = nil
            slot.modifiedAt = Date()
        }

        modelContext.saveWithLogging(context: "clear week")
    }
}

// MARK: - WeekHeaderView

/// Header with week navigation controls
struct WeekHeaderView: View {
    @Binding var weekStartDate: Date
    let status: WeekPlanStatus
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
                    .font(.title3)
                    .foregroundColor(.accentColor)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)

            Spacer()

            VStack(spacing: 2) {
                Text(weekLabel)
                    .font(.headline)

                WeekStatusBadge(status: status)
            }

            Spacer()

            Button(action: onNextWeek) {
                Image(systemName: "chevron.right")
                    .font(.title3)
                    .foregroundColor(.accentColor)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
        }
        .padding(.vertical, 12)
        .padding(.horizontal)
    }
}

// MARK: - WeekStatusBadge

struct WeekStatusBadge: View {
    let status: WeekPlanStatus

    private var statusColor: Color {
        switch status {
        case .draft: return .orange
        case .active: return .green
        case .completed: return .gray
        }
    }

    private var statusLabel: String {
        switch status {
        case .draft: return "Draft"
        case .active: return "Active"
        case .completed: return "Completed"
        }
    }

    var body: some View {
        Text(statusLabel)
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundColor(statusColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(statusColor.opacity(0.15))
            .clipShape(Capsule())
    }
}

// MARK: - WeekGridView

/// Full week grid view for iPad landscape
struct WeekGridView: View {
    let weekPlan: WeekPlan?
    let weekStartDate: Date
    let onSlotTapped: (MealSlot) -> Void
    let onRecipeDropped: (String, MealSlot) -> Void  // Receives recipe UUID string

    private var weekdays: [DayOfWeek] {
        Array(DayOfWeek.allCases.prefix(5)) // Mon–Fri
    }

    private var weekend: [DayOfWeek] {
        Array(DayOfWeek.allCases.suffix(2)) // Sat–Sun
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Weekdays: Mon–Fri
                HStack(alignment: .top, spacing: 8) {
                    ForEach(weekdays, id: \.self) { day in
                        DayColumnView(
                            day: day,
                            weekStartDate: weekStartDate,
                            slots: slotsForDay(day),
                            onSlotTapped: onSlotTapped,
                            onRecipeDropped: onRecipeDropped
                        )
                        .frame(maxWidth: .infinity)
                    }
                }

                // Weekend: Sat–Sun (same column width as weekdays)
                HStack(alignment: .top, spacing: 8) {
                    ForEach(weekend, id: \.self) { day in
                        DayColumnView(
                            day: day,
                            weekStartDate: weekStartDate,
                            slots: slotsForDay(day),
                            onSlotTapped: onSlotTapped,
                            onRecipeDropped: onRecipeDropped
                        )
                        .frame(maxWidth: .infinity)
                    }
                    // 3 invisible columns to keep weekend day widths equal to weekday widths
                    ForEach(0..<3, id: \.self) { _ in
                        Color.clear.frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
        }
    }

    private func slotsForDay(_ day: DayOfWeek) -> [MealSlot] {
        weekPlan?.slots.filter { $0.dayOfWeek == day }.sorted { $0.mealType.rawValue < $1.mealType.rawValue } ?? []
    }
}

// MARK: - DayByDayView

/// Scrollable day-by-day view for iPhone
struct DayByDayView: View {
    let weekPlan: WeekPlan?
    let weekStartDate: Date
    @Binding var selectedDayIndex: Int
    let onSlotTapped: (MealSlot) -> Void
    let onRecipeDropped: (String, MealSlot) -> Void  // Receives recipe UUID string

    var body: some View {
        VStack(spacing: 0) {
            // Day selector
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(Array(DayOfWeek.allCases.enumerated()), id: \.element) { index, day in
                            DayTabButton(
                                day: day,
                                weekStartDate: weekStartDate,
                                isSelected: selectedDayIndex == index,
                                hasContent: slotsForDay(day).contains { !$0.recipes.isEmpty || $0.customMealName != nil }
                            ) {
                                withAnimation {
                                    selectedDayIndex = index
                                }
                            }
                            .id(index)
                        }
                    }
                    .padding(.horizontal)
                }
                .onChange(of: selectedDayIndex) { _, newValue in
                    withAnimation {
                        proxy.scrollTo(newValue, anchor: .center)
                    }
                }
            }
            .padding(.vertical, 8)

            Divider()

            // Day content
            TabView(selection: $selectedDayIndex) {
                ForEach(Array(DayOfWeek.allCases.enumerated()), id: \.element) { index, day in
                    ScrollView {
                        DayColumnView(
                            day: day,
                            weekStartDate: weekStartDate,
                            slots: slotsForDay(day),
                            onSlotTapped: onSlotTapped,
                            onRecipeDropped: onRecipeDropped
                        )
                        .padding()
                    }
                    .tag(index)
                }
            }
            #if os(iOS)
            .tabViewStyle(.page(indexDisplayMode: .never))
            #endif
        }
    }

    private func slotsForDay(_ day: DayOfWeek) -> [MealSlot] {
        weekPlan?.slots.filter { $0.dayOfWeek == day }.sorted { $0.mealType.rawValue < $1.mealType.rawValue } ?? []
    }
}

// MARK: - DayTabButton

struct DayTabButton: View {
    let day: DayOfWeek
    let weekStartDate: Date
    let isSelected: Bool
    let hasContent: Bool
    let action: () -> Void

    private var dateForDay: Date {
        Calendar.current.date(byAdding: .day, value: day.rawValue - 1, to: weekStartDate) ?? weekStartDate
    }

    private var dayNumber: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: dateForDay)
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(day.shortName)
                    .font(.caption)
                    .fontWeight(isSelected ? .semibold : .regular)

                Text(dayNumber)
                    .font(.body)
                    .fontWeight(isSelected ? .semibold : .regular)

                if hasContent {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 6, height: 6)
                } else {
                    Circle()
                        .fill(Color.clear)
                        .frame(width: 6, height: 6)
                }
            }
            .foregroundColor(isSelected ? .accentColor : .primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
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

// MARK: - RecentChangesBanner

/// Expandable banner showing recent changes from other household members
struct RecentChangesBanner: View {
    let changes: [HouseholdChange]
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Header row
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "person.2.fill")
                        .foregroundColor(.orange)

                    if let latestChange = changes.first {
                        Text("\(latestChange.userName) \(latestChange.description)")
                            .font(.subheadline)
                            .foregroundColor(.primary)
                            .lineLimit(1)

                        Text(latestChange.timeAgo)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    if changes.count > 1 {
                        Text("+\(changes.count - 1)")
                            .font(.caption)
                            .foregroundColor(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.15))
                            .clipShape(Capsule())
                    }

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.1))
            }
            .buttonStyle(.plain)

            // Expanded change list
            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(changes) { change in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Color.orange)
                                .frame(width: 6, height: 6)

                            Text(change.userName)
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.primary)

                            Text(change.description)
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Spacer()

                            Text(change.timeAgo)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 6)
                    }
                }
                .background(Color.orange.opacity(0.05))
            }
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        WeekPlannerView()
    }
    .modelContainer(for: [WeekPlan.self, Recipe.self, MealSlot.self, SuggestionMemory.self], inMemory: true)
}
