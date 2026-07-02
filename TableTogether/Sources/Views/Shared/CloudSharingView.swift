#if os(iOS)
import SwiftUI
import CloudKit
import CoreData
import os

/// Presents the system cloud-sharing UI for the household.
///
/// The household CKShare is created (or reused) *before* the sharing controller is
/// shown, so we can hand a ready share to `UICloudSharingController(share:container:)`
/// rather than the deprecated `preparationHandler` initializer. Share creation is
/// async, so this view shows a spinner while `container.share(...)` exports the zone.
///
/// This avoids the timing issue where ShareLink + CKShareTransferRepresentation
/// hangs because iMessage can't compose without a URL, and the URL isn't ready
/// until CloudKit finishes exporting the share zone. #70
struct CloudSharingView: View {
    let household: Household
    let persistenceController: PersistenceController

    @Environment(\.dismiss) private var dismiss
    @State private var preparedShare: PreparedShare?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let preparedShare {
                CloudSharingControllerView(
                    share: preparedShare.share,
                    container: preparedShare.container,
                    persistenceController: persistenceController
                )
                .ignoresSafeArea()
            } else if let errorMessage {
                shareErrorView(errorMessage)
            } else {
                ProgressView("Preparing invitation…")
                    .controlSize(.large)
            }
        }
        .task { await prepareShare() }
    }

    @ViewBuilder
    private func shareErrorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.icloud")
                .font(.largeTitle)
                .foregroundStyle(Theme.Colors.textSecondary)
            Text("Couldn't prepare the invitation")
                .font(AppTypography.cardTitle)
            Text(message)
                .font(AppTypography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    /// Reuses an existing household share when one already has a URL, otherwise creates
    /// and persists a new share. Runs once — `.task` re-fires on reappear, but the
    /// `preparedShare` guard makes that a no-op.
    private func prepareShare() async {
        guard preparedShare == nil, errorMessage == nil else { return }
        let container = persistenceController.container
        let ckContainer = CKContainer(identifier: PersistenceController.cloudKitContainerID)

        if let shareSet = try? container.fetchShares(matching: [household.objectID]),
           let (_, existingShare) = shareSet.first,
           existingShare.url != nil {
            AppLogger.sharing.info("Reusing existing household share")
            preparedShare = PreparedShare(share: existingShare, container: ckContainer)
            return
        }

        AppLogger.sharing.info("Creating new household share")
        do {
            let prepared = try await Self.createShare(container: container, householdID: household.objectID)
            AppLogger.sharing.info("Household share created")
            preparedShare = prepared
        } catch {
            AppLogger.sharing.error("Share preparation failed: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }

    /// Creates and exports the household share off the main actor. `share(_:to:)`
    /// blocks its calling thread while Core Data exports the zone (an internal
    /// `_PFRequestExecutor wait`), so invoking it from the main actor beachballs the
    /// app — and can deadlock if the export needs a main-queue history merge.
    nonisolated private static func createShare(
        container: NSPersistentCloudKitContainer,
        householdID: NSManagedObjectID
    ) async throws -> PreparedShare {
        let context = container.newBackgroundContext()
        let obj = await context.perform { context.object(with: householdID) }
        let (_, share, sharedContainer) = try await container.share([obj], to: nil)
        share[CKShare.SystemFieldKey.title] = "TableTogether Household" as CKRecordValue
        share.publicPermission = .none
        return PreparedShare(share: share, container: sharedContainer)
    }
}

/// A share that has already been created/exported on CloudKit, ready to present.
private struct PreparedShare {
    let share: CKShare
    let container: CKContainer
}

/// UIViewControllerRepresentable wrapper that presents a ready CKShare.
private struct CloudSharingControllerView: UIViewControllerRepresentable {
    let share: CKShare
    let container: CKContainer
    let persistenceController: PersistenceController

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: container)
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
                // Owner vs participant matters here: the owner must NOT purge (it would delete
                // the whole household, #70), only a leaving participant removes its local mirror.
                // handleStoppedSharing makes that distinction and refreshes share state.
                if let share = persistenceController.existingShare {
                    await persistenceController.handleStoppedSharing(share)
                } else {
                    await persistenceController.fetchExistingShare()
                }
            }
        }
    }
}
#endif
