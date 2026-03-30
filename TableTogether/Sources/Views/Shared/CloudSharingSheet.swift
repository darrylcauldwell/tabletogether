#if os(iOS)
import UIKit
import CloudKit
import CoreData

/// Presents CloudKit sharing UI via UIKit.
///
/// Three distinct operations, each using the correct Apple API:
/// - Invite (new): NSItemProvider.registerCKShare + UIActivityViewController
/// - Invite (existing): NSItemProvider.registerCKShare + UIActivityViewController
/// - Manage: UICloudSharingController(share:container:)
@MainActor
final class SharingPresenter: NSObject, UICloudSharingControllerDelegate {

    static let shared = SharingPresenter()

    /// Callback for errors — wired by SettingsView to show alerts.
    var onError: ((String) -> Void)?

    // MARK: - Invite to Household (New Share)

    /// Creates a new CKShare and presents UIActivityViewController for the user to send invitations.
    /// Pre-creates the share first, then uses NSItemProvider.registerCKShare(_:container:allowedSharingOptions:)
    /// to present the activity view controller with the existing share.
    func presentInvite(for household: Household) async {
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

        // Pre-create the CKShare on MainActor before presenting
        let share: CKShare
        do {
            share = try await pc.shareHousehold(household)
        } catch {
            onError?("Failed to create share: \(error.localizedDescription)")
            return
        }

        // Now register the existing share and present
        let itemProvider = NSItemProvider()
        itemProvider.registerCKShare(
            share,
            container: pc.ckContainer,
            allowedSharingOptions: CKAllowedSharingOptions.standard
        )

        presentActivityViewController(with: itemProvider)
    }

    // MARK: - Invite More People (Existing Share)

    /// Presents UIActivityViewController for an existing share so the user can invite more people.
    /// Uses NSItemProvider.registerCKShare(_:container:allowedSharingOptions:)
    func presentInviteMore(share: CKShare) {
        let pc = PersistenceController.shared

        let itemProvider = NSItemProvider()
        itemProvider.registerCKShare(
            share,
            container: pc.ckContainer,
            allowedSharingOptions: CKAllowedSharingOptions.standard
        )

        presentActivityViewController(with: itemProvider)
    }

    // MARK: - Manage Sharing

    /// Presents UICloudSharingController for the owner to manage participants, permissions, and stop sharing.
    /// Uses UICloudSharingController(share:container:) which is NOT deprecated.
    func presentManageSharing(share: CKShare) {
        let pc = PersistenceController.shared

        let controller = UICloudSharingController(share: share, container: pc.ckContainer)
        controller.delegate = self
        controller.availablePermissions = [.allowReadWrite]
        controller.modalPresentationStyle = .formSheet

        guard let topVC = Self.topViewController() else {
            onError?("Unable to present sharing UI")
            return
        }
        topVC.present(controller, animated: true)
    }

    // MARK: - UICloudSharingControllerDelegate

    func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
        if let share = csc.share {
            Task {
                try? await PersistenceController.shared.persistUpdatedShare(share)
                await PersistenceController.shared.fetchExistingShare()
            }
        }
        AppLogger.sharing.info("Share saved successfully")
    }

    func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
        if let share = csc.share {
            Task {
                await PersistenceController.shared.purgeObjectsAndRecords(for: share)
                await PersistenceController.shared.fetchExistingShare()
            }
        } else {
            Task {
                await PersistenceController.shared.fetchExistingShare()
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

    // MARK: - Private Helpers

    private func presentActivityViewController(with itemProvider: NSItemProvider) {
        let configuration = UIActivityItemsConfiguration(itemProviders: [itemProvider])

        let activityVC = UIActivityViewController(activityItemsConfiguration: configuration)
        activityVC.modalPresentationStyle = .formSheet

        guard let topVC = Self.topViewController() else {
            onError?("Unable to present sharing UI")
            return
        }

        // iPad requires popover source
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = topVC.view
            popover.sourceRect = CGRect(x: topVC.view.bounds.midX, y: topVC.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }

        topVC.present(activityVC, animated: true)
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
#endif
