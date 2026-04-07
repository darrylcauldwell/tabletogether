import SwiftUI
import CoreData

struct ContentView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(sortDescriptors: [SortDescriptor(\.displayName)]) private var users: FetchedResults<User>
    @FetchRequest(sortDescriptors: [SortDescriptor(\.name)]) private var households: FetchedResults<Household>

    var body: some View {
        Group {
            if horizontalSizeClass == .compact {
                CompactNavigationView()
            } else {
                RegularNavigationView()
            }
        }
        .task {
            await ensureUserExists()
        }
    }

    @MainActor
    private func ensureUserExists() async {
        // Skip if the default user already exists (by deterministic ID)
        if users.contains(where: { $0.id == User.defaultMeID }) {
            return
        }
        // Migrate legacy random-UUID "Me" users to the deterministic ID
        if let legacy = users.first(where: { $0.displayName == "Me" }) {
            legacy.id = User.defaultMeID
            viewContext.saveWithLogging(context: "migrate legacy Me user to deterministic ID")
            return
        }

        let household = households.first
        let user = User(
            context: viewContext,
            id: User.defaultMeID,
            displayName: "Me",
            avatarEmoji: "",
            avatarColorHex: "34C759"
        )
        user.household = household

        // Archetypes are created by TableTogetherApp, but ensure they exist
        let archetypeRequest = NSFetchRequest<MealArchetype>(entityName: "MealArchetype")
        let existingArchetypes = viewContext.fetchWithLogging(archetypeRequest, context: "archetypes for onboarding")
        if existingArchetypes.isEmpty {
            for archetypeType in ArchetypeType.allCases {
                let archetype = MealArchetype(context: viewContext, systemType: archetypeType)
                archetype.household = household
            }
        }

        viewContext.saveWithLogging(context: "onboarding user and archetypes")
    }
}

// MARK: - iPhone Navigation (TabView)

struct CompactNavigationView: View {
    @State private var selectedTab: Tab = {
        guard let tabName = TableTogetherApp.screenshotScreen else { return .plan }
        switch tabName {
        case "plan": return .plan
        case "recipes": return .recipes
        case "grocery": return .grocery
        case "log": return .log
        case "insights": return .insights
        default: return .plan
        }
    }()
    @State private var showSettings = false

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                WeekPlannerView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button {
                                showSettings = true
                            } label: {
                                Image(systemName: "gear")
                            }
                        }
                    }
            }
            .tabItem {
                Label("Plan", systemImage: "calendar")
            }
            .tag(Tab.plan)

            NavigationStack {
                RecipeLibraryView()
            }
            .tabItem {
                Label("Recipes", systemImage: "book")
            }
            .tag(Tab.recipes)

            NavigationStack {
                ShoppingContainerView()
            }
            .tabItem {
                Label("Shopping", systemImage: "cart")
            }
            .tag(Tab.grocery)

            NavigationStack {
                MealLogView()
            }
            .tabItem {
                Label("Log", systemImage: "square.and.pencil")
            }
            .tag(Tab.log)

            NavigationStack {
                InsightsView()
            }
            .tabItem {
                Label("Nutrition", systemImage: "chart.line.uptrend.xyaxis")
            }
            .tag(Tab.insights)
        }
        .tint(Theme.Colors.primary)
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }
}

// MARK: - Sidebar Mode

enum SidebarMode {
    case navigation
    case recipeBrowser
}

// MARK: - iPad Navigation (NavigationSplitView)

struct RegularNavigationView: View {
    @State private var selectedSection: SidebarSection? = {
        guard let tabName = TableTogetherApp.screenshotScreen else { return .plan }
        switch tabName {
        case "plan": return .plan
        case "recipes": return .recipes
        case "pantryCheck": return .pantryCheck
        case "grocery": return .grocery
        case "log": return .log
        case "insights": return .insights
        default: return .plan
        }
    }()
    @State private var columnVisibility: NavigationSplitViewVisibility = .doubleColumn
    @State private var sidebarMode: SidebarMode = .navigation
    @State private var showSettings = false

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(selectedSection: $selectedSection, sidebarMode: $sidebarMode)
                .navigationTitle("TableTogether")
        } detail: {
            // Each section gets full width and manages its own navigation
            NavigationStack {
                ContentColumnView(selectedSection: selectedSection)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .tint(Theme.Colors.primary)
        #if targetEnvironment(macCatalyst)
        .onReceive(NotificationCenter.default.publisher(for: .navigateToSection)) { notification in
            if let section = notification.object as? SidebarSection {
                selectedSection = section
                sidebarMode = .navigation
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSettingsRequested)) { _ in
            showSettings = true
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        #endif
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @Binding var selectedSection: SidebarSection?
    @Binding var sidebarMode: SidebarMode
    @State private var showSettings = false

    private var sidebarModePicker: some View {
        Picker("Sidebar Mode", selection: $sidebarMode) {
            Text("Menu").tag(SidebarMode.navigation)
            Text("Recipes").tag(SidebarMode.recipeBrowser)
        }
        .pickerStyle(.segmented)
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        .listRowBackground(Color.clear)
    }

    var body: some View {
        Group {
            if sidebarMode == .recipeBrowser && selectedSection == .plan {
                SidebarRecipeBrowserView(sidebarMode: $sidebarMode)
            } else {
                List(selection: $selectedSection) {
                    if selectedSection == .plan {
                        Section {
                            sidebarModePicker
                        }
                    }

                    Section("Planning") {
                        Label("This Week", systemImage: "calendar")
                            .tag(SidebarSection.plan)
                    }

                    Section("Library") {
                        Label("Recipes", systemImage: "book")
                            .tag(SidebarSection.recipes)
                    }

                    Section("Shopping") {
                        Label("Pantry Check", systemImage: "checklist.checked")
                            .tag(SidebarSection.pantryCheck)
                        Label("Shopping List", systemImage: "cart")
                            .tag(SidebarSection.grocery)
                    }

                    Section("Personal") {
                        Label("Meal Log", systemImage: "square.and.pencil")
                            .tag(SidebarSection.log)

                        Label("Nutrition", systemImage: "chart.line.uptrend.xyaxis")
                            .tag(SidebarSection.insights)
                    }
                }
                #if os(iOS)
                .listStyle(.sidebar)
                #endif
            }
        }
        .toolbar {
            #if os(iOS) && !targetEnvironment(macCatalyst)
            ToolbarItem(placement: .bottomBar) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gear")
                }
            }
            #else
            ToolbarItem(placement: .automatic) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gear")
                }
            }
            #endif
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .onChange(of: selectedSection) { _, newValue in
            // Auto-reset to navigation when leaving Plan section
            if newValue != .plan {
                sidebarMode = .navigation
            }
        }
    }
}

// MARK: - Content Column (Middle)

struct ContentColumnView: View {
    let selectedSection: SidebarSection?

    var body: some View {
        switch selectedSection {
        case .plan:
            WeekPlannerView()
        case .recipes:
            RecipeLibraryView()
        case .pantryCheck:
            PantryCheckView()
        case .grocery:
            GroceryListView()
        case .log:
            MealLogView()
        case .insights:
            InsightsView()
        case .none:
            EmptyStateView(
                icon: "sidebar.left",
                title: "Select a Section",
                message: "Choose a section from the sidebar to get started."
            )
        }
    }
}

// MARK: - Supporting Types

enum Tab: Hashable {
    case plan
    case recipes
    case grocery
    case log
    case insights
}

enum SidebarSection: Hashable {
    case plan
    case recipes
    case pantryCheck
    case grocery
    case log
    case insights
}

// MARK: - Preview

#Preview("iPhone") {
    ContentView()
        .environment(\.horizontalSizeClass, .compact)
        .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
}

#Preview("iPad") {
    ContentView()
        .environment(\.horizontalSizeClass, .regular)
        .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
}
