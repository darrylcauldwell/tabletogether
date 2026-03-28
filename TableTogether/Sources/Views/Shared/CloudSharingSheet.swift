#if os(iOS)
import SwiftUI
import CloudKit
import UIKit

/// SwiftUI wrapper for UICloudSharingController.
/// Presents Apple's system sharing UI for managing household CloudKit shares.
///
/// Handles:
/// - Sending invitations (iMessage, email, link)
/// - Managing existing participants
/// - All participants get readWrite access (no hierarchy per spec)
struct CloudSharingSheet: UIViewControllerRepresentable {
    let share: CKShare
    let container: CKContainer
    let persistenceController: PersistenceController
    var onDismiss: (() -> Void)?

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: container)
        controller.delegate = context.coordinator
        controller.availablePermissions = [.allowReadWrite]
        return controller
    }

    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(persistenceController: persistenceController, onDismiss: onDismiss)
    }

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        let persistenceController: PersistenceController
        let onDismiss: (() -> Void)?

        init(persistenceController: PersistenceController, onDismiss: (() -> Void)?) {
            self.persistenceController = persistenceController
            self.onDismiss = onDismiss
        }

        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
            AppLogger.sharing.info("Share saved successfully")
            // Refresh share state
            Task {
                await persistenceController.fetchExistingShare()
            }
        }

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
            AppLogger.sharing.info("Sharing stopped")
            Task {
                await persistenceController.fetchExistingShare()
            }
            onDismiss?()
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
