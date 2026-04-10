#if os(iOS)
import CoreData
import CloudKit
import CoreTransferable

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

            // Return existing share if one already exists
            if let shareSet = try? container.fetchShares(matching: [objectID]),
               let (_, share) = shareSet.first {
                return .existing(share, container: ckContainer)
            }

            // Create a new share
            return .prepareShare(container: ckContainer) {
                let container = PersistenceController._persistentContainer!
                let obj = await container.viewContext.perform {
                    container.viewContext.object(with: objectID)
                }
                let (_, share, _) = try await container.share([obj], to: nil)
                share[CKShare.SystemFieldKey.title] = "TableTogether Household" as CKRecordValue
                share.publicPermission = .none
                return share
            }
        }
    }
}

// MARK: - CKShare sharing via ShareLink (for resending existing invites)

extension CKShare: @preconcurrency @retroactive Transferable {
    public nonisolated static var transferRepresentation: some TransferRepresentation {
        CKShareTransferRepresentation { share in
            .existing(share, container: CKContainer(identifier: PersistenceController.cloudKitContainerID))
        }
    }
}
#endif
