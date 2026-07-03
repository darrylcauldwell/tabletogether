import SwiftUI
import CoreData
import os.log

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
private let screenshotScreen: String? = {
    let args = ProcessInfo.processInfo.arguments
    guard let index = args.firstIndex(of: "--screenshot-screen"),
          index + 1 < args.count else { return nil }
    return args[index + 1]
}()

/// Whether demo data is enabled via UserDefaults
private let isDemoDataEnabled: Bool = UserDefaults.standard.bool(forKey: "isDemoDataEnabled")

@main
struct TableTogetherTVApp: App {
    // tvOS is a strictly read-only ambient surface (see header) and must never write into
    // the CloudKit-backed store. When demo data is needed (screenshots), use an isolated
    // in-memory controller so seeded data can't sync to the household's real iCloud data.
    private let persistenceController: PersistenceController = {
        if isScreenshotMode || isDemoDataEnabled {
            return PersistenceController(inMemory: true)
        }
        return .shared
    }()

    @State private var selectedTab: TVTab = {
        // Set initial tab from screenshot argument if provided
        if let tabName = screenshotScreen {
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

    var body: some Scene {
        WindowGroup {
            TVContentView(selectedTab: $selectedTab)
                .environment(\.managedObjectContext, persistenceController.viewContext)
                .onAppear {
                    // Seed only the isolated in-memory store used in screenshot/demo mode.
                    // The real shared store is never written to (tvOS is read-only).
                    if isScreenshotMode || isDemoDataEnabled {
                        TVDemoDataSeeder.seedDemoData(into: persistenceController.viewContext)
                    }
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
    // Live fetch so plan edits from iPhone/iPad appear without relaunching.
    @FetchRequest private var weekPlans: FetchedResults<WeekPlan>
    @State private var loadedWeekStart = WeekPlan.normalizeToMonday(Date())

    init() {
        let monday = WeekPlan.normalizeToMonday(Date())
        _weekPlans = FetchRequest(
            sortDescriptors: [],
            predicate: NSPredicate(format: "weekStartDate == %@", monday as NSDate)
        )
    }

    private var weekPlan: WeekPlan? { weekPlans.first }

    /// The ambient surface shows only today onward (matches the iOS
    /// current-week default) — days already gone carry no planning value on a
    /// whiteboard. State-backed so the always-on display advances past
    /// midnight via the rollover task below.
    @State private var fromDay: DayOfWeek = .today

    private var days: [DayOfWeek] {
        DayOfWeek.remaining(from: fromDay)
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
        .task {
            // Roll the display forward at day and week boundaries (always-on).
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                if DayOfWeek.today != fromDay {
                    fromDay = DayOfWeek.today
                }
                let monday = WeekPlan.normalizeToMonday(Date())
                if monday != loadedWeekStart {
                    loadedWeekStart = monday
                    weekPlans.nsPredicate = NSPredicate(format: "weekStartDate == %@", monday as NSDate)
                }
            }
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
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \Recipe.title, ascending: true)])
    private var recipes: FetchedResults<Recipe>
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

    @ViewBuilder private var recipeThumbnail: some View {
        let placeholder = Rectangle()
            .fill(TVTheme.Colors.glassBackground)
            .overlay(
                Image(systemName: "photo")
                    .font(.system(size: 48))
                    .foregroundStyle(TVTheme.Colors.textTertiary)
            )
        if let imageData = recipe.imageData, let uiImage = UIImage(data: imageData) {
            Image(uiImage: uiImage).resizable()
        } else if let url = recipe.imageURL {
            CachedRemoteImage(url: url) { placeholder }
        } else {
            placeholder
        }
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: TVTheme.Spacing.md) {
                // Recipe image — imageData fast-path, else cached remote load.
                recipeThumbnail
                    .aspectRatio(16/9, contentMode: .fill)
                    .frame(height: 200)
                    .clipped()

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
        .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
}
