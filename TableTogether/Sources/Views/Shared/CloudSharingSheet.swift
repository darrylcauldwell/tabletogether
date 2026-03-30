#if os(iOS)
import UIKit
import CloudKit
import CoreData

/// Presents UICloudSharingController via UIKit — no SwiftUI .sheet() wrapper.
///
/// Uses only non-deprecated APIs:
/// - Pre-creates CKShare via NSPersistentCloudKitContainer.share() for new shares
/// - Presents UICloudSharingController(share:container:) which is NOT deprecated
/// - Avoids UICloudSharingController(preparationHandler:) which IS deprecated in iOS 17
@MainActor
final class SharingPresenter: NSObject, UICloudSharingControllerDelegate {

    static let shared = SharingPresenter()

    /// Callback for errors — wired by SettingsView to show alerts.
    var onError: ((String) -> Void)?

    /// Presents sharing UI for the given household.
    /// If no share exists, creates one first, then presents the controller.
    func presentSharing(for household: Household, existingShare: CKShare?) async {
        let pc = PersistenceController.shared

        // Ensure data is saved before sharing
        if pc.viewContext.hasChanges {
            do {
                try pc.viewContext.save()
            } catch {
                onError?("Failed to save: \(error.localizedDescription)")
                return
            }
        }

        // Get or create the CKShare
        let share: CKShare
        if let existing = existingShare {
            share = existing
        } else {
            // Pre-create the share (not using deprecated preparationHandler)
            do {
                share = try await pc.shareHousehold(household)
            } catch {
                onError?("Failed to create share: \(error.localizedDescription)")
                return
            }
        }

        // Present UICloudSharingController with the existing share (non-deprecated API)
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

    // MARK: - View Controller Discovery

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
