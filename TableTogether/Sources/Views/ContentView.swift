import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.modelContext) private var modelContext
    @Query private var users: [User]
    @Query private var households: [Household]

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
        guard users.isEmpty else { return }

        let household = households.first
        let user = User(displayName: "Me", avatarEmoji: "", avatarColorHex: "34C759")
        user.household = household
        modelContext.insert(user)

        // Archetypes are created by TableTogetherApp, but ensure they exist
        let archetypeDescriptor = FetchDescriptor<MealArchetype>()
        let existingArchetypes = (try? modelContext.fetch(archetypeDescriptor)) ?? []
        if existingArchetypes.isEmpty {
            for archetypeType in ArchetypeType.allCases {
                let archetype = MealArchetype(systemType: archetypeType)
                archetype.household = household
                modelContext.insert(archetype)
            }
        }

        try? modelContext.save()
    }
}

// MARK: - iPhone Navigation (TabView)

struct CompactNavigationView: View {
    @State private var selectedTab: Tab = {
        guard let tabName = TableTogetherApp.screenshotTab else { return .plan }
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
                Label("Insights", systemImage: "chart.line.uptrend.xyaxis")
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
        guard let tabName = TableTogetherApp.screenshotTab else { return .plan }
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

                        Label("Insights", systemImage: "chart.line.uptrend.xyaxis")
                            .tag(SidebarSection.insights)
                    }
                }
                #if os(iOS)
                .listStyle(.sidebar)
                #endif
            }
        }
        .toolbar {
            #if os(iOS)
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
            ContentUnavailableView(
                "Select a Section",
                systemImage: "sidebar.left",
                description: Text("Choose a section from the sidebar to get started.")
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
        .modelContainer(for: [User.self, WeekPlan.self, Recipe.self, MealSlot.self, GroceryItem.self, MealArchetype.self], inMemory: true)
}

#Preview("iPad") {
    ContentView()
        .environment(\.horizontalSizeClass, .regular)
        .modelContainer(for: [User.self, WeekPlan.self, Recipe.self, MealSlot.self, GroceryItem.self, MealArchetype.self], inMemory: true)
}
