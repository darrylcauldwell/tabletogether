import Foundation
import CloudKit
import Observation
import SwiftUI

/// Manages CloudKit sharing lifecycle for household data.
///
/// Uses zone-level CKShare on the Core Data CloudKit zone to share
/// all household data (recipes, meal plans, groceries) with participants.
/// All participants have equal readWrite access — no owner hierarchy.
@Observable
final class CloudSharingManager {

    // MARK: - Properties

    /// The CloudKit container for this app
    /// Using @ObservationIgnored allows lazy initialization to work with @Observable
    @ObservationIgnored
    private(set) lazy var ckContainer: CKContainer = CKContainer(identifier: "iCloud.dev.dreamfold.tabletogether")

    /// The Core Data CloudKit zone where SwiftData stores records
    private let zoneID = CKRecordZone.ID(
        zoneName: "com.apple.coredata.cloudkit.zone",
        ownerName: CKCurrentUserDefaultName
    )

    /// The existing CKShare for the household, if any
    private(set) var existingShare: CKShare?

    /// Whether the household is currently shared with others
    var isSharing: Bool {
        existingShare != nil
    }

    /// Number of participants (excluding owner)
    var participantCount: Int {
        guard let share = existingShare else { return 0 }
        return share.participants.count - 1 // Exclude owner
    }

    /// Participant names for display
    var participantNames: [String] {
        guard let share = existingShare else { return [] }
        return share.participants
            .filter { $0.role != .owner }
            .compactMap { participant in
                participant.userIdentity.nameComponents.flatMap {
                    PersonNameComponentsFormatter.localizedString(from: $0, style: .default)
                } ?? "Unknown"
            }
    }

    /// Whether an error occurred during the last operation
    private(set) var lastError: String?

    // MARK: - Fetch Existing Share

    /// Checks if a CKShare already exists for the Core Data zone.
    /// Call this on app launch and before presenting the sharing UI.
    func fetchExistingShare() async {
        do {
            let privateDB = ckContainer.privateCloudDatabase

            // Zone-wide shares use the special system record name
            let shareRecordID = CKRecord.ID(
                recordName: CKRecordNameZoneWideShare,
                zoneID: zoneID
            )

            let record = try await privateDB.record(for: shareRecordID)
            if let share = record as? CKShare {
                await MainActor.run {
                    self.existingShare = share
                    self.lastError = nil
                }
                AppLogger.sharing.info("Found existing household share with \(share.participants.count) participants")
            }
        } catch let error as CKError where error.code == .unknownItem {
            // No share exists yet — this is normal for first-time users
            await MainActor.run {
                self.existingShare = nil
                self.lastError = nil
            }
            AppLogger.sharing.info("No existing household share found")
        } catch let error as CKError where error.code == .zoneNotFound {
            // Zone doesn't exist yet — SwiftData hasn't synced yet
            await MainActor.run {
                self.existingShare = nil
                self.lastError = nil
            }
            AppLogger.sharing.info("CloudKit zone not yet created (first sync pending)")
        } catch {
            await MainActor.run {
                self.lastError = error.localizedDescription
            }
            AppLogger.sharing.error("Failed to fetch existing share: \(error.localizedDescription)")
        }
    }

    // MARK: - Create Share

    /// Creates a new zone-level CKShare for the Core Data zone.
    /// Returns the share for use with UICloudSharingController.
    func createShare() async throws -> CKShare {
        let privateDB = ckContainer.privateCloudDatabase

        // First, ensure the zone exists
        let zone = CKRecordZone(zoneID: zoneID)
        do {
            _ = try await privateDB.save(zone)
        } catch let error as CKError where error.code == .serverRejectedRequest {
            // Zone already exists — that's fine
            AppLogger.sharing.info("CloudKit zone already exists")
        }

        // Create a zone-level share
        let share = CKShare(recordZoneID: zoneID)
        share[CKShare.SystemFieldKey.title] = "TableTogether Household" as CKRecordValue
        share.publicPermission = .none // Only invited participants

        let modifyOp = CKModifyRecordsOperation(recordsToSave: [share])
        modifyOp.savePolicy = .changedKeys

        return try await withCheckedThrowingContinuation { continuation in
            modifyOp.perRecordSaveBlock = { recordID, result in
                switch result {
                case .success:
                    AppLogger.sharing.info("Share record saved: \(recordID.recordName)")
                case .failure(let error):
                    AppLogger.sharing.error("Failed to save share record: \(error.localizedDescription)")
                }
            }
            modifyOp.modifyRecordsResultBlock = { result in
                switch result {
                case .success:
                    Task { @MainActor in
                        self.existingShare = share
                        self.lastError = nil
                    }
                    continuation.resume(returning: share)
                case .failure(let error):
                    Task { @MainActor in
                        self.lastError = error.localizedDescription
                    }
                    continuation.resume(throwing: error)
                }
            }
            privateDB.add(modifyOp)
        }
    }

    // MARK: - Accept Share

    /// Accepts an incoming share invitation.
    /// Called from the app delegate when processing a CloudKit share URL.
    func acceptShare(metadata: CKShare.Metadata) async throws {
        try await ckContainer.accept(metadata)
        AppLogger.sharing.info("Accepted household share invitation")

        // Refresh the existing share reference
        await fetchExistingShare()
    }
}

// MARK: - SwiftUI Environment Key

private struct CloudSharingManagerKey: EnvironmentKey {
    static let defaultValue: CloudSharingManager? = nil
}

extension EnvironmentValues {
    var cloudSharingManager: CloudSharingManager? {
        get { self[CloudSharingManagerKey.self] }
        set { self[CloudSharingManagerKey.self] = newValue }
    }
}
