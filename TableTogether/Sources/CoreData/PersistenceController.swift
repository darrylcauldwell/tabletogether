@preconcurrency import CoreData
import CloudKit
import SwiftUI
import Observation
import os

/// Unified persistence controller managing Core Data with CloudKit sharing.
///
/// Handles:
/// - NSPersistentCloudKitContainer with dual stores (private + shared)
/// - CloudKit sharing lifecycle (create, accept, fetch shares)
/// - Persistent history tracking and remote change processing
/// - Deduplication of records arriving from CloudKit
@Observable
@MainActor
final class PersistenceController {

    // MARK: - Singleton & Preview

    /// Shared instance for the app.
    static let shared = PersistenceController()

    /// In-memory controller for SwiftUI previews and tests.
    static let preview: PersistenceController = {
        let controller = PersistenceController(inMemory: true)
        // Seed minimal preview data on the viewContext
        let context = controller.viewContext
        let household = Household(context: context)
        household.id = UUID()
        household.name = "Preview Household"
        household.createdAt = Date()
        try? context.save()
        return controller
    }()

    // MARK: - Container & Stores

    /// The CloudKit-enabled persistent container.
    let container: NSPersistentCloudKitContainer

    /// The private persistent store (owner's data).
    private(set) var privatePersistentStore: NSPersistentStore?

    /// The shared persistent store (data shared by others).
    private(set) var sharedPersistentStore: NSPersistentStore?

    /// The CloudKit container for sharing operations.
    @ObservationIgnored
    private(set) lazy var ckContainer = CKContainer(identifier: Self.cloudKitContainerID)

    /// Main context for UI reads and writes.
    var viewContext: NSManagedObjectContext { container.viewContext }

    // MARK: - Sharing State

    /// The existing CKShare for the household, if any.
    private(set) var existingShare: CKShare?

    /// Whether the household is currently shared with others.
    var isSharing: Bool { existingShare != nil }

    /// Number of participants (excluding owner).
    var participantCount: Int {
        guard let share = existingShare else { return 0 }
        return share.participants.count - 1
    }

    /// Participant names for display.
    var participantNames: [String] {
        guard let share = existingShare else { return [] }
        return share.participants
            .filter { $0.role != .owner }
            .compactMap { participant in
                participant.userIdentity.nameComponents.flatMap {
                    PersonNameComponentsFormatter.localizedString(from: $0, style: .default)
                } ?? "Unknown"
            }
    }

    /// Last error from sharing operations.
    private(set) var lastError: String?

    // MARK: - Constants

    static let cloudKitContainerID = "iCloud.dev.dreamfold.tabletogether"
    private static let appTransactionAuthor = "TableTogether"

    // MARK: - History Tokens

    @ObservationIgnored
    private var lastHistoryTokens: [String: NSPersistentHistoryToken] = [:]

    @ObservationIgnored
    private lazy var tokenDirectory: URL = {
        let url = NSPersistentContainer.defaultDirectoryURL().appendingPathComponent("HistoryTokens", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    // MARK: - Initialization

    init(inMemory: Bool = false) {
        container = NSPersistentCloudKitContainer(name: "TableTogether")

        if inMemory {
            // Single in-memory store for previews/tests
            let description = NSPersistentStoreDescription()
            description.type = NSInMemoryStoreType
            container.persistentStoreDescriptions = [description]
        } else {
            let storeDirectory = NSPersistentContainer.defaultDirectoryURL()

            // Private store — owner's data, syncs to CloudKit private database
            let privateDescription = NSPersistentStoreDescription(
                url: storeDirectory.appendingPathComponent("private.sqlite")
            )
            privateDescription.configuration = "Private"
            privateDescription.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
                containerIdentifier: Self.cloudKitContainerID
            )
            privateDescription.cloudKitContainerOptions?.databaseScope = .private
            privateDescription.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            privateDescription.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

            // Shared store — data shared by others, syncs to CloudKit shared database
            let sharedDescription = NSPersistentStoreDescription(
                url: storeDirectory.appendingPathComponent("shared.sqlite")
            )
            sharedDescription.configuration = "Shared"
            let sharedOptions = NSPersistentCloudKitContainerOptions(
                containerIdentifier: Self.cloudKitContainerID
            )
            sharedOptions.databaseScope = .shared
            sharedDescription.cloudKitContainerOptions = sharedOptions
            sharedDescription.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            sharedDescription.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

            container.persistentStoreDescriptions = [privateDescription, sharedDescription]
        }

        container.loadPersistentStores { [weak self] description, error in
            if let error {
                AppLogger.swiftData.fault("Failed to load store '\(description.configuration ?? "default")': \(error.localizedDescription)")
                return
            }

            guard let self else { return }

            // Capture store references
            if let store = description.cloudKitContainerOptions.flatMap({ options -> NSPersistentStore? in
                self.container.persistentStoreCoordinator.persistentStore(for: description.url!)
            }) {
                if description.cloudKitContainerOptions?.databaseScope == .shared {
                    self.sharedPersistentStore = store
                } else {
                    self.privatePersistentStore = store
                }
            } else if let url = description.url,
                      let store = self.container.persistentStoreCoordinator.persistentStore(for: url) {
                // In-memory or fallback
                self.privatePersistentStore = store
            }
        }

        // Configure viewContext
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
        container.viewContext.transactionAuthor = Self.appTransactionAuthor

        // Observe remote changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(processRemoteChanges),
            name: .NSPersistentStoreRemoteChange,
            object: container.persistentStoreCoordinator
        )

        // Load persisted history tokens
        loadHistoryTokens()

        #if DEBUG
        initializeSchemaIfNeeded()
        #endif
    }

    // MARK: - Background Context

    /// Creates a new background context for batch operations.
    func newBackgroundContext() -> NSManagedObjectContext {
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
        context.transactionAuthor = Self.appTransactionAuthor
        return context
    }

    // MARK: - Store Queries

    /// Whether an object lives in the private store (owned by this user).
    func isOwned(object: NSManagedObject) -> Bool {
        guard let store = object.objectID.persistentStore else { return true }
        return store == privatePersistentStore
    }

    /// Whether the current user can edit an object.
    func canEdit(object: NSManagedObject) -> Bool {
        if isOwned(object: object) { return true }
        return container.canUpdateRecord(forManagedObjectWith: object.objectID)
    }

    /// Whether the current user can delete an object.
    func canDelete(object: NSManagedObject) -> Bool {
        if isOwned(object: object) { return true }
        return container.canDeleteRecord(forManagedObjectWith: object.objectID)
    }

    // MARK: - Sharing

    /// Creates a CKShare for the given household, sharing all related data.
    func shareHousehold(_ household: Household) async throws -> CKShare {
        try await withCheckedThrowingContinuation { continuation in
            container.share([household], to: nil) { _, share, _, error in
                if let error {
                    Task { @MainActor in
                        self.lastError = error.localizedDescription
                    }
                    continuation.resume(throwing: error)
                    return
                }

                guard let share else {
                    let err = NSError(domain: "PersistenceController", code: 1,
                                      userInfo: [NSLocalizedDescriptionKey: "Share creation returned nil"])
                    continuation.resume(throwing: err)
                    return
                }

                share[CKShare.SystemFieldKey.title] = "TableTogether Household" as CKRecordValue
                share.publicPermission = .none

                Task { @MainActor in
                    self.existingShare = share
                    self.lastError = nil
                }
                continuation.resume(returning: share)
            }
        }
    }

    /// Accepts an incoming share invitation.
    func acceptShare(metadata: CKShare.Metadata) async throws {
        guard let sharedStore = sharedPersistentStore else {
            throw NSError(domain: "PersistenceController", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Shared store not available"])
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            container.acceptShareInvitations(from: [metadata], into: sharedStore) { _, error in
                if let error {
                    Task { @MainActor in
                        self.lastError = error.localizedDescription
                    }
                    continuation.resume(throwing: error)
                } else {
                    AppLogger.sharing.info("Accepted household share invitation")
                    continuation.resume()
                }
            }
        }

        await fetchExistingShare()
    }

    /// Fetches the existing CKShare for the household, if any.
    func fetchExistingShare() async {
        guard let privateStore = privatePersistentStore else { return }

        do {
            let shares = try container.fetchShares(in: privateStore)
            await MainActor.run {
                self.existingShare = shares.first
                self.lastError = nil
            }
            if let share = shares.first {
                AppLogger.sharing.info("Found existing household share with \(share.participants.count) participants")
            } else {
                AppLogger.sharing.info("No existing household share found")
            }
        } catch {
            await MainActor.run {
                self.lastError = error.localizedDescription
            }
            AppLogger.sharing.error("Failed to fetch shares: \(error.localizedDescription)")
        }
    }

    /// Returns the CKShare associated with a specific managed object, if any.
    func fetchShare(for object: NSManagedObject) throws -> CKShare? {
        let shares = try container.fetchShares(matching: [object.objectID])
        return shares[object.objectID]
    }

    /// Persists updates to an existing CKShare.
    func persistUpdatedShare(_ share: CKShare) async throws {
        guard let store = privatePersistentStore ?? sharedPersistentStore else { return }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            container.persistUpdatedShare(share, in: store) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    // MARK: - History Processing

    @objc
    private nonisolated func processRemoteChanges(_ notification: Notification) {
        Task { @MainActor in
            self.processHistory()
        }
    }

    private func processHistory() {
        let stores: [NSPersistentStore] = [privatePersistentStore, sharedPersistentStore].compactMap { $0 }
        guard !stores.isEmpty else { return }

        for store in stores {
            guard let storeID = store.identifier else { continue }
            let token = lastHistoryTokens[storeID]

            let request = NSPersistentHistoryChangeRequest.fetchHistory(after: token)
            if let fetchRequest = NSPersistentHistoryTransaction.fetchRequest {
                fetchRequest.predicate = NSPredicate(format: "author != %@", Self.appTransactionAuthor)
                request.fetchRequest = fetchRequest
            }
            request.affectedStores = [store]

            let context = newBackgroundContext()
            context.performAndWait {
                do {
                    let result = try context.execute(request) as? NSPersistentHistoryResult
                    guard let transactions = result?.result as? [NSPersistentHistoryTransaction],
                          !transactions.isEmpty else { return }

                    // Merge remote changes into viewContext
                    for transaction in transactions {
                        self.viewContext.perform {
                            self.viewContext.mergeChanges(fromContextDidSave: transaction.objectIDNotification())
                        }
                    }

                    // Update token — archive and persist on this thread
                    if let lastToken = transactions.last?.token {
                        if let data = try? NSKeyedArchiver.archivedData(withRootObject: lastToken, requiringSecureCoding: true) {
                            let url = NSPersistentContainer.defaultDirectoryURL()
                                .appendingPathComponent("HistoryTokens", isDirectory: true)
                                .appendingPathComponent("\(storeID).token")
                            try? data.write(to: url)
                        }
                    }

                    // Deduplicate new objects in private store only
                    if store == self.privatePersistentStore {
                        self.deduplicateIfNeeded(transactions: transactions, in: context)
                    }
                } catch {
                    AppLogger.swiftData.error("Failed to process history for store \(storeID): \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Deduplication

    /// Deduplicates objects that arrived from CloudKit by keeping the lowest UUID.
    private func deduplicateIfNeeded(transactions: [NSPersistentHistoryTransaction], in context: NSManagedObjectContext) {
        let entityNames = ["Household", "Recipe", "Ingredient", "User", "WeekPlan",
                           "MealSlot", "MealArchetype", "GroceryItem", "FoodItem",
                           "RecipeIngredient", "SuggestionMemory"]

        for transaction in transactions {
            guard let changes = transaction.changes else { continue }

            for change in changes where change.changeType == .insert {
                let entityName = change.changedObjectID.entity.name ?? ""
                guard entityNames.contains(entityName) else { continue }

                // Fetch the inserted object to get its UUID
                guard let inserted = try? context.existingObject(with: change.changedObjectID),
                      let insertedUUID = inserted.value(forKey: "id") as? UUID else { continue }

                // Find duplicates with same UUID
                let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: entityName)
                fetchRequest.predicate = NSPredicate(format: "id == %@", insertedUUID as CVarArg)
                fetchRequest.affectedStores = [privatePersistentStore].compactMap { $0 }

                guard let duplicates = try? context.fetch(fetchRequest), duplicates.count > 1 else { continue }

                // Keep the one with the "lowest" objectID (deterministic across peers)
                let sorted = duplicates.sorted {
                    $0.objectID.uriRepresentation().absoluteString < $1.objectID.uriRepresentation().absoluteString
                }
                for duplicate in sorted.dropFirst() {
                    context.delete(duplicate)
                }
            }
        }

        if context.hasChanges {
            do {
                try context.save()
                AppLogger.swiftData.info("Deduplicated CloudKit records")
            } catch {
                AppLogger.swiftData.error("Failed to save deduplication: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - History Token Persistence

    private func loadHistoryTokens() {
        guard let files = try? FileManager.default.contentsOfDirectory(at: tokenDirectory, includingPropertiesForKeys: nil) else { return }

        for file in files where file.pathExtension == "token" {
            let storeID = file.deletingPathExtension().lastPathComponent
            if let data = try? Data(contentsOf: file),
               let token = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSPersistentHistoryToken.self, from: data) {
                lastHistoryTokens[storeID] = token
            }
        }
    }

    private func saveHistoryToken(_ token: NSPersistentHistoryToken, for storeID: String) {
        let url = tokenDirectory.appendingPathComponent("\(storeID).token")
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true) {
            try? data.write(to: url)
        }
    }

    // MARK: - Schema Initialization (Debug Only)

    #if DEBUG
    private func initializeSchemaIfNeeded() {
        // Only initialize schema during development to push the Core Data model to CloudKit
        // This is a no-op in production builds
        do {
            try container.initializeCloudKitSchema(options: [])
            AppLogger.swiftData.info("CloudKit schema initialized")
        } catch {
            // Schema initialization failure is non-fatal — schema may already exist
            AppLogger.swiftData.warning("CloudKit schema initialization: \(error.localizedDescription)")
        }
    }
    #endif
}

// MARK: - Environment Access

extension PersistenceController {
    /// Access the shared controller from views.
    /// Use `PersistenceController.shared` directly — no environment key needed
    /// since the controller is a singleton and @MainActor isolated.
}
