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

    /// Non-isolated reference to the persistent container for Transferable
    /// conformances that run outside MainActor. Set once during init.
    @ObservationIgnored
    nonisolated(unsafe) private(set) static var _persistentContainer: NSPersistentCloudKitContainer!

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

    /// Tracks whether orphaned share cleanup has already run for private store zone errors. #70
    @ObservationIgnored
    private var privateStoreOrphanCleanupDone = false

    // MARK: - Constants

    nonisolated static let cloudKitContainerID = "iCloud.dev.dreamfold.tabletogether"
    nonisolated static let appTransactionAuthor = "TableTogether"
    nonisolated static let tokenPrefix = "HistoryToken_"

    /// Store filenames — single source of truth so the private/shared store can be identified
    /// from a `nonisolated` history-processing context (which can't touch the @MainActor
    /// store properties) by matching the store URL.
    nonisolated static let privateStoreFileName = "private.sqlite"
    nonisolated static let sharedStoreFileName = "shared.sqlite"

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
        Self._persistentContainer = container

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
                url: storeDirectory.appendingPathComponent(Self.privateStoreFileName)
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
                url: storeDirectory.appendingPathComponent(Self.sharedStoreFileName)
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

    /// Accepts an incoming share invitation.
    func acceptShare(metadata: CKShare.Metadata) async throws {
        guard let sharedStore = sharedPersistentStore else {
            throw NSError(domain: "PersistenceController", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Shared store not available"])
        }

        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                container.acceptShareInvitations(from: [metadata], into: sharedStore) { _, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        AppLogger.sharing.info("Accepted household share invitation")
                        continuation.resume()
                    }
                }
            }
        } catch {
            lastError = error.localizedDescription
            throw error
        }

        await fetchExistingShare()
    }

    /// Fetches the existing CKShare for the household, if any.
    /// Filters out orphaned shares (nil URL) so the app doesn't try to use them. #70
    ///
    /// Note: we intentionally do NOT call `purgeObjectsAndRecordsInZone` here.
    /// `container.share([obj], to: nil)` moves managed objects into the share zone,
    /// so purging would delete the Household and all linked records (recipes, ingredients,
    /// meal plans). The orphaned share zone causes a "Zone Not Found" sync loop, but
    /// that is preferable to data loss. Users can recover via "Reset All Sync Data"
    /// in CloudKit Diagnostics, which clears local stores and re-downloads from CloudKit.
    func fetchExistingShare() async {
        // The owner's share lives in the private store; a participant's accepted share
        // lives in the shared store. Check both — querying only the private store left
        // participants with blank isSharing/participantCount/householdMembers and made
        // stop-sharing cleanup (which keys off existingShare) unreachable for them.
        var stores: [NSPersistentStore] = []
        if let privateStore = privatePersistentStore { stores.append(privateStore) }
        if let sharedStore = sharedPersistentStore { stores.append(sharedStore) }
        guard !stores.isEmpty else { return }

        do {
            var shares: [CKShare] = []
            for store in stores {
                shares.append(contentsOf: try container.fetchShares(in: store))
            }

            if shares.contains(where: { $0.url == nil }) {
                AppLogger.sharing.fault("Found orphaned share(s) with nil URL — filtering out. Use 'Reset All Sync Data' to clean up.")
            }

            // Use only valid shares (with a CloudKit URL)
            existingShare = shares.first(where: { $0.url != nil })
            lastError = nil
            if let share = existingShare {
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

    /// Whether the current iCloud user owns this share (i.e. created the household share).
    ///
    /// This distinction is critical when sharing stops: the owner's records were *moved* into
    /// the share zone of their own **private** store, so the owner must never purge. A
    /// participant only holds a mirror in the **shared** store, which is safe to purge.
    /// If participation can't be determined we conservatively treat the user as a participant —
    /// safe because the purge below only ever touches the shared store, never the owner's data.
    func isCurrentUserOwner(of share: CKShare) -> Bool {
        share.currentUserParticipant?.role == .owner
    }

    /// Handles the system "Stop Sharing" / "Remove Me" action (UICloudSharingController delegate).
    ///
    /// - Owner: CloudKit tears down the CKShare and demotes the records back into the owner's
    ///   private store. We must NOT purge — purging the zone would delete the Household and all
    ///   linked records (recipes, ingredients, meal plans). #70. We only clear local share state.
    /// - Participant: we remove our local mirror from the shared store (see `purgeSharedMirror`).
    func handleStoppedSharing(_ share: CKShare) async {
        if isCurrentUserOwner(of: share) {
            AppLogger.sharing.info("Owner stopped sharing — preserving household data, clearing local share state")
            existingShare = nil
        } else {
            await purgeSharedMirror(for: share)
        }
        await fetchExistingShare()
    }

    /// Removes the local mirror of a shared household after the current user (a *participant*)
    /// leaves. This purges only the participant's copy from the **shared** store; it never
    /// touches the owner's private store, so it cannot delete the real household data (#70).
    /// Never call this for the share owner.
    private func purgeSharedMirror(for share: CKShare) async {
        guard !isCurrentUserOwner(of: share) else {
            AppLogger.sharing.error("purgeSharedMirror called for the share owner — refusing to avoid data loss")
            return
        }
        guard let store = sharedPersistentStore else { return }
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
            AppLogger.sharing.info("Purged local shared mirror after leaving household")
        } catch {
            AppLogger.sharing.error("Failed to purge shared mirror: \(error.localizedDescription)")
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

            // Merge remote changes into viewContext IN ORDER, then persist the token —
            // all in a single MainActor hop. Dispatching each transaction as its own
            // detached Task gave no ordering guarantee, and saving the token synchronously
            // before those merges ran could advance the token past not-yet-merged
            // transactions (lost on a kill in between). historyQueue is serial, and
            // mergeChanges is idempotent, so re-processing after a stale-token read is safe.
            // objectIDNotification() yields non-Sendable NSNotifications, but their payload is
            // only NSManagedObjectIDs, which are safe to transfer across the actor hop below.
            nonisolated(unsafe) let notifications = transactions.map { $0.objectIDNotification() }
            let lastToken = transactions.last?.token
            let tokenData: Data? = lastToken.flatMap {
                try? NSKeyedArchiver.archivedData(withRootObject: $0, requiringSecureCoding: true)
            }
            Task { @MainActor in
                for notification in notifications {
                    self.viewContext.mergeChanges(fromContextDidSave: notification)
                }
                if let tokenData {
                    UserDefaults.standard.set(tokenData, forKey: tokenKey)
                }
            }

            // Deduplicate in the private store only. Identify it by URL since this is a
            // nonisolated context. The shared store holds another user's authoritative
            // records; deduping there could delete legitimately-distinct rows.
            let isSharedStore = store.url?.lastPathComponent == Self.sharedStoreFileName
            if !isSharedStore {
                deduplicateIfNeeded(transactions: transactions, in: context, store: store)
            }
        } catch {
            AppLogger.swiftData.error("Failed to process history for store \(storeUUID): \(error.localizedDescription)")
        }
    }

    // MARK: - Deduplication

    private nonisolated func deduplicateIfNeeded(transactions: [NSPersistentHistoryTransaction], in context: NSManagedObjectContext, store: NSPersistentStore) {
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
                // Scope to the originating store: with two stores a same-id row can exist in
                // both (e.g. the deterministic Household.defaultID). An unscoped fetch could
                // delete the row in the other store.
                fetchRequest.affectedStores = [store]

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
            } else if needsRecovery,
                      storeID == self.privatePersistentStore?.identifier,
                      !self.privateStoreOrphanCleanupDone {
                // Private store "Zone Not Found" — orphaned share zone from a cancelled
                // share creation. Log once per session. Cannot purge automatically because
                // purgeObjectsAndRecordsInZone deletes the Household and all shared objects.
                // User must use "Reset All Sync Data" in CloudKit Diagnostics to recover. #70
                self.privateStoreOrphanCleanupDone = true
                AppLogger.sync.fault("Private store zone error detected — orphaned share zone. Use 'Reset All Sync Data' to clean up.")
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
            url: storeDirectory.appendingPathComponent(Self.sharedStoreFileName)
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
            url: storeDirectory.appendingPathComponent(Self.privateStoreFileName)
        )
        // Use the default configuration (no named configuration) to match init()
        // and resyncSharedStore — the model defines no "Private"/"Shared"
        // configurations, so naming one would throw 134080 and reload nothing.
        privateDescription.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
            containerIdentifier: Self.cloudKitContainerID
        )
        privateDescription.cloudKitContainerOptions?.databaseScope = .private
        privateDescription.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        privateDescription.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

        // Shared store
        let sharedDescription = NSPersistentStoreDescription(
            url: storeDirectory.appendingPathComponent(Self.sharedStoreFileName)
        )
        let sharedOptions = NSPersistentCloudKitContainerOptions(
            containerIdentifier: Self.cloudKitContainerID
        )
        sharedOptions.databaseScope = .shared
        sharedDescription.cloudKitContainerOptions = sharedOptions
        sharedDescription.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        sharedDescription.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

        container.persistentStoreDescriptions = [privateDescription, sharedDescription]

        // Clear any prior load error so the post-reload check reflects only this attempt.
        storeLoadError = nil
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

        // loadPersistentStores fires its completion synchronously for SQLite stores,
        // so storeLoadError is current here. Only declare recovery healthy if the
        // reload actually succeeded — otherwise we'd mask a genuine load failure.
        syncRecoveryInProgress = false
        if storeLoadError == nil {
            sharedStoreHealthy = true
            recoveryAttemptCount = 0
            lastSyncEvents.removeAll()
            AppLogger.sync.info("All sync data reset — waiting for CloudKit re-sync")
        } else {
            AppLogger.sync.fault("All sync data reset failed to reload stores: \(storeLoadError ?? "unknown")")
        }
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
