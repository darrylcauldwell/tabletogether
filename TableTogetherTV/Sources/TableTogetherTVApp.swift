import SwiftUI
import SwiftData

// MARK: - TableTogether tvOS App
//
// A calm, ambient, read-only experience for the household.
// Designed for kitchens and shared family spaces.
//
// Core principles:
// - Read-only (no editing on tvOS)
// - Glanceable from across the room
// - Focus-based navigation (Siri Remote)
// - Shared data via iCloud
// - No nutrition tracking or personal data

// MARK: - Screenshot Mode Support

/// Whether the app was launched in screenshot mode (for App Store screenshots)
private let isScreenshotMode: Bool = ProcessInfo.processInfo.arguments.contains("--screenshot-mode")

/// The tab to display when in screenshot mode
private let screenshotTab: String? = {
    let args = ProcessInfo.processInfo.arguments
    guard let index = args.firstIndex(of: "--screenshot-tab"),
          index + 1 < args.count else { return nil }
    return args[index + 1]
}()

/// Whether demo data is enabled via UserDefaults
private let isDemoDataEnabled: Bool = UserDefaults.standard.bool(forKey: "isDemoDataEnabled")

@main
struct TableTogetherTVApp: App {
    private let modelContainer: ModelContainer?

    @State private var selectedTab: TVTab = {
        // Set initial tab from screenshot argument if provided
        if let tabName = screenshotTab {
            switch tabName {
            case "today": return .today
            case "thisWeek": return .thisWeek
            case "recipes": return .recipes
            case "inspiration": return .inspiration
            default: return .today
            }
        }
        return .today
    }()

    init() {
        // Shared schema with iOS app (read-only access)
        // Note: MealLog and personal data are NOT included
        let schema = Schema([
            Household.self,
            Ingredient.self,
            RecipeIngredient.self,
            Recipe.self,
            MealArchetype.self,
            MealSlot.self,
            WeekPlan.self,
            User.self,
            GroceryItem.self,
            SuggestionMemory.self
        ])

        // Connect to the same iCloud container as iOS
        let cloudKitConfig = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .automatic
        )

        do {
            self.modelContainer = try ModelContainer(
                for: schema,
                configurations: [cloudKitConfig]
            )
        } catch {
            // Fallback to local-only if CloudKit unavailable
            print("CloudKit unavailable, using local storage: \(error)")

            let localConfig = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .none
            )

            do {
                self.modelContainer = try ModelContainer(
                    for: schema,
                    configurations: [localConfig]
                )
            } catch {
                print("Failed to create model container: \(error)")
                self.modelContainer = nil
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            if let container = modelContainer {
                TVContentView(selectedTab: $selectedTab)
                    .modelContainer(container)
                    .onAppear {
                        // Seed demo data for screenshots if enabled
                        if isDemoDataEnabled || isScreenshotMode {
                            Task { @MainActor in
                                TVDemoDataSeeder.seedDemoData(into: container.mainContext)
                            }
                        }
                    }
            } else {
                TVErrorView()
            }
        }
    }
}

// MARK: - Tab Definition

enum TVTab: String, CaseIterable, Identifiable {
    case today = "Today"
    case thisWeek = "This Week"
    case recipes = "Recipes"
    case inspiration = "Inspiration"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .today: return "sun.max.fill"
        case .thisWeek: return "calendar"
        case .recipes: return "book.fill"
        case .inspiration: return "sparkles"
        }
    }
}

// MARK: - Content View

struct TVContentView: View {
    @Binding var selectedTab: TVTab

    var body: some View {
        TabView(selection: $selectedTab) {
            // Today's meals (ambient view)
            AmbientView()
                .tabItem {
                    Label(TVTab.today.rawValue, systemImage: TVTab.today.icon)
                }
                .tag(TVTab.today)

            // Week overview
            WeekView()
                .tabItem {
                    Label(TVTab.thisWeek.rawValue, systemImage: TVTab.thisWeek.icon)
                }
                .tag(TVTab.thisWeek)

            // Recipe browser
            RecipeBrowserView()
                .tabItem {
                    Label(TVTab.recipes.rawValue, systemImage: TVTab.recipes.icon)
                }
                .tag(TVTab.recipes)

            // Inspiration mode
            InspirationModeView()
                .tabItem {
                    Label(TVTab.inspiration.rawValue, systemImage: TVTab.inspiration.icon)
                }
                .tag(TVTab.inspiration)
        }
    }
}

// MARK: - Week View

struct WeekView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var weekPlan: WeekPlan?

    private var days: [DayOfWeek] {
        DayOfWeek.allCases
    }

    var body: some View {
        ZStack {
            TVTheme.Colors.background.ignoresSafeArea()

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: TVTheme.Spacing.lg) {
                    ForEach(days, id: \.self) { day in
                        DayColumn(day: day, weekPlan: weekPlan)
                    }
                }
                .tvSafeArea()
            }
        }
        .onAppear {
            loadWeekPlan()
        }
    }

    private func loadWeekPlan() {
        let weekStart = WeekPlan.normalizeToMonday(Date())

        let descriptor = FetchDescriptor<WeekPlan>(
            predicate: #Predicate<WeekPlan> { plan in
                plan.weekStartDate == weekStart
            }
        )

        do {
            let plans = try modelContext.fetch(descriptor)
            weekPlan = plans.first
        } catch {
            print("Error loading week plan: \(error)")
        }
    }
}

// MARK: - Day Column

struct DayColumn: View {
    let day: DayOfWeek
    let weekPlan: WeekPlan?

    private var slots: [MealSlot] {
        weekPlan?.slots(for: day) ?? []
    }

    private var isToday: Bool {
        let weekday = Calendar.current.component(.weekday, from: Date())
        let adjusted = weekday == 1 ? 7 : weekday - 1
        return DayOfWeek(rawValue: adjusted) == day
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TVTheme.Spacing.md) {
            // Day header
            HStack(spacing: TVTheme.Spacing.sm) {
                Text(day.shortName)
                    .font(TVTheme.Typography.title2)
                    .foregroundStyle(isToday ? TVTheme.Colors.primary : TVTheme.Colors.textPrimary)

                if isToday {
                    Circle()
                        .fill(TVTheme.Colors.primary)
                        .frame(width: 12, height: 12)
                }
            }

            // Meals for the day
            ForEach(slots.sorted { $0.mealType.sortOrder < $1.mealType.sortOrder }) { slot in
                TVMealRow(mealSlot: slot)
            }

            if slots.isEmpty {
                Text("No meals planned")
                    .font(TVTheme.Typography.callout)
                    .foregroundStyle(TVTheme.Colors.textTertiary)
                    .padding(.vertical, TVTheme.Spacing.lg)
            }

            Spacer()
        }
        .frame(width: 320)
        .padding(TVTheme.Spacing.lg)
        .tvGlassBackground(highlighted: isToday)
        .clipShape(RoundedRectangle(cornerRadius: TVTheme.CornerRadius.large))
    }
}

// MARK: - Recipe Browser View

struct RecipeBrowserView: View {
    @Query(sort: \Recipe.title) private var recipes: [Recipe]
    @State private var selectedRecipe: Recipe?
    @State private var showingRecipeDetail = false

    private let columns = [
        GridItem(.adaptive(minimum: 350, maximum: 450), spacing: TVTheme.Spacing.lg)
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                TVTheme.Colors.background.ignoresSafeArea()

                if recipes.isEmpty {
                    TVEmptyState(
                        icon: "book.closed.fill",
                        title: "No Recipes",
                        message: "Add recipes on your iPhone or iPad to see them here."
                    )
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: TVTheme.Spacing.lg) {
                            ForEach(recipes) { recipe in
                                RecipeCard(recipe: recipe) {
                                    selectedRecipe = recipe
                                    showingRecipeDetail = true
                                }
                            }
                        }
                        .tvSafeArea()
                    }
                }
            }
            .navigationDestination(isPresented: $showingRecipeDetail) {
                if let recipe = selectedRecipe {
                    RecipeView(recipe: recipe, mealSlot: nil)
                }
            }
        }
    }
}

// MARK: - Recipe Card

struct RecipeCard: View {
    let recipe: Recipe
    let onSelect: () -> Void

    @Environment(\.isFocused) private var isFocused

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: TVTheme.Spacing.md) {
                // Recipe image
                if let imageData = recipe.imageData,
                   let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(16/9, contentMode: .fill)
                        .frame(height: 200)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(TVTheme.Colors.glassBackground)
                        .aspectRatio(16/9, contentMode: .fill)
                        .frame(height: 200)
                        .overlay(
                            Image(systemName: "photo")
                                .font(.system(size: 48))
                                .foregroundStyle(TVTheme.Colors.textTertiary)
                        )
                }

                // Recipe info
                VStack(alignment: .leading, spacing: TVTheme.Spacing.sm) {
                    Text(recipe.title)
                        .font(TVTheme.Typography.headline)
                        .foregroundStyle(TVTheme.Colors.textPrimary)
                        .lineLimit(2)

                    HStack(spacing: TVTheme.Spacing.md) {
                        if let time = recipe.totalTimeMinutes {
                            HStack(spacing: TVTheme.Spacing.xs) {
                                Image(systemName: "clock")
                                Text("\(time) min")
                            }
                            .font(TVTheme.Typography.callout)
                            .foregroundStyle(TVTheme.Colors.textSecondary)
                        }

                        if recipe.isFavorite {
                            Image(systemName: "heart.fill")
                                .foregroundStyle(TVTheme.Colors.secondary)
                        }
                    }
                }
                .padding(TVTheme.Spacing.md)
            }
            .tvGlassBackground(highlighted: isFocused)
            .clipShape(RoundedRectangle(cornerRadius: TVTheme.CornerRadius.standard))
        }
        .buttonStyle(.plain)
        .scaleEffect(isFocused ? TVTheme.FocusScale.card : 1.0)
        .shadow(
            color: isFocused ? TVTheme.Colors.focusGlow : .clear,
            radius: isFocused ? 30 : 0
        )
        .animation(TVTheme.Animation.focusIn, value: isFocused)
    }
}

// MARK: - Error View

struct TVErrorView: View {
    var body: some View {
        ZStack {
            TVTheme.Colors.background.ignoresSafeArea()

            VStack(spacing: TVTheme.Spacing.xl) {
                Image(systemName: "exclamationmark.icloud.fill")
                    .font(.system(size: 100))
                    .foregroundStyle(TVTheme.Colors.textTertiary)

                Text("Unable to Load Data")
                    .font(TVTheme.Typography.title)
                    .foregroundStyle(TVTheme.Colors.textPrimary)

                Text("TableTogether couldn't connect to iCloud. Make sure you're signed in to iCloud on this Apple TV.")
                    .font(TVTheme.Typography.body)
                    .foregroundStyle(TVTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 600)
            }
        }
    }
}

#Preview("TV Content") {
    TVContentView(selectedTab: .constant(.today))
}
