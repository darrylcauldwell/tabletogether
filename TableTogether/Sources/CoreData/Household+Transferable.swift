#if os(iOS)
import CoreData
import CloudKit
import CoreTransferable
import os

/// Wrapper that makes a Household shareable via SwiftUI's ShareLink.
///
/// NSManagedObject can't conform to Transferable (Sendable is unavailable on iOS),
/// so this struct wraps the household's objectID URI — which IS Sendable — and
/// provides the CKShareTransferRepresentation that handles CloudKit share creation.
struct HouseholdShareItem: Transferable {
    let objectURI: URL

    init(household: Household) {
        self.objectURI = household.objectID.uriRepresentation()
    }

    static var transferRepresentation: some TransferRepresentation {
        CKShareTransferRepresentation { item in
            let container = PersistenceController._persistentContainer!
            let ckContainer = CKContainer(identifier: PersistenceController.cloudKitContainerID)

            // Resolve the managed object from the URI
            let coordinator = container.viewContext.persistentStoreCoordinator
            guard let objectID = coordinator?.managedObjectID(forURIRepresentation: item.objectURI) else {
                fatalError("Cannot resolve Household objectID from URI: \(item.objectURI)")
            }

            // Return existing share if one already exists AND has been saved to CloudKit.
            // Shares with nil URL were created locally but never persisted to the server
            // (e.g. user cancelled the sharing UI). Using them causes "You cannot get the
            // URL of a share until it's been saved to the server" and an infinite sync loop
            // as CoreData tries to import from a non-existent share zone. #70
            if let shareSet = try? container.fetchShares(matching: [objectID]),
               let (_, share) = shareSet.first {
                if share.url != nil {
                    AppLogger.sharing.fault("""
                        Returning existing share — \
                        url: \(share.url?.absoluteString ?? "nil", privacy: .public), \
                        participants: \(share.participants.count), \
                        recordName: \(share.recordID.recordName, privacy: .public)
                        """)
                    return .existing(share, container: ckContainer)
                } else {
                    AppLogger.sharing.fault("""
                        Ignoring orphaned share with nil URL — \
                        recordName: \(share.recordID.recordName, privacy: .public). \
                        Will create new share via prepareShare.
                        """)
                }
            }

            // Create a new share
            AppLogger.sharing.fault("No existing share found — will create new via prepareShare")
            return .prepareShare(container: ckContainer) {
                let container = PersistenceController._persistentContainer!
                let obj = await container.viewContext.perform {
                    container.viewContext.object(with: objectID)
                }
                AppLogger.sharing.fault("Calling container.share() to create CKShare...")
                let (sharedIDs, share, _) = try await container.share([obj], to: nil)
                share[CKShare.SystemFieldKey.title] = "TableTogether Household" as CKRecordValue
                share.publicPermission = .none
                AppLogger.sharing.fault("""
                    Share created — \
                    url: \(share.url?.absoluteString ?? "nil", privacy: .public), \
                    sharedObjectCount: \(sharedIDs.count), \
                    participants: \(share.participants.count), \
                    recordName: \(share.recordID.recordName, privacy: .public), \
                    publicPermission: \(String(describing: share.publicPermission))
                    """)
                return share
            }
        }
    }
}

// MARK: - CKShare sharing via ShareLink (for resending existing invites)

extension CKShare: @retroactive Transferable {
    public nonisolated static var transferRepresentation: some TransferRepresentation {
        CKShareTransferRepresentation { share in
            .existing(share, container: CKContainer(identifier: PersistenceController.cloudKitContainerID))
        }
    }
}
#endif
