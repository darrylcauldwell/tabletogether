#if os(iOS)
import UIKit
import CloudKit
import CoreData

/// Presents CloudKit sharing UI via UICloudSharingController.
///
/// UICloudSharingController manages the full share lifecycle — including
/// uploading the CKShare to CloudKit — before letting the user send an
/// invitation.  The previous NSItemProvider + UIActivityViewController
/// approach failed because NSPersistentCloudKitContainer.share() saves
/// the share locally; CloudKit mirroring is async, so the share wasn't
/// uploaded by the time iMessage tried to resolve it (infinite spinner).
///
/// State management: CKSystemSharingUIObserver (configured in
/// PersistenceController.init) handles updating existingShare after
/// save/stop events. The delegate here calls fetchExistingShare() for
/// immediacy and onError for UI alerts — no direct property writes.
@MainActor
final class SharingPresenter: NSObject {

    static let shared = SharingPresenter()

    /// Callback for errors — wired by SettingsView to show alerts.
    var onError: ((String) -> Void)?

    // MARK: - Invite to Household (New Share)

    /// Presents UICloudSharingController with a preparation handler that
    /// creates the CKShare via NSPersistentCloudKitContainer.share().
    /// The controller waits for the share to be fully uploaded to CloudKit
    /// before presenting sharing options to the user.
    func presentInvite(for household: Household, recipientLabel: String? = nil) {
        let pc = PersistenceController.shared

        // Save pending changes before sharing
        if pc.viewContext.hasChanges {
            do {
                try pc.viewContext.save()
            } catch {
                onError?("Failed to save: \(error.localizedDescription)")
                return
            }
        }

        let controller = UICloudSharingController { _, preparationHandler in
            pc.container.share([household], to: nil) { _, share, ckContainer, error in
                if let share {
                    share[CKShare.SystemFieldKey.title] = "TableTogether Household" as CKRecordValue
                    share.publicPermission = .none

                    // Store recipient label so the pending row shows a name.
                    // UserDefaults is thread-safe; safe to call from this queue.
                    if let recipientLabel, !recipientLabel.isEmpty {
                        PendingInvitationStore.setLabel(
                            recipientLabel,
                            forShareRecordName: share.recordID.recordName
                        )
                    }
                }
                preparationHandler(share, ckContainer, error)
            }
        }

        controller.availablePermissions = [.allowReadWrite, .allowPrivate]
        controller.delegate = self
        presentController(controller)
    }

    // MARK: - Invite More People (Existing Share)

    /// Presents UICloudSharingController for an existing share so the user
    /// can invite additional people.
    func presentInviteMore(share: CKShare, recipientLabel: String? = nil) {
        let pc = PersistenceController.shared

        if let recipientLabel, !recipientLabel.isEmpty {
            PendingInvitationStore.setLabel(
                recipientLabel,
                forShareRecordName: share.recordID.recordName
            )
        }

        let controller = UICloudSharingController(share: share, container: pc.ckContainer)
        controller.availablePermissions = [.allowReadWrite, .allowPrivate]
        controller.delegate = self
        presentController(controller)
    }

    // MARK: - Private Helpers

    private func presentController(_ controller: UICloudSharingController) {
        controller.modalPresentationStyle = .formSheet

        guard let topVC = Self.topViewController() else {
            onError?("Unable to present sharing UI")
            return
        }

        // iPad requires popover source
        if let popover = controller.popoverPresentationController {
            popover.sourceView = topVC.view
            popover.sourceRect = CGRect(x: topVC.view.bounds.midX, y: topVC.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }

        topVC.present(controller, animated: true)
    }

    private static func topViewController() -> UIViewController? {
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let rootVC = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController
        else { return nil }

        var topVC = rootVC
        while let presented = topVC.presentedViewController {
            topVC = presented
        }
        return topVC
    }
}

// MARK: - UICloudSharingControllerDelegate

extension SharingPresenter: UICloudSharingControllerDelegate {

    nonisolated func cloudSharingController(
        _ controller: UICloudSharingController,
        failedToSaveShareWithError error: any Error
    ) {
        Task { @MainActor in
            onError?("Failed to share: \(error.localizedDescription)")
        }
    }

    nonisolated func cloudSharingControllerDidSaveShare(_ controller: UICloudSharingController) {
        Task { @MainActor in
            await PersistenceController.shared.fetchExistingShare()
        }
    }

    nonisolated func cloudSharingControllerDidStopSharing(_ controller: UICloudSharingController) {
        Task { @MainActor in
            await PersistenceController.shared.fetchExistingShare()
        }
    }

    nonisolated func itemTitle(for controller: UICloudSharingController) -> String? {
        "TableTogether Household"
    }
}
#endif
