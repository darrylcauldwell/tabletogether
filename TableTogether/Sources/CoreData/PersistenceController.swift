@preconcurrency import CoreData
import CloudKit
import SwiftUI
import Observation
import os

/// Unified persistence controller managing Core Data with CloudKit sharing.
///
/// Architecture matches Apple's CoreDataCloudKitShare sample:
/// - NSPersistentCloudKitContainer with dual stores (private + shared)
/// - Serial OperationQueue for history processing (off main thread)
/// - UserDefaults-based history token persistence
/// - CloudKit sharing lifecycle (create, accept, fetch shares)
@Observable
@MainActor
final class PersistenceController {

    // MARK: - Singleton & Preview

    static let shared = PersistenceController()

    static let preview: PersistenceController = {
        let controller = PersistenceController(inMemory: true)
        let context = controller.viewContext
        let household = Household(context: context)
        household.id = UUID()
        household.name = "Preview Household"
        household.createdAt = Date()
        try? context.save()
        return controller
    }()

    // MARK: - Container & Stores

    let container: NSPersistentCloudKitContainer

    /// The private persistent store (owner's data). Set during init, always available after.
    private(set) var privatePersistentStore: NSPersistentStore?

    /// The shared persistent store (data shared by others). Set during init, always available after.
    private(set) var sharedPersistentStore: NSPersistentStore?

    /// Error from store loading, if any. Observable so UI can show error state.
    private(set) var storeLoadError: String?

    @ObservationIgnored
    private(set) lazy var ckContainer = CKContainer(identifier: Self.cloudKitContainerID)

    var viewContext: NSManagedObjectContext { container.viewContext }

    // MARK: - Sharing State

    private(set) var existingShare: CKShare?

    var isSharing: Bool { existingShare != nil }

    var participantCount: Int {
        guard let share = existingShare else { return 0 }
        return share.participants.count - 1
    }

    var participantNames: [String] {
        householdMembers.map(\.name)
    }

    /// Rich participant data including name and acceptance status.
    var householdMembers: [HouseholdMember] {
        guard let share = existingShare else { return [] }
        return share.participants
            .filter { $0.role != .owner }
            .map { participant in
                let name = participant.userIdentity.nameComponents.flatMap {
                    PersonNameComponentsFormatter.localizedString(from: $0, style: .default)
                } ?? participant.userIdentity.lookupInfo?.emailAddress
                  ?? participant.userIdentity.lookupInfo?.phoneNumber
                  ?? "Invited Person"

                let status: HouseholdMember.Status = switch participant.acceptanceStatus {
                case .accepted: .accepted
                case .removed: .removed
                case .pending: .pending
                @unknown default: .pending
                }

                return HouseholdMember(name: name, status: status)
            }
    }

    /// Represents a household member with their sharing status.
    struct HouseholdMember: Identifiable {
        let name: String
        let status: Status
        var id: String { name }

        enum Status {
            case pending
            case accepted
            case removed

            var label: String {
                switch self {
                case .pending: "Invite Sent"
                case .accepted: "Joined"
                case .removed: "Removed"
                }
            }

            var iconName: String {
                switch self {
                case .pending: "envelope.circle.fill"
                case .accepted: "checkmark.circle.fill"
                case .removed: "xmark.circle.fill"
                }
            }

            var color: String {
                switch self {
                case .pending: "orange"
                case .accepted: "green"
                case .removed: "red"
                }
            }
        }
    }

    private(set) var lastError: String?

    // MARK: - Constants

    static let cloudKitContainerID = "iCloud.dev.dreamfold.tabletogether"
    nonisolated(unsafe) static let appTransactionAuthor = "TableTogether"
    nonisolated(unsafe) static let tokenPrefix = "HistoryToken_"

    // MARK: - Sharing UI Observer

    #if os(iOS)
    /// Observes system sharing UI events (save/stop) to keep local state in sync.
    @ObservationIgnored
    private var sharingUIObserver: CKSystemSharingUIObserver?
    #endif

    // MARK: - History Processing Queue

    /// Serial queue for processing persistent history (off main thread, matches Apple's sample).
    @ObservationIgnored
    private let historyQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.name = "PersistenceController.historyQueue"
        return queue
    }()

    // MARK: - Initialization

    init(inMemory: Bool = false) {
        container = NSPersistentCloudKitContainer(name: "TableTogether")

        if inMemory {
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

        // loadPersistentStores fires completion synchronously for SQLite stores
        // (shouldAddStoreAsynchronously defaults to false). Stores are ready when this returns.
        container.loadPersistentStores { description, error in
            if let error {
                AppLogger.swiftData.fault("Failed to load store '\(description.configuration ?? "default")': \(error.localizedDescription)")
                self.storeLoadError = error.localizedDescription
                return
            }

            // Capture store references
            if let url = description.url,
               let store = self.container.persistentStoreCoordinator.persistentStore(for: url) {
                if description.cloudKitContainerOptions?.databaseScope == .shared {
                    self.sharedPersistentStore = store
                } else {
                    self.privatePersistentStore = store
                }
            }
        }

        // Configure viewContext
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
        container.viewContext.transactionAuthor = Self.appTransactionAuthor

        // Register for remote changes AFTER stores are loaded
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(processRemoteChanges),
            name: .NSPersistentStoreRemoteChange,
            object: container.persistentStoreCoordinator
        )

        // Set up CKSystemSharingUIObserver to monitor system sharing UI events
        #if os(iOS)
        if !inMemory {
            let observer = CKSystemSharingUIObserver(container: ckContainer)
            observer.systemSharingUIDidSaveShareBlock = { [weak self] _, result in
                Task { @MainActor in
                    await self?.fetchExistingShare()
                }
            }
            observer.systemSharingUIDidStopSharingBlock = { [weak self] _, result in
                Task { @MainActor in
                    self?.existingShare = nil
                    await self?.fetchExistingShare()
                }
            }
            self.sharingUIObserver = observer
        }
        #endif

        #if DEBUG
        if !inMemory {
            do {
                try container.initializeCloudKitSchema(options: [])
                AppLogger.swiftData.info("CloudKit schema initialized")
            } catch {
                AppLogger.swiftData.warning("CloudKit schema init: \(error.localizedDescription)")
            }
        }
        #endif
    }

    // MARK: - Background Context

    func newBackgroundContext() -> NSManagedObjectContext {
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
        context.transactionAuthor = Self.appTransactionAuthor
        return context
    }

    // MARK: - Store Queries

    func isOwned(object: NSManagedObject) -> Bool {
        guard let store = object.objectID.persistentStore else { return true }
        return store == privatePersistentStore
    }

    func canEdit(object: NSManagedObject) -> Bool {
        if isOwned(object: object) { return true }
        return container.canUpdateRecord(forManagedObjectWith: object.objectID)
    }

    func canDelete(object: NSManagedObject) -> Bool {
        if isOwned(object: object) { return true }
        return container.canDeleteRecord(forManagedObjectWith: object.objectID)
    }

    // MARK: - Sharing

    /// Creates a CKShare for the given household.
    /// Saves the context first to ensure the object is persisted.
    func shareHousehold(_ household: Household) async throws -> CKShare {
        // Ensure household is saved to the persistent store before sharing
        if viewContext.hasChanges {
            try viewContext.save()
        }

        return try await withCheckedThrowingContinuation { continuation in
            container.share([household], to: nil) { _, share, _, error in
                if let error {
                    self.lastError = error.localizedDescription
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

                self.existingShare = share
                self.lastError = nil
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
                    self.lastError = error.localizedDescription
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
            existingShare = shares.first
            lastError = nil
            if let share = shares.first {
                AppLogger.sharing.info("Found existing share with \(share.participants.count) participants")
            }
        } catch {
            lastError = error.localizedDescription
            AppLogger.sharing.error("Failed to fetch shares: \(error.localizedDescription)")
        }
    }

    /// Returns the CKShare associated with a specific managed object, if any.
    func fetchShare(for object: NSManagedObject) throws -> CKShare? {
        let shares = try container.fetchShares(matching: [object.objectID])
        return shares[object.objectID]
    }

    /// Persists updates to an existing CKShare (called by UICloudSharingController delegate).
    func persistUpdatedShare(_ share: CKShare) async throws {
        guard let store = privatePersistentStore ?? sharedPersistentStore else {
            throw NSError(domain: "PersistenceController", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "No persistent store available"])
        }

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

    /// Purges shared objects and records when sharing stops (called by UICloudSharingController delegate).
    func purgeObjectsAndRecords(for share: CKShare) async {
        guard let store = privatePersistentStore else { return }
        guard let zoneID = share.recordID.zoneID as CKRecordZone.ID? else { return }

        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                container.purgeObjectsAndRecordsInZone(with: zoneID, in: store) { _, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
            existingShare = nil
            AppLogger.sharing.info("Purged shared objects and records")
        } catch {
            AppLogger.sharing.error("Failed to purge: \(error.localizedDescription)")
        }
    }

    // MARK: - History Processing (Serial Queue, Off Main Thread)

    @objc
    private nonisolated func processRemoteChanges(_ notification: Notification) {
        // Extract store UUID from notification (matches Apple's sample pattern)
        guard let storeUUID = notification.userInfo?[NSStoreUUIDKey] as? String else { return }

        historyQueue.addOperation { [weak self] in
            guard let self else { return }
            let context = self.container.newBackgroundContext()
            context.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
            context.performAndWait {
                self.processHistory(storeUUID: storeUUID, context: context)
            }
        }
    }

    private nonisolated func processHistory(storeUUID: String, context: NSManagedObjectContext) {
        // Find the store matching this UUID
        let store = container.persistentStoreCoordinator.persistentStores.first {
            $0.identifier == storeUUID
        }
        guard let store else { return }

        // Load token from UserDefaults
        let tokenKey = Self.tokenPrefix + storeUUID
        let lastToken: NSPersistentHistoryToken? = {
            guard let data = UserDefaults.standard.data(forKey: tokenKey) else { return nil }
            return try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSPersistentHistoryToken.self, from: data)
        }()

        // Fetch history since last token, excluding our own changes
        let request = NSPersistentHistoryChangeRequest.fetchHistory(after: lastToken)
        if let fetchRequest = NSPersistentHistoryTransaction.fetchRequest {
            fetchRequest.predicate = NSPredicate(format: "author != %@", Self.appTransactionAuthor)
            request.fetchRequest = fetchRequest
        }
        request.affectedStores = [store]

        do {
            let result = try context.execute(request) as? NSPersistentHistoryResult
            guard let transactions = result?.result as? [NSPersistentHistoryTransaction],
                  !transactions.isEmpty else { return }

            // Merge remote changes into viewContext
            for transaction in transactions {
                let notification = transaction.objectIDNotification()
                Task { @MainActor in
                    self.viewContext.mergeChanges(fromContextDidSave: notification)
                }
            }

            // Save updated token to UserDefaults
            if let newToken = transactions.last?.token,
               let data = try? NSKeyedArchiver.archivedData(withRootObject: newToken, requiringSecureCoding: true) {
                UserDefaults.standard.set(data, forKey: tokenKey)
            }

            // Deduplicate in private store only (not shared)
            if store.configurationName != "Shared" {
                deduplicateIfNeeded(transactions: transactions, in: context)
            }
        } catch {
            AppLogger.swiftData.error("Failed to process history for store \(storeUUID): \(error.localizedDescription)")
        }
    }

    // MARK: - Deduplication

    private nonisolated func deduplicateIfNeeded(transactions: [NSPersistentHistoryTransaction], in context: NSManagedObjectContext) {
        let entityNames = ["Household", "Recipe", "Ingredient", "User", "WeekPlan",
                           "MealSlot", "MealArchetype", "GroceryItem", "FoodItem",
                           "RecipeIngredient", "SuggestionMemory"]

        for transaction in transactions {
            guard let changes = transaction.changes else { continue }

            for change in changes where change.changeType == .insert {
                let entityName = change.changedObjectID.entity.name ?? ""
                guard entityNames.contains(entityName) else { continue }

                guard let inserted = try? context.existingObject(with: change.changedObjectID),
                      let insertedUUID = inserted.value(forKey: "id") as? UUID else { continue }

                let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: entityName)
                fetchRequest.predicate = NSPredicate(format: "id == %@", insertedUUID as CVarArg)

                guard let duplicates = try? context.fetch(fetchRequest), duplicates.count > 1 else { continue }

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
}
