import SwiftUI
import CoreData
import CloudKit

@main
struct TableTogetherApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    // MARK: - Screenshot Mode

    /// Whether the app was launched in screenshot capture mode
    static let isScreenshotMode: Bool = ProcessInfo.processInfo.arguments.contains("--screenshot-mode")

    /// The tab to display when in screenshot mode (e.g. "plan", "recipes", "grocery", "log", "insights", "pantryCheck")
    static let screenshotScreen: String? = {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "--screenshot-screen"),
              index + 1 < args.count else { return nil }
        return args[index + 1]
    }()

    @State private var privateDataManager = PrivateDataManager()
    @State private var calendarService = CalendarService.shared
    @AppStorage("appearanceMode") private var appearanceMode: Int = AppearanceMode.system.rawValue

    /// Deep link navigation state
    @State private var deepLinkMealSlotId: UUID?

    private let persistenceController = PersistenceController.shared

    private var selectedColorScheme: ColorScheme? {
        (AppearanceMode(rawValue: appearanceMode) ?? .system).colorScheme
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.viewContext)
                .environment(privateDataManager)
                .environment(calendarService)
                .environment(\.deepLinkMealSlotId, $deepLinkMealSlotId)
                .preferredColorScheme(selectedColorScheme)
                .task {
                    await initializeDataIfNeeded()
                    if TableTogetherApp.isScreenshotMode {
                        let demoManager = DemoDataManager()
                        demoManager.configure(modelContext: persistenceController.viewContext, privateDataManager: privateDataManager)
                        await demoManager.enableDemoData()
                    } else {
                        await persistenceController.fetchExistingShare()
                    }
                }
                .onOpenURL { url in
                    handleDeepLink(url)
                }
        }
        // Menu bar commands added via AppDelegate.buildMenu(with:) for Catalyst compatibility
    }

    /// Handle deep links from calendar events.
    ///
    /// URL format: `tabletogether://meal/{mealSlotId}`
    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "tabletogether", url.host == "meal" else { return }

        // Extract the meal slot ID from the path
        // URL path is like "/550e8400-e29b-41d4-a716-446655440000"
        let pathComponents = url.pathComponents
        guard pathComponents.count >= 2,
              let slotId = UUID(uuidString: pathComponents[1]) else {
            return
        }

        // Set the deep link ID to trigger navigation
        deepLinkMealSlotId = slotId
    }

    /// Initialize default data on first launch
    @MainActor
    private func initializeDataIfNeeded() async {
        let context = persistenceController.viewContext

        // Ensure a Household exists first — all new records will be linked to it
        let household = ensureHousehold(context: context)

        // Save the household immediately so it syncs to CloudKit before anything else is created
        if context.hasChanges {
            do {
                try context.save()
                AppLogger.app.info("Saved household")
            } catch {
                AppLogger.swiftData.error("Failed to save household", error: error)
            }
        }

        // Check if archetypes already exist
        let archetypeRequest = NSFetchRequest<MealArchetype>(entityName: "MealArchetype")
        let existingArchetypes = context.fetchWithLogging(archetypeRequest, context: "system archetypes check")

        if existingArchetypes.isEmpty {
            // Create system archetypes
            let archetypes = MealArchetype.createSystemArchetypes(context: context)
            for archetype in archetypes {
                archetype.household = household
            }

            do {
                try context.save()
                AppLogger.app.info("Created \(archetypes.count) system archetypes")
            } catch {
                AppLogger.swiftData.error("Failed to save system archetypes", error: error)
            }
        }

        // Week plans and meal slots are NOT seeded — they materialize on demand
        // when a meal is planned (#Change2/#Change4). Concurrent seeding was the
        // systemic source of duplicate CKRecords, and the slot self-heal it
        // required fed the cross-device dedup thrash loop (see
        // docs/SYNC_DEDUP_REDESIGN.md).

        cleanupEmptyStructureIfNeeded(context: context)
    }

    /// One-time cleanup (#Change5): builds before the lazy-structure redesign
    /// materialized 28 empty slots per week as data. Deletes empty unplanned
    /// slots and content-free week plans from the private store so empty cells
    /// exist only as UI. Idempotent across devices — both may delete the same
    /// records; the deletions converge through sync.
    @MainActor
    private func cleanupEmptyStructureIfNeeded(context: NSManagedObjectContext) {
        let cleanupKey = "EmptyStructureCleanup_v1"
        guard !UserDefaults.standard.bool(forKey: cleanupKey) else { return }
        // Never touch the shared store — it holds another household's records.
        guard let privateStore = persistenceController.privatePersistentStore else { return }

        let slotRequest = NSFetchRequest<MealSlot>(entityName: "MealSlot")
        slotRequest.affectedStores = [privateStore]
        var deletedSlots = 0
        for slot in context.fetchWithLogging(slotRequest, context: "empty-slot cleanup")
        where slot.isEmpty && (slot.notes?.isEmpty ?? true) && slot.storedComponents.isEmpty {
            context.delete(slot)
            deletedSlots += 1
        }

        let planRequest = NSFetchRequest<WeekPlan>(entityName: "WeekPlan")
        planRequest.affectedStores = [privateStore]
        var deletedPlans = 0
        for plan in context.fetchWithLogging(planRequest, context: "empty-plan cleanup") {
            let keepsSlots = plan.slotsArray.contains { !$0.isDeleted }
            let keepsGroceries = plan.groceryItemsArray.contains { !$0.isDeleted }
            if !keepsSlots && !keepsGroceries && (plan.householdNote?.isEmpty ?? true) {
                context.delete(plan)
                deletedPlans += 1
            }
        }

        if context.hasChanges {
            do {
                try context.save()
                AppLogger.app.info("Cleanup: removed \(deletedSlots) empty slots, \(deletedPlans) empty week plans")
            } catch {
                AppLogger.swiftData.error("Failed to save empty-structure cleanup", error: error)
                return // leave the flag unset so the cleanup retries next launch
            }
        }
        UserDefaults.standard.set(true, forKey: cleanupKey)
    }

    /// Creates a Household if none exists, links all orphaned top-level records to it,
    /// and returns it for use when creating new records.
    @MainActor
    @discardableResult
    private func ensureHousehold(context: NSManagedObjectContext) -> Household {
        // Scope every fetch here to the PRIVATE store. The shared store holds another
        // user's household (after accepting an invitation), which has the same
        // deterministic Household.defaultID. An unscoped fetch would treat it as a
        // duplicate and reparent/delete its records across stores — catastrophic.
        let privateStore = persistenceController.privatePersistentStore
        func scopedRequest<T: NSFetchRequestResult>(_ entity: String) -> NSFetchRequest<T> {
            let request = NSFetchRequest<T>(entityName: entity)
            if let privateStore { request.affectedStores = [privateStore] }
            return request
        }

        let householdRequest: NSFetchRequest<Household> = scopedRequest("Household")
        let existingHouseholds = context.fetchWithLogging(householdRequest, context: "household check")

        let household: Household
        // Prefer the deterministic default household if it exists
        if let defaultHousehold = existingHouseholds.first(where: { $0.id == Household.defaultID }) {
            household = defaultHousehold
        } else if let legacy = existingHouseholds.first {
            // Legacy data with random UUIDs — adopt the first, then migrate its ID
            // so future syncs across devices converge on the same household.
            household = legacy
            household.id = Household.defaultID
            AppLogger.app.info("Adopted legacy household and migrated to default ID")
        } else {
            // Fresh install — create the default household
            household = Household(context: context, name: "My Household")
            AppLogger.app.info("Created default household")
        }

        // Merge any duplicate households into the canonical one
        let duplicates = existingHouseholds.filter { $0 !== household }
        if !duplicates.isEmpty {
            AppLogger.app.info("Merging \(duplicates.count) duplicate households")
            for duplicate in duplicates {
                for recipe in duplicate.recipesArray { recipe.household = household }
                for ingredient in duplicate.ingredientsArray { ingredient.household = household }
                for user in duplicate.usersArray { user.household = household }
                for weekPlan in duplicate.weekPlansArray { weekPlan.household = household }
                for archetype in duplicate.archetypesArray { archetype.household = household }
                for memory in duplicate.memoriesArray { memory.household = household }
                for foodItem in duplicate.foodItemsArray { foodItem.household = household }
                context.delete(duplicate)
            }
        }

        // Link orphaned top-level records to household
        var linked = 0

        for recipe in context.fetchWithLogging(scopedRequest("Recipe") as NSFetchRequest<Recipe>, context: "orphaned recipes") where recipe.household == nil {
            recipe.household = household
            linked += 1
        }
        for ingredient in context.fetchWithLogging(scopedRequest("Ingredient") as NSFetchRequest<Ingredient>, context: "orphaned ingredients") where ingredient.household == nil {
            ingredient.household = household
            linked += 1
        }
        for weekPlan in context.fetchWithLogging(scopedRequest("WeekPlan") as NSFetchRequest<WeekPlan>, context: "orphaned week plans") where weekPlan.household == nil {
            weekPlan.household = household
            linked += 1
        }
        for user in context.fetchWithLogging(scopedRequest("User") as NSFetchRequest<User>, context: "orphaned users") where user.household == nil {
            user.household = household
            linked += 1
        }
        for archetype in context.fetchWithLogging(scopedRequest("MealArchetype") as NSFetchRequest<MealArchetype>, context: "orphaned archetypes") where archetype.household == nil {
            archetype.household = household
            linked += 1
        }
        for memory in context.fetchWithLogging(scopedRequest("SuggestionMemory") as NSFetchRequest<SuggestionMemory>, context: "orphaned suggestion memories") where memory.household == nil {
            memory.household = household
            linked += 1
        }
        for foodItem in context.fetchWithLogging(scopedRequest("FoodItem") as NSFetchRequest<FoodItem>, context: "orphaned food items") where foodItem.household == nil {
            foodItem.household = household
            linked += 1
        }

        if linked > 0 {
            do {
                try context.save()
                AppLogger.app.info("Linked \(linked) records to household")
            } catch {
                AppLogger.swiftData.error("Failed to link records to household", error: error)
            }
        }

        return household
    }
}

// MARK: - Deep Link Environment Key

struct DeepLinkMealSlotIdKey: EnvironmentKey {
    static let defaultValue: Binding<UUID?>? = nil
}

extension EnvironmentValues {
    var deepLinkMealSlotId: Binding<UUID?>? {
        get { self[DeepLinkMealSlotIdKey.self] }
        set { self[DeepLinkMealSlotIdKey.self] = newValue }
    }
}

// MARK: - App & Scene Delegates for CloudKit Share Acceptance
//
// Per Apple's "Accepting Share Invitations in a SwiftUI App" documentation:
// SwiftUI apps are scene-based, so share acceptance must use UIWindowSceneDelegate
// (not UIApplicationDelegate which is deprecated for this purpose).

#if os(iOS)
class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    /// Called when user taps a CloudKit share link while app is running or suspended.
    func windowScene(
        _ windowScene: UIWindowScene,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        acceptShare(metadata: cloudKitShareMetadata)
    }

    /// Called when app is launched from a CloudKit share link (cold start).
    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        if let metadata = connectionOptions.cloudKitShareMetadata {
            acceptShare(metadata: metadata)
        }
    }

    private func acceptShare(metadata: CKShare.Metadata) {
        Task {
            do {
                try await PersistenceController.shared.acceptShare(metadata: metadata)
                AppLogger.sharing.info("Accepted CloudKit share invitation")
            } catch {
                AppLogger.sharing.error("Failed to accept CloudKit share: \(error.localizedDescription)")
            }
        }
    }
}

class AppDelegate: UIResponder, UIApplicationDelegate {
    /// Wire the SceneDelegate so share acceptance works in SwiftUI.
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = SceneDelegate.self
        return config
    }

    #if targetEnvironment(macCatalyst)
    /// Keyboard shortcuts for Mac Catalyst — delivered via the responder chain.
    override var keyCommands: [UIKeyCommand]? {
        [
            UIKeyCommand(title: "New Recipe", action: #selector(handleNewRecipe), input: "N", modifierFlags: .command),
            UIKeyCommand(title: "Import from URL…", action: #selector(handleImportFromURL), input: "I", modifierFlags: [.command, .shift]),
            UIKeyCommand(title: "Settings…", action: #selector(handleOpenSettings), input: ",", modifierFlags: .command),
            UIKeyCommand(title: "Plan", action: #selector(handleNavigate(_:)), input: "1", modifierFlags: .command),
            UIKeyCommand(title: "Recipes", action: #selector(handleNavigate(_:)), input: "2", modifierFlags: .command),
            UIKeyCommand(title: "Shopping", action: #selector(handleNavigate(_:)), input: "3", modifierFlags: .command),
            UIKeyCommand(title: "Meal Log", action: #selector(handleNavigate(_:)), input: "4", modifierFlags: .command),
            UIKeyCommand(title: "Insights", action: #selector(handleNavigate(_:)), input: "5", modifierFlags: .command),
        ]
    }

    @objc private func handleNewRecipe() {
        NotificationCenter.default.post(name: .newRecipeRequested, object: nil)
    }

    @objc private func handleImportFromURL() {
        NotificationCenter.default.post(name: .importFromURLRequested, object: nil)
    }

    @objc private func handleOpenSettings() {
        NotificationCenter.default.post(name: .openSettingsRequested, object: nil)
    }

    @objc private func handleNavigate(_ sender: UIKeyCommand) {
        guard let input = sender.input else { return }
        let section: SidebarSection? = switch input {
        case "1": .plan
        case "2": .recipes
        case "3": .grocery
        case "4": .log
        case "5": .insights
        default: nil
        }
        if let section {
            NotificationCenter.default.post(name: .navigateToSection, object: section)
        }
    }
    #endif
}
#endif

