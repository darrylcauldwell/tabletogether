#if os(iOS)
import SwiftUI
import CloudKit
import CoreData
import os

/// UIViewControllerRepresentable wrapper for UICloudSharingController.
///
/// UICloudSharingController handles the entire sharing flow internally:
/// - Creates the CKShare and zone on CloudKit (with its own loading spinner)
/// - Generates the share URL
/// - Presents the system share sheet (iMessage, Mail, etc.)
///
/// This avoids the timing issue where ShareLink + CKShareTransferRepresentation
/// hangs because iMessage can't compose without a URL, and the URL isn't ready
/// until CloudKit finishes exporting the share zone. #70
struct CloudSharingView: UIViewControllerRepresentable {
    let household: Household
    let persistenceController: PersistenceController

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let container = persistenceController.container
        let ckContainer = CKContainer(identifier: PersistenceController.cloudKitContainerID)

        // Check for an existing share first
        if let shareSet = try? container.fetchShares(matching: [household.objectID]),
           let (_, existingShare) = shareSet.first,
           existingShare.url != nil {
            AppLogger.sharing.info("Presenting UICloudSharingController with existing share")
            let controller = UICloudSharingController(share: existingShare, container: ckContainer)
            controller.delegate = context.coordinator
            return controller
        }

        // Create a new share via the preparation handler.
        // UICloudSharingController shows its own spinner while CloudKit
        // creates the zone and exports the share record.
        AppLogger.sharing.info("Presenting UICloudSharingController with preparation handler")
        let controller = UICloudSharingController { controller, preparationCompletion in
            Task {
                do {
                    let obj = await container.viewContext.perform {
                        container.viewContext.object(with: self.household.objectID)
                    }
                    let (_, share, ckContainer) = try await container.share([obj], to: nil)
                    share[CKShare.SystemFieldKey.title] = "TableTogether Household" as CKRecordValue
                    share.publicPermission = .none
                    AppLogger.sharing.info("Share prepared — handing to UICloudSharingController")
                    // UICloudSharingController requires the completion to be called on the main thread
                    DispatchQueue.main.async {
                        preparationCompletion(share, ckContainer, nil)
                    }
                } catch {
                    AppLogger.sharing.error("Share preparation failed: \(error.localizedDescription)")
                    DispatchQueue.main.async {
                        preparationCompletion(nil, nil, error)
                    }
                }
            }
        }
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(persistenceController: persistenceController)
    }

    class Coordinator: NSObject, UICloudSharingControllerDelegate {
        let persistenceController: PersistenceController

        init(persistenceController: PersistenceController) {
            self.persistenceController = persistenceController
        }

        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: any Error) {
            AppLogger.sharing.error("UICloudSharingController failed to save share: \(error.localizedDescription)")
        }

        func itemTitle(for csc: UICloudSharingController) -> String? {
            "TableTogether Household"
        }

        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
            AppLogger.sharing.info("UICloudSharingController saved share successfully")
            Task { @MainActor in
                await persistenceController.fetchExistingShare()
            }
        }

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
            AppLogger.sharing.info("UICloudSharingController stopped sharing")
            Task { @MainActor in
                if let share = persistenceController.existingShare {
                    await persistenceController.purgeObjectsAndRecords(for: share)
                }
                await persistenceController.fetchExistingShare()
            }
        }
    }
}
#endif
