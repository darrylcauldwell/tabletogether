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
        users.first // In production, would be based on CloudKit identity
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
                onRecipeDropped: handleRecipeDropped
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
        .onAppear {
            ensureWeekPlanExists()
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
            context: viewContext,
            weekStartDate: currentWeekStart,
            householdNote: nil
        )

        // Use the shared helper which generates deterministic slot IDs
        newPlan.createDefaultSlots(context: viewContext)
        newPlan.household = households.first
        viewContext.saveWithLogging(context: "new week plan")
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
              let currentPlan = currentWeekPlan else { return }

        for previousSlot in previousPlan.slotsArray {
            if let currentSlot = currentPlan.slotsArray.first(where: { $0.dayOfWeek == previousSlot.dayOfWeek && $0.mealType == previousSlot.mealType }) {
                currentSlot.recipes = previousSlot.recipes
                currentSlot.archetype = previousSlot.archetype
                currentSlot.customMealName = previousSlot.customMealName
                currentSlot.servingsPlanned = previousSlot.servingsPlanned
                currentSlot.modifiedAt = Date()
            }
        }

        viewContext.saveWithLogging(context: "copy from last week")
    }

    private func clearWeek() {
        guard let weekPlan = currentWeekPlan else { return }

        for slot in weekPlan.slotsArray {
            slot.recipes = NSSet()
            slot.archetype = nil
            slot.customMealName = nil
            slot.modifiedAt = Date()
        }

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
        weekPlan?.slotsArray.filter { $0.dayOfWeek == day }.sorted { $0.mealType.rawValue < $1.mealType.rawValue } ?? []
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
                                hasContent: slotsForDay(day).contains { !$0.recipesArray.isEmpty || $0.customMealName != nil }
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
        weekPlan?.slotsArray.filter { $0.dayOfWeek == day }.sorted { $0.mealType.rawValue < $1.mealType.rawValue } ?? []
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
                    .font(AppTypography.caption)
                    .fontWeight(isSelected ? .semibold : .regular)

                Text(dayNumber)
                    .font(AppTypography.body)
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

// MARK: - Preview

#Preview {
    NavigationStack {
        WeekPlannerView()
    }
    .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
}
