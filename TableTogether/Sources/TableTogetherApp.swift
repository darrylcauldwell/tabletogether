import SwiftUI
import SwiftData
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
    static let screenshotTab: String? = {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "--screenshot-tab"),
              index + 1 < args.count else { return nil }
        return args[index + 1]
    }()

    @State private var modelContainerError: ModelContainerError?
    @StateObject private var privateDataManager = PrivateDataManager()
    @StateObject private var calendarService = CalendarService.shared
    @AppStorage("appearanceMode") private var appearanceMode: Int = AppearanceMode.system.rawValue

    /// Cloud sharing manager for household sharing
    @State private var cloudSharingManager = CloudSharingManager()

    /// Deep link navigation state
    @State private var deepLinkMealSlotId: UUID?

    private let modelContainer: ModelContainer?

    private var selectedColorScheme: ColorScheme? {
        (AppearanceMode(rawValue: appearanceMode) ?? .system).colorScheme
    }

    init() {
        // Note: MealLog is NOT in the shared schema - it's stored in CloudKit private database
        // via PrivateDataManager. This ensures meal consumption data is never shared.
        let schema = Schema([
            Household.self,
            FoodItem.self,
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

        // Try CloudKit-enabled configuration first
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
            // If CloudKit fails, try local-only configuration
            AppLogger.swiftData.warning("CloudKit ModelContainer failed: \(error.localizedDescription)")
            AppLogger.swiftData.info("Attempting local-only configuration...")

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
                AppLogger.swiftData.notice("Local-only ModelContainer created successfully")
            } catch {
                AppLogger.swiftData.fault("Local ModelContainer also failed: \(error.localizedDescription)")
                self.modelContainer = nil
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            if let container = modelContainer {
                ContentView()
                    .modelContainer(container)
                    .environment(\.privateDataManager, privateDataManager)
                    .environment(\.calendarService, calendarService)
                    .environment(\.cloudSharingManager, cloudSharingManager)
                    .environment(\.deepLinkMealSlotId, $deepLinkMealSlotId)
                    .preferredColorScheme(selectedColorScheme)
                    .task {
                        await initializeDataIfNeeded(container: container)
                        if TableTogetherApp.isScreenshotMode {
                            let demoManager = DemoDataManager()
                            demoManager.configure(modelContext: container.mainContext, privateDataManager: privateDataManager)
                            await demoManager.enableDemoData()
                        } else {
                            await cloudSharingManager.fetchExistingShare()
                        }
                    }
                    .onOpenURL { url in
                        handleDeepLink(url)
                    }
            } else {
                ModelContainerErrorView(
                    onRetry: {
                        // In a real app, we'd need to restart the app
                        // For now, just show the error
                    }
                )
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
    private func initializeDataIfNeeded(container: ModelContainer) async {
        let context = container.mainContext

        // Ensure a Household exists first — all new records will be linked to it
        let household = ensureHousehold(context: context)

        // Check if archetypes already exist
        let archetypeDescriptor = FetchDescriptor<MealArchetype>()
        let existingArchetypes = (try? context.fetch(archetypeDescriptor)) ?? []

        if existingArchetypes.isEmpty {
            // Create system archetypes
            let archetypes = MealArchetype.createSystemArchetypes()
            for archetype in archetypes {
                archetype.household = household
                context.insert(archetype)
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

        var weekPlanDescriptor = FetchDescriptor<WeekPlan>(
            predicate: #Predicate<WeekPlan> { plan in
                plan.weekStartDate == weekStart
            }
        )
        weekPlanDescriptor.fetchLimit = 1

        let existingPlans = (try? context.fetch(weekPlanDescriptor)) ?? []

        if existingPlans.isEmpty {
            // Create current week plan with default slots
            let weekPlan = WeekPlan(weekStartDate: today)
            weekPlan.createDefaultSlots(mealTypes: [.breakfast, .lunch, .dinner])
            weekPlan.household = household
            context.insert(weekPlan)

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
    private func ensureHousehold(context: ModelContext) -> Household {
        let householdDescriptor = FetchDescriptor<Household>()
        let existingHouseholds = (try? context.fetch(householdDescriptor)) ?? []

        let household: Household
        if let existing = existingHouseholds.first {
            household = existing
        } else {
            household = Household(name: "My Household")
            context.insert(household)
            AppLogger.app.info("Created household")
        }

        // Link orphaned top-level records to household
        var linked = 0

        for recipe in (try? context.fetch(FetchDescriptor<Recipe>())) ?? [] where recipe.household == nil {
            recipe.household = household
            linked += 1
        }
        for ingredient in (try? context.fetch(FetchDescriptor<Ingredient>())) ?? [] where ingredient.household == nil {
            ingredient.household = household
            linked += 1
        }
        for weekPlan in (try? context.fetch(FetchDescriptor<WeekPlan>())) ?? [] where weekPlan.household == nil {
            weekPlan.household = household
            linked += 1
        }
        for user in (try? context.fetch(FetchDescriptor<User>())) ?? [] where user.household == nil {
            user.household = household
            linked += 1
        }
        for archetype in (try? context.fetch(FetchDescriptor<MealArchetype>())) ?? [] where archetype.household == nil {
            archetype.household = household
            linked += 1
        }
        for memory in (try? context.fetch(FetchDescriptor<SuggestionMemory>())) ?? [] where memory.household == nil {
            memory.household = household
            linked += 1
        }
        for foodItem in (try? context.fetch(FetchDescriptor<FoodItem>())) ?? [] where foodItem.household == nil {
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

// MARK: - Model Container Error

enum ModelContainerError: Error, LocalizedError {
    case cloudKitFailed(underlying: Error)
    case localFailed(underlying: Error)
    case bothFailed(cloudKit: Error, local: Error)

    var errorDescription: String? {
        switch self {
        case .cloudKitFailed(let error):
            return "iCloud sync unavailable: \(error.localizedDescription)"
        case .localFailed(let error):
            return "Local storage failed: \(error.localizedDescription)"
        case .bothFailed(let cloudKit, let local):
            return "Storage unavailable. iCloud: \(cloudKit.localizedDescription), Local: \(local.localizedDescription)"
        }
    }
}

// MARK: - Error View

struct ModelContainerErrorView: View {
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "exclamationmark.icloud.fill")
                .font(.system(size: 64))
                .foregroundStyle(Theme.Colors.textSecondary)

            Text("Unable to Load Data")
                .font(Theme.Typography.title2)
                .foregroundStyle(Theme.Colors.textPrimary)

            Text("TableTogether couldn't access its data storage. This might be due to iCloud being unavailable or a storage issue on your device.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            VStack(spacing: 12) {
                Text("Try these steps:")
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)

                VStack(alignment: .leading, spacing: 8) {
                    Label("Check your internet connection", systemImage: "wifi")
                    Label("Sign in to iCloud in Settings", systemImage: "icloud")
                    Label("Ensure you have storage space", systemImage: "internaldrive")
                    Label("Restart the app", systemImage: "arrow.clockwise")
                }
                .font(Theme.Typography.subheadline)
                .foregroundStyle(Theme.Colors.textSecondary)
            }
            .padding()
            #if os(iOS)
            .background(Color(.secondarySystemBackground))
            #else
            .background(Color.secondary.opacity(0.1))
            #endif
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.standard))

            Button(action: onRetry) {
                Text("Retry")
                    .font(Theme.Typography.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 12)
                    .background(Theme.Colors.primary)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Colors.background)
    }
}

#Preview("Error View") {
    ModelContainerErrorView(onRetry: {})
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
        let container = CKContainer(identifier: "iCloud.dev.dreamfold.tabletogether")
        Task {
            do {
                try await container.accept(cloudKitShareMetadata)
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
        let container = CKContainer(identifier: "iCloud.dev.dreamfold.tabletogether")
        Task {
            do {
                try await container.accept(cloudKitShareMetadata)
                AppLogger.sharing.info("Accepted CloudKit share invitation (macOS)")
            } catch {
                AppLogger.sharing.error("Failed to accept CloudKit share: \(error.localizedDescription)")
            }
        }
    }
}
#endif
