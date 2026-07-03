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
    case thisWeek = "Upcoming"
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
    /// Number of upcoming days shown, starting today — spans week boundaries so
    /// the remote can scroll right into future weeks ("Upcoming meals").
    private static let horizonDays = 14

    // Live fetch across the upcoming window so plan edits from iPhone/iPad
    // appear without relaunching, and future weeks are included.
    @FetchRequest private var weekPlans: FetchedResults<WeekPlan>
    @State private var anchorDay = Calendar.current.startOfDay(for: Date())

    init() {
        _weekPlans = FetchRequest(
            sortDescriptors: [NSSortDescriptor(keyPath: \WeekPlan.weekStartDate, ascending: true)],
            predicate: Self.windowPredicate(from: Date())
        )
    }

    /// Week plans whose week start falls within the upcoming window.
    private static func windowPredicate(from date: Date) -> NSPredicate {
        let calendar = Calendar.current
        let startMonday = WeekPlan.normalizeToMonday(date)
        let end = calendar.date(byAdding: .day, value: horizonDays + 7, to: startMonday) ?? date
        return NSPredicate(format: "weekStartDate >= %@ AND weekStartDate < %@", startMonday as NSDate, end as NSDate)
    }

    /// The upcoming days, today through today + horizon.
    private var upcomingDates: [Date] {
        let calendar = Calendar.current
        return (0..<Self.horizonDays).compactMap {
            calendar.date(byAdding: .day, value: $0, to: anchorDay)
        }
    }

    private func weekPlan(for date: Date) -> WeekPlan? {
        let monday = WeekPlan.normalizeToMonday(date)
        return weekPlans.first { Calendar.current.isDate($0.weekStartDate, inSameDayAs: monday) }
    }

    var body: some View {
        ZStack {
            TVTheme.Colors.background.ignoresSafeArea()

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: TVTheme.Spacing.lg) {
                    ForEach(upcomingDates, id: \.self) { date in
                        DayColumn(date: date, weekPlan: weekPlan(for: date))
                    }
                }
                .tvSafeArea()
            }
        }
        .task {
            // Roll forward past midnight (always-on display): re-anchor to today
            // and slide the fetch window so future weeks keep arriving.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                let today = Calendar.current.startOfDay(for: Date())
                if today != anchorDay {
                    anchorDay = today
                    weekPlans.nsPredicate = Self.windowPredicate(from: today)
                }
            }
        }
    }
}

// MARK: - Day Column

struct DayColumn: View {
    let date: Date
    let weekPlan: WeekPlan?

    // Focusable so the Apple TV remote can move across the strip; focus drives
    // the ScrollView to bring off-screen future days into view.
    @Environment(\.isFocused) private var isFocused
    @FocusState private var focused: Bool

    private var day: DayOfWeek { DayOfWeek.day(for: date) }

    private var slots: [MealSlot] {
        weekPlan?.slots(for: day) ?? []
    }

    private var isToday: Bool { Calendar.current.isDateInToday(date) }

    private var dayNumber: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM"
        return formatter.string(from: date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TVTheme.Spacing.md) {
            // Day header
            HStack(spacing: TVTheme.Spacing.sm) {
                Text(isToday ? "Today" : day.shortName)
                    .font(TVTheme.Typography.title2)
                    .foregroundStyle(isToday ? TVTheme.Colors.primary : TVTheme.Colors.textPrimary)

                Text(dayNumber)
                    .font(TVTheme.Typography.callout)
                    .foregroundStyle(TVTheme.Colors.textTertiary)

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
        .tvGlassBackground(highlighted: isToday || focused)
        .clipShape(RoundedRectangle(cornerRadius: TVTheme.CornerRadius.large))
        .scaleEffect(focused ? 1.03 : 1.0)
        .animation(TVTheme.Animation.focusIn, value: focused)
        .focusable()
        .focused($focused)
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
