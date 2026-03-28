import SwiftUI
import CoreData
import CloudKit

@main
struct TableTogetherApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #elseif os(macOS)
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) var appDelegate
    #endif

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
                .environment(\.privateDataManager, privateDataManager)
                .environment(\.calendarService, calendarService)
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

        // Check if archetypes already exist
        let archetypeRequest = NSFetchRequest<MealArchetype>(entityName: "MealArchetype")
        let existingArchetypes = (try? context.fetch(archetypeRequest)) ?? []

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

        // Check if current week plan exists
        let today = Date()
        let weekStart = WeekPlan.normalizeToMonday(today)

        let weekPlanRequest = NSFetchRequest<WeekPlan>(entityName: "WeekPlan")
        weekPlanRequest.predicate = NSPredicate(format: "weekStartDate == %@", weekStart as NSDate)
        weekPlanRequest.fetchLimit = 1

        let existingPlans = (try? context.fetch(weekPlanRequest)) ?? []

        if existingPlans.isEmpty {
            // Create current week plan with default slots
            let weekPlan = WeekPlan(context: context, weekStartDate: today)
            weekPlan.createDefaultSlots(context: context, mealTypes: [.breakfast, .lunch, .dinner])
            weekPlan.household = household

            do {
                try context.save()
                AppLogger.app.info("Created week plan for \(weekPlan.weekRangeDisplay)")
            } catch {
                AppLogger.swiftData.error("Failed to save week plan", error: error)
            }
        }
    }

    /// Creates a Household if none exists, links all orphaned top-level records to it,
    /// and returns it for use when creating new records.
    @MainActor
    @discardableResult
    private func ensureHousehold(context: NSManagedObjectContext) -> Household {
        let householdRequest = NSFetchRequest<Household>(entityName: "Household")
        let existingHouseholds = (try? context.fetch(householdRequest)) ?? []

        let household: Household
        if let existing = existingHouseholds.first {
            household = existing
        } else {
            household = Household(context: context, name: "My Household")
            AppLogger.app.info("Created household")
        }

        // Link orphaned top-level records to household
        var linked = 0

        for recipe in (try? context.fetch(NSFetchRequest<Recipe>(entityName: "Recipe"))) ?? [] where recipe.household == nil {
            recipe.household = household
            linked += 1
        }
        for ingredient in (try? context.fetch(NSFetchRequest<Ingredient>(entityName: "Ingredient"))) ?? [] where ingredient.household == nil {
            ingredient.household = household
            linked += 1
        }
        for weekPlan in (try? context.fetch(NSFetchRequest<WeekPlan>(entityName: "WeekPlan"))) ?? [] where weekPlan.household == nil {
            weekPlan.household = household
            linked += 1
        }
        for user in (try? context.fetch(NSFetchRequest<User>(entityName: "User"))) ?? [] where user.household == nil {
            user.household = household
            linked += 1
        }
        for archetype in (try? context.fetch(NSFetchRequest<MealArchetype>(entityName: "MealArchetype"))) ?? [] where archetype.household == nil {
            archetype.household = household
            linked += 1
        }
        for memory in (try? context.fetch(NSFetchRequest<SuggestionMemory>(entityName: "SuggestionMemory"))) ?? [] where memory.household == nil {
            memory.household = household
            linked += 1
        }
        for foodItem in (try? context.fetch(NSFetchRequest<FoodItem>(entityName: "FoodItem"))) ?? [] where foodItem.household == nil {
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

// MARK: - App Delegates for CloudKit Share Acceptance

#if os(iOS)
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        Task {
            do {
                try await PersistenceController.shared.acceptShare(metadata: cloudKitShareMetadata)
                AppLogger.sharing.info("Accepted CloudKit share invitation")
            } catch {
                AppLogger.sharing.error("Failed to accept CloudKit share: \(error.localizedDescription)")
            }
        }
    }
}
#endif

#if os(macOS)
class MacAppDelegate: NSObject, NSApplicationDelegate {
    func application(
        _ application: NSApplication,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        Task {
            do {
                try await PersistenceController.shared.acceptShare(metadata: cloudKitShareMetadata)
                AppLogger.sharing.info("Accepted CloudKit share invitation (macOS)")
            } catch {
                AppLogger.sharing.error("Failed to accept CloudKit share: \(error.localizedDescription)")
            }
        }
    }
}
#endif
