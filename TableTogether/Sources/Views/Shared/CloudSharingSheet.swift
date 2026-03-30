#if os(iOS)
import SwiftUI
import CloudKit
import CoreData
import UIKit

/// SwiftUI wrapper for UICloudSharingController.
///
/// Matches Apple's CoreDataCloudKitShare sample pattern:
/// - Existing share: UICloudSharingController(share:container:) for managing
/// - New share: UICloudSharingController(preparationHandler:) for creating
///
/// Delegate callbacks persist share updates and purge data when sharing stops.
struct CloudSharingSheet: UIViewControllerRepresentable {
    let share: CKShare?
    let household: Household
    let persistenceController: PersistenceController

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller: UICloudSharingController

        if let existingShare = share {
            // Manage existing share
            controller = UICloudSharingController(
                share: existingShare,
                container: persistenceController.ckContainer
            )
        } else {
            // Create new share via preparation handler (Apple's recommended pattern)
            controller = UICloudSharingController { _, completion in
                let pc = self.persistenceController
                pc.container.share([self.household], to: nil) { _, share, container, error in
                    if let share {
                        share[CKShare.SystemFieldKey.title] = "TableTogether Household" as CKRecordValue
                        share.publicPermission = .none
                    }
                    completion(share, container, error)
                }
            }
        }

        controller.delegate = context.coordinator
        controller.availablePermissions = [.allowReadWrite]
        return controller
    }

    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(persistenceController: persistenceController)
    }

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        let persistenceController: PersistenceController

        init(persistenceController: PersistenceController) {
            self.persistenceController = persistenceController
        }

        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
            // Persist share metadata back to Core Data (Apple's sample does this)
            if let share = csc.share {
                Task {
                    try? await persistenceController.persistUpdatedShare(share)
                    await persistenceController.fetchExistingShare()
                }
            }
            AppLogger.sharing.info("Share saved successfully")
        }

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
            // Purge shared objects and records (Apple's sample does this)
            if let share = csc.share {
                Task {
                    await persistenceController.purgeObjectsAndRecords(for: share)
                }
            }
            AppLogger.sharing.info("Sharing stopped")
        }

        func cloudSharingController(
            _ csc: UICloudSharingController,
            failedToSaveShareWithError error: Error
        ) {
            AppLogger.sharing.error("Failed to save share: \(error.localizedDescription)")
        }

        func itemTitle(for csc: UICloudSharingController) -> String? {
            "TableTogether Household"
        }

        func itemThumbnailData(for csc: UICloudSharingController) -> Data? {
            nil
        }
    }
}
#endif
