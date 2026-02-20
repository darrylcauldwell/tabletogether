import SwiftUI
import SwiftData
import Charts
import HealthKit

/// Main insights screen showing personal macro tracking with calm, positive language.
/// Follows progressive disclosure: summary by default, detail on demand.
///
/// Note: This view shows ONLY the current user's personal data.
/// All meal logs and goals are stored in CloudKit private database
/// and are never shared with other household members.
struct InsightsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.privateDataManager) private var privateDataManager
    @StateObject private var healthService = HealthKitService.shared

    @Query private var users: [User]
    @Query private var recipes: [Recipe]

    @State private var showExpandedDailyView = false
    @State private var showHealthKitSection = false

    /// Current user (for display purposes only - avatar shown in toolbar)
    private var currentUser: User? {
        users.first // In a real app, would match CloudKit identity
    }

    /// Personal settings from private storage
    private var settings: PersonalSettings {
        privateDataManager?.settings ?? PersonalSettings()
    }

    /// Meal logs from private storage
    private var weeklyLogs: [PrivateMealLog] {
        privateDataManager?.mealLogs ?? []
    }

    /// Recipe lookup for macro calculations
    private var recipeLookup: SimpleRecipeLookup {
        SimpleRecipeLookup(recipes: recipes)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Apple Health integration card
                    HealthKitCard(healthService: healthService)
                        .padding(.horizontal)

                    // Weekly trend card (default view)
                    WeeklyTrendCard(
                        mealLogs: weeklyLogs,
                        recipeLookup: recipeLookup,
                        onTap: {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                showExpandedDailyView.toggle()
                            }
                        }
                    )
                    .padding(.horizontal)

                    // Expanded daily view (on tap)
                    if showExpandedDailyView {
                        ExpandedDailyView(
                            mealLogs: weeklyLogs,
                            recipeLookup: recipeLookup
                        )
                        .padding(.horizontal)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    // Goals card (only if user has goals set)
                    if settings.hasGoalsSet {
                        GoalsCard(
                            settings: settings,
                            weeklyLogs: weeklyLogs,
                            recipeLookup: recipeLookup
                        )
                        .padding(.horizontal)
                    }

                    // Calorie estimate card (when HealthKit data is available)
                    if healthService.isAuthorized && healthService.estimatedDailyCalories != nil {
                        CalorieEstimateCard(healthService: healthService)
                            .padding(.horizontal)
                    }

                    // Empty state
                    if weeklyLogs.isEmpty && !healthService.isAuthorized {
                        EmptyInsightsView()
                            .padding(.horizontal)
                    }

                    Spacer(minLength: 20)
                }
                .padding(.vertical)
            }
            .background(Theme.Colors.background)
            .navigationTitle("Insights")
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .topBarTrailing) {
                    if let user = currentUser {
                        Menu {
                            Text(user.displayName)
                        } label: {
                            UserAvatarView(user: user, size: 32)
                        }
                    }
                }
                #else
                ToolbarItem(placement: .automatic) {
                    if let user = currentUser {
                        Menu {
                            Text(user.displayName)
                        } label: {
                            UserAvatarView(user: user, size: 32)
                        }
                    }
                }
                #endif
            }
            .task {
                await privateDataManager?.fetchCurrentWeekLogs()
                await privateDataManager?.fetchSettings()
            }
        }
    }
}

// MARK: - Simple Recipe Lookup

/// Simple implementation of RecipeMacroLookup using an array of recipes
struct SimpleRecipeLookup: RecipeMacroLookup {
    let recipes: [Recipe]

    func macrosPerServing(for recipeID: UUID) -> MacroSummary? {
        recipes.first(where: { $0.id == recipeID })?.macrosPerServing
    }

    func recipeName(for recipeID: UUID) -> String? {
        recipes.first(where: { $0.id == recipeID })?.title
    }
}

// MARK: - Expanded Daily View

struct ExpandedDailyView: View {
    let mealLogs: [PrivateMealLog]
    let recipeLookup: RecipeMacroLookup

    private var logsByDay: [Date: [PrivateMealLog]] {
        let calendar = Calendar.current
        var grouped: [Date: [PrivateMealLog]] = [:]

        for log in mealLogs {
            let day = calendar.startOfDay(for: log.date)
            grouped[day, default: []].append(log)
        }

        return grouped
    }

    private var sortedDays: [Date] {
        logsByDay.keys.sorted()
    }

    var body: some View {
        VStack(spacing: 16) {
            ForEach(sortedDays, id: \.self) { day in
                DayDetailCard(
                    date: day,
                    mealLogs: logsByDay[day] ?? [],
                    recipeLookup: recipeLookup
                )
            }
        }
    }
}

// MARK: - Goals Card

struct GoalsCard: View {
    let settings: PersonalSettings
    let weeklyLogs: [PrivateMealLog]
    let recipeLookup: RecipeMacroLookup

    private func calculateAverage(extractor: (PrivateMealLog) -> Int?) -> Int {
        guard !weeklyLogs.isEmpty else { return 0 }
        let total = weeklyLogs.compactMap(extractor).reduce(0, +)
        let days = Set(weeklyLogs.map { Calendar.current.startOfDay(for: $0.date) }).count
        return days > 0 ? total / days : 0
    }

    private var averageDailyCalories: Int {
        calculateAverage { log in
            if let cal = log.quickLogCalories { return cal }
            if let recipeID = log.recipeID,
               let macros = recipeLookup.macrosPerServing(for: recipeID),
               let cal = macros.calories {
                return Int(cal * log.servingsConsumed)
            }
            return nil
        }
    }

    private var averageDailyProtein: Int {
        calculateAverage { log in
            if let prot = log.quickLogProtein { return prot }
            if let recipeID = log.recipeID,
               let macros = recipeLookup.macrosPerServing(for: recipeID),
               let prot = macros.protein {
                return Int(prot * log.servingsConsumed)
            }
            return nil
        }
    }

    private var averageDailyCarbs: Int {
        calculateAverage { log in
            if let carbs = log.quickLogCarbs { return carbs }
            if let recipeID = log.recipeID,
               let macros = recipeLookup.macrosPerServing(for: recipeID),
               let carbs = macros.carbs {
                return Int(carbs * log.servingsConsumed)
            }
            return nil
        }
    }

    private var averageDailyFat: Int {
        calculateAverage { log in
            if let fat = log.quickLogFat { return fat }
            if let recipeID = log.recipeID,
               let macros = recipeLookup.macrosPerServing(for: recipeID),
               let fat = macros.fat {
                return Int(fat * log.servingsConsumed)
            }
            return nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Your averages")
                .font(.headline)
                .foregroundStyle(Color.charcoal)

            VStack(spacing: 12) {
                if let target = settings.dailyCalorieTarget {
                    GoalProgressRow(
                        label: "Calories",
                        current: averageDailyCalories,
                        target: target,
                        unit: "cal"
                    )
                }

                if let target = settings.dailyProteinTarget {
                    GoalProgressRow(
                        label: "Protein",
                        current: averageDailyProtein,
                        target: target,
                        unit: "g"
                    )
                }

                if let target = settings.dailyCarbTarget {
                    GoalProgressRow(
                        label: "Carbs",
                        current: averageDailyCarbs,
                        target: target,
                        unit: "g"
                    )
                }

                if let target = settings.dailyFatTarget {
                    GoalProgressRow(
                        label: "Fat",
                        current: averageDailyFat,
                        target: target,
                        unit: "g"
                    )
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.offWhite)
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
        )
    }
}

struct GoalProgressRow: View {
    let label: String
    let current: Int
    let target: Int
    let unit: String

    private var progress: Double {
        guard target > 0 else { return 0 }
        return min(Double(current) / Double(target), 1.5)
    }

    private var progressDescription: String {
        let percentage = Int((Double(current) / Double(target)) * 100)
        if percentage < 85 {
            return "Light"
        } else if percentage > 115 {
            return "Hearty"
        } else {
            return "Steady"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(Color.charcoal)

                Spacer()

                Text("\(current) / \(target) \(unit)")
                    .font(.caption)
                    .foregroundStyle(Color.slateGray)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.softBlue.opacity(0.3))

                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.softGreen)
                        .frame(width: geometry.size.width * min(progress, 1.0))
                }
            }
            .frame(height: 8)

            Text(progressDescription)
                .font(.caption2)
                .foregroundStyle(Color.slateGray)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(current) of \(target) \(unit). \(progressDescription) intake.")
    }
}

// MARK: - Empty State

struct EmptyInsightsView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 48))
                .foregroundStyle(Theme.Colors.textSecondary.opacity(0.5))

            Text("Start logging meals to see your eating patterns here.")
                .font(.body)
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
}

// MARK: - Apple Health Card

/// Card for connecting to Apple Health and displaying synced body metrics
struct HealthKitCard: View {
    @ObservedObject var healthService: HealthKitService

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with Apple Health branding
            HStack(spacing: 10) {
                Image(systemName: "heart.fill")
                    .font(.title2)
                    .foregroundStyle(.red)

                Text("Apple Health")
                    .font(.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)

                Spacer()

                if healthService.isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }

            if healthService.isAuthorized {
                // Show synced data
                VStack(alignment: .leading, spacing: 8) {
                    if let weight = healthService.weightInPounds {
                        HealthMetricRow(
                            icon: "scalemass",
                            label: "Weight",
                            value: String(format: "%.1f lbs", weight)
                        )
                    }

                    if let height = healthService.heightInFeetAndInches {
                        HealthMetricRow(
                            icon: "ruler",
                            label: "Height",
                            value: "\(height.feet)' \(height.inches)\""
                        )
                    }

                    if let age = healthService.age {
                        HealthMetricRow(
                            icon: "calendar",
                            label: "Age",
                            value: "\(age) years"
                        )
                    }

                    // Refresh button
                    Button {
                        Task {
                            await healthService.fetchAllHealthData()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.clockwise")
                            Text("Refresh")
                        }
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.primary)
                    }
                    .padding(.top, 4)
                }

                if healthService.latestWeight == nil && healthService.latestHeight == nil {
                    Text("No health data found. Add your weight and height in the Health app.")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .padding(.top, 4)
                }
            } else {
                // Not connected - show connect prompt
                VStack(alignment: .leading, spacing: 12) {
                    Text("Connect to sync your weight and height for personalized calorie estimates. Meal logs will also be saved to Health.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.Colors.textSecondary)

                    Button {
                        Task {
                            await healthService.requestAuthorization()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "heart.circle.fill")
                            Text("Connect to Health")
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.red.opacity(0.9))
                        )
                    }
                }
            }

            if let error = healthService.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Theme.Colors.cardBackground)
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
        )
    }
}

/// Single row for a health metric
struct HealthMetricRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(width: 20)

            Text(label)
                .font(.subheadline)
                .foregroundStyle(Theme.Colors.textSecondary)

            Spacer()

            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.Colors.textPrimary)
        }
    }
}

// MARK: - Calorie Estimate Card

/// Shows estimated daily calorie needs based on HealthKit data
struct CalorieEstimateCard: View {
    @ObservedObject var healthService: HealthKitService

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your estimated needs")
                .font(.headline)
                .foregroundStyle(Theme.Colors.textPrimary)

            if let bmr = healthService.estimatedBMR,
               let dailyCal = healthService.estimatedDailyCalories {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Basal Metabolic Rate")
                                .font(.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                            Text("\(bmr) cal/day")
                                .font(.title3.weight(.medium))
                                .foregroundStyle(Theme.Colors.textPrimary)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Maintenance")
                                .font(.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                            Text("~\(dailyCal) cal/day")
                                .font(.title3.weight(.medium))
                                .foregroundStyle(Theme.Colors.primary)
                        }
                    }

                    Text("Based on your weight, height, age, and sedentary activity. Adjust based on your actual activity level.")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .padding(.top, 4)
                }
            } else {
                Text("Add your weight, height, and date of birth in the Health app to see personalized estimates.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Theme.Colors.cardBackground)
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
        )
    }
}

// MARK: - Adaptive Color Extensions for Insights
// These colors adapt to light/dark mode using Theme.Colors

extension Color {
    /// Primary accent - Sage Green (same in both modes)
    static let sageGreen = Theme.Colors.primary

    /// Secondary accent - Warm Orange (same in both modes)
    static let warmOrange = Theme.Colors.secondary

    /// Card/surface background - adapts to mode
    static let offWhite = Theme.Colors.cardBackground

    /// Primary text - adapts to mode
    static let charcoal = Theme.Colors.textPrimary

    /// Secondary text - adapts to mode
    static let slateGray = Theme.Colors.textSecondary

    /// Positive accent (same in both modes)
    static let softGreen = Theme.Colors.positive

    /// Neutral accent (same in both modes)
    static let softBlue = Theme.Colors.neutral
}

#Preview {
    InsightsView()
        .modelContainer(for: [User.self, Recipe.self], inMemory: true)
}
