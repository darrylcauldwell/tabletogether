#if os(iOS)
import SwiftUI
import CloudKit
import CoreData
import CoreTransferable
import os

/// Presents the household invitation flow.
///
/// The household CKShare is created (or reused) *before* any UI is shown, so the
/// sheet always has a live invite URL. Share creation is async, so this view shows
/// a spinner while `container.share(...)` exports the zone. #70
///
/// The invite UI is a custom sheet (not `UICloudSharingController`, which renders
/// poorly under Mac Catalyst and duplicates the member management that already
/// lives in Settings): a Liquid Glass "Send Invitation" button opens the system
/// share sheet, plus a copy-link button. The share uses link-based joining
/// (`publicPermission = .readWrite`) — anyone in the household with the link can
/// join, matching the low-ceremony sharing model.
struct CloudSharingView: View {
    let household: Household
    let persistenceController: PersistenceController

    @Environment(\.dismiss) private var dismiss
    @State private var preparedShare: PreparedShare?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let preparedShare {
                HouseholdInviteSheet(share: preparedShare.share) { dismiss() }
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
                .font(AppTypography.largeTitle)
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
            await upgradeToLinkJoiningIfNeeded(existingShare)
            preparedShare = PreparedShare(share: existingShare, container: ckContainer)
            return
        }

        AppLogger.sharing.info("Creating new household share")
        do {
            let prepared = try await Self.createShare(container: container, householdID: household.objectID)
            try await persistenceController.persistUpdatedShare(prepared.share)
            await persistenceController.fetchExistingShare()
            AppLogger.sharing.info("Household share created")
            preparedShare = prepared
        } catch {
            AppLogger.sharing.error("Share preparation failed: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }

    /// Shares created before the link-based invite flow carry `publicPermission = .none`,
    /// which would bounce anyone who taps the link. Upgrade and persist in place.
    private func upgradeToLinkJoiningIfNeeded(_ share: CKShare) async {
        guard share.publicPermission != .readWrite else { return }
        share.publicPermission = .readWrite
        do {
            try await persistenceController.persistUpdatedShare(share)
        } catch {
            AppLogger.sharing.error("Failed to upgrade share to link joining: \(error.localizedDescription)")
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
        share.publicPermission = .readWrite
        return PreparedShare(share: share, container: sharedContainer)
    }
}

/// A share that has already been created/exported on CloudKit, ready to present.
private struct PreparedShare {
    let share: CKShare
    let container: CKContainer
}

/// Lets an existing CKShare be re-sent via ShareLink (used by the household member
/// detail sheet to resend an invitation).
extension CKShare: @retroactive Transferable {
    public nonisolated static var transferRepresentation: some TransferRepresentation {
        CKShareTransferRepresentation { share in
            .existing(share, container: CKContainer(identifier: PersistenceController.cloudKitContainerID))
        }
    }
}

/// Calm, glass-styled invitation sheet: send the invite link via the system share
/// sheet (Messages first) or copy it. Member management stays in Settings.
private struct HouseholdInviteSheet: View {
    let share: CKShare
    var onDone: () -> Void

    @State private var copied = false

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            VStack(spacing: 12) {
                Image(systemName: "person.2.wave.2")
                    .font(AppTypography.largeTitle)
                    .foregroundStyle(Theme.Colors.primary)
                    .accessibilityHidden(true)
                Text("Invite to Your Household")
                    .font(AppTypography.title2Emphasized)
                Text("Anyone with this link can join your household to plan meals, share recipes, and build grocery lists together.")
                    .font(AppTypography.callout)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal)

            if let url = share.url {
                VStack(spacing: 14) {
                    sendButton(url: url)
                    copyButton(url: url)
                }
                .padding(.horizontal, 32)
            }

            Text("You can see who has joined, or stop sharing, in Settings.")
                .font(AppTypography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)

            Spacer()

            Button("Done") { onDone() }
                .font(AppTypography.controlLabel)
                .padding(.bottom)
        }
        .padding()
    }

    @ViewBuilder
    private func sendButton(url: URL) -> some View {
        let link = ShareLink(
            item: url,
            subject: Text("TableTogether Household"),
            message: Text("Join our household on TableTogether")
        ) {
            Label("Send Invitation", systemImage: "message")
                .font(AppTypography.controlLabel)
                .frame(maxWidth: .infinity)
        }
        if #available(iOS 26.0, macCatalyst 26.0, *) {
            link.buttonStyle(.glassProminent).controlSize(.large)
        } else {
            link.buttonStyle(.borderedProminent).controlSize(.large)
        }
    }

    @ViewBuilder
    private func copyButton(url: URL) -> some View {
        let button = Button {
            UIPasteboard.general.url = url
            withAnimation(.easeInOut(duration: 0.2)) { copied = true }
            Task {
                try? await Task.sleep(for: .seconds(2))
                withAnimation(.easeInOut(duration: 0.2)) { copied = false }
            }
        } label: {
            Label(copied ? "Copied" : "Copy Link", systemImage: copied ? "checkmark" : "link")
                .font(AppTypography.controlLabel)
                .frame(maxWidth: .infinity)
        }
        if #available(iOS 26.0, macCatalyst 26.0, *) {
            button.buttonStyle(.glass).controlSize(.large)
        } else {
            button.buttonStyle(.bordered).controlSize(.large)
        }
    }
}
#endif
