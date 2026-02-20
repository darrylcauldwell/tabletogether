import SwiftUI
import SwiftData

// MARK: - Ambient View ("What's for TableTogether?")
//
// The primary tvOS experience. Shows today's planned meals
// in a calm, glanceable layout designed to reduce decision fatigue.
//
// Design goals:
// - Readable from across the room
// - No pressure, no judgment
// - Encourages conversation
// - Shows household presence

struct AmbientView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var users: [User]

    @State private var weekPlan: WeekPlan?
    @State private var todaySlots: [MealSlot] = []
    @State private var selectedSlot: MealSlot?
    @State private var showingRecipeView = false
    @State private var currentTime = Date()

    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private var today: DayOfWeek {
        let weekday = Calendar.current.component(.weekday, from: Date())
        // Convert Sunday=1...Saturday=7 to Monday=1...Sunday=7
        let adjusted = weekday == 1 ? 7 : weekday - 1
        return DayOfWeek(rawValue: adjusted) ?? .monday
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: currentTime)
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<21: return "Good evening"
        default: return "Hello"
        }
    }

    private var nextMeal: MealSlot? {
        let hour = Calendar.current.component(.hour, from: currentTime)
        return todaySlots.first { slot in
            switch slot.mealType {
            case .breakfast: return hour < 10
            case .lunch: return hour < 14
            case .dinner: return hour < 20
            case .snack: return hour < 16
            }
        }
    }

    private var timeUntilNextMeal: String? {
        guard let meal = nextMeal else { return nil }

        let hour = Calendar.current.component(.hour, from: currentTime)
        let targetHour: Int

        switch meal.mealType {
        case .breakfast: targetHour = 8
        case .lunch: targetHour = 12
        case .dinner: targetHour = 18
        case .snack: targetHour = 15
        }

        let hoursUntil = targetHour - hour
        if hoursUntil <= 0 { return nil }
        if hoursUntil == 1 { return "in 1 hour" }
        return "in \(hoursUntil) hours"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Background gradient
                LinearGradient(
                    colors: [
                        TVTheme.Colors.background,
                        TVTheme.Colors.backgroundElevated
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Header with greeting and household
                    headerSection
                        .padding(.bottom, TVTheme.Spacing.lg)

                    // Main content
                    HStack(alignment: .top, spacing: TVTheme.Spacing.xl) {
                        // Today's meals (main focus)
                        todayMealsSection
                            .frame(maxWidth: .infinity)

                        // Sidebar: Next meal countdown & reactions
                        sidebarSection
                            .frame(width: 400)
                    }

                    Spacer()

                    // Footer with navigation hint
                    footerSection
                }
                .tvSafeArea()
            }
            .navigationDestination(isPresented: $showingRecipeView) {
                if let slot = selectedSlot, let recipe = slot.recipes.first {
                    RecipeView(recipe: recipe, mealSlot: slot)
                }
            }
        }
        .onAppear {
            loadTodaysMeals()
        }
        .onReceive(timer) { _ in
            currentTime = Date()
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: TVTheme.Spacing.sm) {
                Text(greeting)
                    .font(TVTheme.Typography.hero)
                    .foregroundStyle(TVTheme.Colors.textPrimary)

                Text(today.fullName)
                    .font(TVTheme.Typography.title)
                    .foregroundStyle(TVTheme.Colors.textSecondary)
            }

            Spacer()

            // Household presence
            if !users.isEmpty {
                householdPresence
            }
        }
    }

    private var householdPresence: some View {
        VStack(alignment: .trailing, spacing: TVTheme.Spacing.sm) {
            Text("Household")
                .font(TVTheme.Typography.subheadline)
                .foregroundStyle(TVTheme.Colors.textTertiary)

            HStack(spacing: TVTheme.Spacing.md) {
                ForEach(users.prefix(5)) { user in
                    TVUserAvatar(user: user, size: 64, showName: false)
                }
            }
        }
    }

    // MARK: - Today's Meals Section

    private var todayMealsSection: some View {
        VStack(alignment: .leading, spacing: TVTheme.Spacing.lg) {
            Text("Today's Meals")
                .font(TVTheme.Typography.title2)
                .foregroundStyle(TVTheme.Colors.textSecondary)

            if todaySlots.isEmpty {
                TVEmptyState(
                    icon: "fork.knife",
                    title: "No meals planned",
                    message: "Open TableTogether on your iPhone or iPad to plan today's meals."
                )
                .frame(height: 400)
            } else {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: TVTheme.Spacing.lg),
                        GridItem(.flexible(), spacing: TVTheme.Spacing.lg)
                    ],
                    spacing: TVTheme.Spacing.lg
                ) {
                    ForEach(todaySlots.sorted { $0.mealType.sortOrder < $1.mealType.sortOrder }) { slot in
                        TVMealCard(mealSlot: slot) {
                            if !slot.recipes.isEmpty {
                                selectedSlot = slot
                                showingRecipeView = true
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Sidebar Section

    private var sidebarSection: some View {
        VStack(spacing: TVTheme.Spacing.xl) {
            // Next meal countdown
            if let meal = nextMeal, let timeUntil = timeUntilNextMeal {
                TVGlassCard {
                    VStack(spacing: TVTheme.Spacing.md) {
                        Text("Up Next")
                            .font(TVTheme.Typography.subheadline)
                            .foregroundStyle(TVTheme.Colors.textSecondary)

                        Text(meal.displayTitle)
                            .font(TVTheme.Typography.headline)
                            .foregroundStyle(TVTheme.Colors.textPrimary)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)

                        Text(timeUntil)
                            .font(TVTheme.Typography.timerSmall)
                            .foregroundStyle(TVTheme.Colors.primary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            // Quick reactions (for soft collaboration)
            TVGlassCard {
                VStack(spacing: TVTheme.Spacing.md) {
                    Text("Quick Reactions")
                        .font(TVTheme.Typography.subheadline)
                        .foregroundStyle(TVTheme.Colors.textSecondary)

                    HStack(spacing: TVTheme.Spacing.md) {
                        TVReactionButton(emoji: "👍", count: 0, isSelected: false) { }
                        TVReactionButton(emoji: "😋", count: 0, isSelected: false) { }
                        TVReactionButton(emoji: "🤔", count: 0, isSelected: false) { }
                    }

                    Text("Express your feelings about today's plan")
                        .font(TVTheme.Typography.caption)
                        .foregroundStyle(TVTheme.Colors.textTertiary)
                        .multilineTextAlignment(.center)
                }
            }

            Spacer()
        }
    }

    // MARK: - Footer Section

    private var footerSection: some View {
        HStack {
            Spacer()

            Text("Select a meal to start cooking")
                .font(TVTheme.Typography.footnote)
                .foregroundStyle(TVTheme.Colors.textTertiary)

            Spacer()
        }
        .padding(.top, TVTheme.Spacing.lg)
    }

    // MARK: - Data Loading

    private func loadTodaysMeals() {
        let weekStart = WeekPlan.normalizeToMonday(Date())

        let descriptor = FetchDescriptor<WeekPlan>(
            predicate: #Predicate<WeekPlan> { plan in
                plan.weekStartDate == weekStart
            }
        )

        do {
            let plans = try modelContext.fetch(descriptor)
            if let plan = plans.first {
                weekPlan = plan
                todaySlots = plan.slots(for: today)
            }
        } catch {
            print("Error loading week plan: \(error)")
        }
    }
}

// MARK: - Inspiration Mode View

/// Full-screen ambient display with beautiful recipe photography.
/// Acts like a food-focused screensaver.
struct InspirationModeView: View {
    @Query private var recipes: [Recipe]
    @State private var currentRecipeIndex = 0

    private let transitionTimer = Timer.publish(every: 15, on: .main, in: .common).autoconnect()

    private var currentRecipe: Recipe? {
        guard !recipes.isEmpty else { return nil }
        return recipes[currentRecipeIndex % recipes.count]
    }

    var body: some View {
        ZStack {
            // Background
            Color.black.ignoresSafeArea()

            if let recipe = currentRecipe {
                VStack {
                    Spacer()

                    // Recipe image (if available)
                    if let imageData = recipe.imageData,
                       let uiImage = UIImage(data: imageData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .overlay(
                                LinearGradient(
                                    colors: [.clear, .black.opacity(0.7)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    }

                    Spacer()

                    // Recipe info overlay
                    VStack(alignment: .leading, spacing: TVTheme.Spacing.md) {
                        Text(recipe.title)
                            .font(TVTheme.Typography.hero)
                            .foregroundStyle(.white)

                        if let summary = recipe.summary {
                            Text(summary)
                                .font(TVTheme.Typography.title3)
                                .foregroundStyle(.white.opacity(0.8))
                                .lineLimit(2)
                        }

                        HStack(spacing: TVTheme.Spacing.lg) {
                            if let time = recipe.totalTimeMinutes {
                                TVTimeChip(minutes: time)
                            }

                            if let archetype = recipe.suggestedArchetypes.first {
                                TVArchetypeBadge(archetype: archetype)
                            }
                        }
                    }
                    .padding(TVTheme.Spacing.xxl)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                TVEmptyState(
                    icon: "photo.stack",
                    title: "No Recipes",
                    message: "Add recipes on your iPhone or iPad to see them here."
                )
            }
        }
        .onReceive(transitionTimer) { _ in
            withAnimation(TVTheme.Animation.crossfade) {
                currentRecipeIndex += 1
            }
        }
    }
}

#Preview("Ambient View") {
    AmbientView()
}
