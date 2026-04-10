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

    /// Rich participant data including name, contact info, and acceptance status.
    var householdMembers: [HouseholdMember] {
        guard let share = existingShare else { return [] }
        let localLabel = PendingInvitationStore.label(forShareRecordName: share.recordID.recordName)
        return share.participants
            .filter { $0.role != .owner }
            .enumerated()
            .map { index, participant in
                // CloudKit reveals the participant's identity only after they accept.
                // For pending invites, fall back to the local label the owner typed
                // when sending the invitation.
                let formattedName = participant.userIdentity.nameComponents.flatMap {
                    PersonNameComponentsFormatter.localizedString(from: $0, style: .default)
                }
                let email = participant.userIdentity.lookupInfo?.emailAddress
                let phone = participant.userIdentity.lookupInfo?.phoneNumber

                let displayName = formattedName ?? email ?? phone ?? localLabel ?? "Pending invitation"

                let status: HouseholdMember.Status = switch participant.acceptanceStatus {
                case .accepted: .accepted
                case .removed: .removed
                case .pending: .pending
                case .unknown: .pending
                @unknown default: .pending
                }

                // Stable per-participant ID. Prefer the CloudKit user record name if
                // available; fall back to email, then phone, then a positional index
                // so two pending invitations don't collapse into one row.
                let participantID = participant.userIdentity.userRecordID?.recordName
                    ?? email
                    ?? phone
                    ?? "pending-\(index)"

                return HouseholdMember(
                    id: participantID,
                    name: displayName,
                    email: email,
                    phone: phone,
                    status: status
                )
            }
    }

    /// Represents a household member with their sharing status and contact details.
    struct HouseholdMember: Identifiable {
        let id: String
        let name: String
        let email: String?
        let phone: String?
        let status: Status

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

    /// Maps a store identifier (UUID string) to a friendly name ("private" / "shared").
    func friendlyStoreName(for storeIdentifier: String) -> String {
        if storeIdentifier == privatePersistentStore?.identifier { return "private" }
        if storeIdentifier == sharedPersistentStore?.identifier { return "shared" }
        return "unknown"
    }

    // MARK: - Sync Health

    /// Recent mirroring events for diagnostics (ring buffer, last 20).
    private(set) var lastSyncEvents: [SyncEventInfo] = []

    /// Whether the shared store is syncing without zone errors.
    private(set) var sharedStoreHealthy = true

    /// Whether a sync recovery operation is in progress.
    private(set) var syncRecoveryInProgress = false

    /// Number of automatic recovery attempts since last success.
    private(set) var recoveryAttemptCount = 0

    @ObservationIgnored
    private var lastRecoveryAttempt: Date?

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

    /// Notification observer tokens for closure-based observers.
    /// Closure-based observers avoid the @objc thunk that inherits @MainActor
    /// isolation from the class, which causes runtime traps when CoreData fires
    /// notifications on background threads (Thread 2 SIGTRAP).
    @ObservationIgnored
    private var remoteChangeObserver: Any?
    @ObservationIgnored
    private var cloudKitEventObserver: Any?

    // MARK: - Initialization

    /// Locate the Core Data model in either the SPM resource bundle or the main bundle.
    /// Both locations are used: the app bundle (via XcodeGen sources) for normal launches,
    /// and the SPM resource bundle for hostless test targets that don't load the app.
    private static func loadManagedObjectModel() -> NSManagedObjectModel {
        #if SWIFT_PACKAGE
        if let url = Bundle.module.url(forResource: "TableTogether", withExtension: "momd"),
           let model = NSManagedObjectModel(contentsOf: url) {
            return model
        }
        #endif
        if let url = Bundle.main.url(forResource: "TableTogether", withExtension: "momd"),
           let model = NSManagedObjectModel(contentsOf: url) {
            return model
        }
        fatalError("Failed to load Core Data model 'TableTogether' from any bundle")
    }

    init(inMemory: Bool = false) {
        let model = Self.loadManagedObjectModel()
        container = NSPersistentCloudKitContainer(name: "TableTogether", managedObjectModel: model)

        if inMemory {
            let description = NSPersistentStoreDescription()
            description.type = NSInMemoryStoreType
            container.persistentStoreDescriptions = [description]
        } else {
            let storeDirectory = NSPersistentContainer.defaultDirectoryURL()

            // Private store — owner's data, syncs to CloudKit private database.
            // Uses the default configuration (no named configuration) to match
            // Apple's CoreDataCloudKitShare sample pattern.
            let privateDescription = NSPersistentStoreDescription(
                url: storeDirectory.appendingPathComponent("private.sqlite")
            )
            privateDescription.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
                containerIdentifier: Self.cloudKitContainerID
            )
            privateDescription.cloudKitContainerOptions?.databaseScope = .private
            privateDescription.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            privateDescription.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

            // Shared store — data shared BY OTHER USERS with this device.
            // Owner's own data always lives in the private store; the shared store
            // is populated automatically when the user accepts an invitation.
            let sharedDescription = NSPersistentStoreDescription(
                url: storeDirectory.appendingPathComponent("shared.sqlite")
            )
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

        // Register for remote changes AFTER stores are loaded.
        // Use closure-based observers so the callback runs on the posting
        // thread without going through an @objc thunk that would inherit
        // @MainActor isolation and trap at runtime (SIGTRAP on Thread 2).
        remoteChangeObserver = NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: container.persistentStoreCoordinator,
            queue: nil
        ) { [weak self] notification in
            self?.processRemoteChanges(notification)
        }

        // Observe CloudKit mirroring events for sync health monitoring
        cloudKitEventObserver = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: container,
            queue: nil
        ) { [weak self] notification in
            self?.handleCloudKitEvent(notification)
        }

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

        let share: CKShare = try await withCheckedThrowingContinuation { continuation in
            container.share([household], to: nil) { _, share, _, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let share else {
                    let err = NSError(domain: "PersistenceController", code: 1,
                                      userInfo: [NSLocalizedDescriptionKey: "Share creation returned nil"])
                    continuation.resume(throwing: err)
                    return
                }

                continuation.resume(returning: share)
            }
        }

        // Configure and persist the share on MainActor (where viewContext lives)
        share[CKShare.SystemFieldKey.title] = "TableTogether Household" as CKRecordValue
        share.publicPermission = .none
        try viewContext.save()

        self.existingShare = share
        self.lastError = nil
        return share
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
            PendingInvitationStore.removeLabel(forShareRecordName: share.recordID.recordName)
            existingShare = nil
            AppLogger.sharing.info("Purged shared objects and records")
        } catch {
            AppLogger.sharing.error("Failed to purge: \(error.localizedDescription)")
        }
    }

    /// Removes a single participant from the existing CKShare and persists the change.
    /// Used by the household member detail sheet to revoke a specific invite without
    /// stopping sharing entirely. If the removed participant was the last non-owner,
    /// the share itself is preserved (the owner can still re-invite later).
    /// - Parameter memberID: The stable participant ID from `HouseholdMember.id`.
    /// - Throws: A CloudKit error if the share update cannot be persisted.
    func removeParticipant(matching memberID: String) async throws {
        guard let share = existingShare else {
            AppLogger.sharing.warning("removeParticipant called with no existing share")
            return
        }
        guard let store = privatePersistentStore else {
            AppLogger.sharing.warning("removeParticipant called with no private store")
            return
        }

        // Resolve the participant by the same ID rule used in householdMembers.
        let pendingParticipants = share.participants
            .filter { $0.role != .owner }
            .enumerated()
        let resolved = pendingParticipants.first { index, participant in
            let id = participant.userIdentity.userRecordID?.recordName
                ?? participant.userIdentity.lookupInfo?.emailAddress
                ?? participant.userIdentity.lookupInfo?.phoneNumber
                ?? "pending-\(index)"
            return id == memberID
        }

        guard let (_, participant) = resolved else {
            AppLogger.sharing.warning("removeParticipant: no participant matches id \(memberID)")
            return
        }

        share.removeParticipant(participant)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            container.persistUpdatedShare(share, in: store) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }

        // Refresh local share state so the UI updates.
        await fetchExistingShare()
        AppLogger.sharing.info("Removed participant \(memberID) from share")
    }

    // MARK: - History Processing (Serial Queue, Off Main Thread)

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

    // MARK: - CloudKit Mirroring Event Observer

    private nonisolated func handleCloudKitEvent(_ notification: Notification) {
        guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                as? NSPersistentCloudKitContainer.Event else { return }

        // Only track completed events (endDate != nil), not start events
        guard event.endDate != nil else { return }

        // Extract event data on the calling thread (CloudKit's background queue)
        let eventType: String = switch event.type {
        case .setup: "setup"
        case .import: "import"
        case .export: "export"
        @unknown default: "unknown"
        }

        let storeID = event.storeIdentifier
        let succeeded = event.succeeded
        let errorMessage = event.error?.localizedDescription
        let needsRecovery = !succeeded && isStaleZoneError(event.error)

        if let errorMessage {
            AppLogger.sync.error("CloudKit \(eventType) failed for store \(storeID): \(errorMessage)")
        } else if succeeded {
            AppLogger.sync.info("CloudKit \(eventType) succeeded for store \(storeID)")
        }

        // Dispatch state mutations to MainActor
        Task { @MainActor in
            let info = SyncEventInfo(
                storeIdentifier: storeID,
                eventType: eventType,
                succeeded: succeeded,
                error: errorMessage,
                timestamp: Date()
            )
            self.lastSyncEvents.append(info)
            if self.lastSyncEvents.count > 20 {
                self.lastSyncEvents.removeFirst(self.lastSyncEvents.count - 20)
            }

            if needsRecovery,
               storeID == self.sharedPersistentStore?.identifier {
                self.sharedStoreHealthy = false
                await self.attemptSharedStoreRecovery()
            } else if succeeded, storeID == self.sharedPersistentStore?.identifier {
                self.sharedStoreHealthy = true
                self.recoveryAttemptCount = 0
            }
        }
    }

    /// Check whether a CKError indicates stale zone references.
    private nonisolated func isStaleZoneError(_ error: Error?) -> Bool {
        guard let error else { return false }
        let nsError = error as NSError

        // Direct CKError zone-not-found or unknown-item
        if nsError.domain == CKError.errorDomain {
            if nsError.code == CKError.zoneNotFound.rawValue ||
               nsError.code == CKError.unknownItem.rawValue {
                return true
            }
            // Check partial errors
            if nsError.code == CKError.partialFailure.rawValue,
               let partialErrors = nsError.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: Error] {
                return partialErrors.values.contains { partialError in
                    let code = (partialError as NSError).code
                    return code == CKError.zoneNotFound.rawValue || code == CKError.unknownItem.rawValue
                }
            }
        }

        // Check underlying error
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
            return isStaleZoneError(underlying)
        }

        return false
    }

    // MARK: - Sync Recovery

    /// Attempt automatic recovery of the shared store with backoff.
    private func attemptSharedStoreRecovery() async {
        guard !syncRecoveryInProgress else { return }
        guard recoveryAttemptCount < 3 else {
            storeLoadError = "CloudKit sync failed repeatedly. Use CloudKit Diagnostics to reset sync data."
            AppLogger.sync.error("Shared store recovery exhausted (3 attempts)")
            return
        }
        if let last = lastRecoveryAttempt, Date().timeIntervalSince(last) < 300 {
            AppLogger.sync.info("Skipping recovery — last attempt was \(Int(Date().timeIntervalSince(last)))s ago")
            return
        }

        await resetSharedStore()
    }

    /// Delete and recreate the shared persistent store to clear stale zone metadata.
    func resetSharedStore() async {
        guard !syncRecoveryInProgress else { return }

        syncRecoveryInProgress = true
        recoveryAttemptCount += 1
        lastRecoveryAttempt = Date()
        AppLogger.sync.info("Resetting shared store (attempt \(recoveryAttemptCount))")

        let coordinator = container.persistentStoreCoordinator

        // Remove the shared store
        if let store = sharedPersistentStore {
            let storeURL = store.url
            let tokenKey = Self.tokenPrefix + store.identifier

            do {
                try coordinator.remove(store)
                sharedPersistentStore = nil

                // Delete SQLite files
                if let url = storeURL {
                    for suffix in ["", "-wal", "-shm"] {
                        let fileURL = url.appendingPathExtension(suffix.isEmpty ? "" : String(suffix.dropFirst()))
                        let actualURL = suffix.isEmpty ? url : URL(fileURLWithPath: url.path + suffix)
                        try? FileManager.default.removeItem(at: actualURL)
                    }
                }

                // Clear history token
                UserDefaults.standard.removeObject(forKey: tokenKey)

                AppLogger.sync.info("Removed shared store and cleared metadata")
            } catch {
                AppLogger.sync.error("Failed to remove shared store: \(error.localizedDescription)")
                syncRecoveryInProgress = false
                return
            }
        }

        // Re-add the shared store (uses default configuration)
        let storeDirectory = NSPersistentContainer.defaultDirectoryURL()
        let sharedDescription = NSPersistentStoreDescription(
            url: storeDirectory.appendingPathComponent("shared.sqlite")
        )
        let sharedOptions = NSPersistentCloudKitContainerOptions(
            containerIdentifier: Self.cloudKitContainerID
        )
        sharedOptions.databaseScope = .shared
        sharedDescription.cloudKitContainerOptions = sharedOptions
        sharedDescription.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        sharedDescription.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

        do {
            guard let storeURL = sharedDescription.url else {
                AppLogger.sync.error("Shared store description has no URL")
                syncRecoveryInProgress = false
                return
            }
            let newStore = try coordinator.addPersistentStore(
                type: .sqlite,
                at: storeURL,
                options: sharedDescription.options
            )
            sharedPersistentStore = newStore
            sharedStoreHealthy = true
            AppLogger.sync.info("Shared store recreated successfully")
        } catch {
            AppLogger.sync.error("Failed to recreate shared store: \(error.localizedDescription)")
            storeLoadError = "Failed to recreate shared store: \(error.localizedDescription)"
        }

        syncRecoveryInProgress = false
    }

    /// Delete both stores and re-sync from CloudKit. Nuclear recovery option.
    func resetAllSyncData() async {
        guard !syncRecoveryInProgress else { return }
        syncRecoveryInProgress = true
        AppLogger.sync.warning("Resetting ALL sync data — will re-download from CloudKit")

        let coordinator = container.persistentStoreCoordinator

        // Remove all stores
        for store in coordinator.persistentStores {
            let url = store.url
            let tokenKey = Self.tokenPrefix + store.identifier
            do {
                try coordinator.remove(store)
                if let url {
                    for suffix in ["", "-wal", "-shm"] {
                        let actualURL = suffix.isEmpty ? url : URL(fileURLWithPath: url.path + suffix)
                        try? FileManager.default.removeItem(at: actualURL)
                    }
                }
                UserDefaults.standard.removeObject(forKey: tokenKey)
            } catch {
                AppLogger.sync.error("Failed to remove store: \(error.localizedDescription)")
            }
        }

        privatePersistentStore = nil
        sharedPersistentStore = nil
        existingShare = nil

        // Re-add stores manually (loadPersistentStores requires descriptions)
        let storeDirectory = NSPersistentContainer.defaultDirectoryURL()

        // Private store
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

        // Shared store
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

        container.loadPersistentStores { description, error in
            if let error {
                AppLogger.sync.fault("Failed to reload store '\(description.configuration ?? "default")': \(error.localizedDescription)")
                self.storeLoadError = error.localizedDescription
                return
            }
            if let url = description.url,
               let store = self.container.persistentStoreCoordinator.persistentStore(for: url) {
                if description.cloudKitContainerOptions?.databaseScope == .shared {
                    self.sharedPersistentStore = store
                } else {
                    self.privatePersistentStore = store
                }
            }
        }
        sharedStoreHealthy = true
        recoveryAttemptCount = 0
        lastSyncEvents.removeAll()
        syncRecoveryInProgress = false
        AppLogger.sync.info("All sync data reset — waiting for CloudKit re-sync")
    }
}

// MARK: - Sync Event Info

struct SyncEventInfo: Identifiable {
    let id = UUID()
    let storeIdentifier: String
    let eventType: String
    let succeeded: Bool
    let error: String?
    let timestamp: Date

}
