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
struct CloudSharingSheet: UIViewControllerRepresentable {
    let share: CKShare?
    let household: Household
    let persistenceController: PersistenceController
    var onError: ((String) -> Void)?

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller: UICloudSharingController

        if let existingShare = share {
            // Manage existing share — shows participants, permissions, stop sharing
            controller = UICloudSharingController(
                share: existingShare,
                container: persistenceController.ckContainer
            )
        } else {
            // Create new share — shows invite UI (iMessage, email, link, AirDrop)
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
        Coordinator(persistenceController: persistenceController, onError: onError)
    }

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        let persistenceController: PersistenceController
        let onError: ((String) -> Void)?

        init(persistenceController: PersistenceController, onError: ((String) -> Void)?) {
            self.persistenceController = persistenceController
            self.onError = onError
        }

        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
            if let share = csc.share {
                Task {
                    try? await persistenceController.persistUpdatedShare(share)
                    await persistenceController.fetchExistingShare()
                }
            }
            AppLogger.sharing.info("Share saved successfully")
        }

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
            if let share = csc.share {
                Task {
                    await persistenceController.purgeObjectsAndRecords(for: share)
                    await persistenceController.fetchExistingShare()
                }
            } else {
                Task {
                    await persistenceController.fetchExistingShare()
                }
            }
            AppLogger.sharing.info("Sharing stopped")
        }

        func cloudSharingController(
            _ csc: UICloudSharingController,
            failedToSaveShareWithError error: Error
        ) {
            AppLogger.sharing.error("Failed to save share: \(error.localizedDescription)")
            onError?(error.localizedDescription)
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
