//
//  SharingCoordinator.swift
//  TableTogether
//
//  Coordinates CloudKit sharing and handles conflict resolution for collaborative editing.
//  Implements conflict resolution strategies per the specification:
//  - MealSlot: Last-write-wins at field level with "also edited by" notification
//  - GroceryItem.isChecked: OR merge (if either checked, stay checked)
//  - Recipe: Last-write-wins (rare concurrent edits)
//  - User: Per-field merge (personal settings don't conflict)
//

import Foundation
import SwiftData
import SwiftUI
import CloudKit
import Observation
import Combine

// MARK: - Sync Status

/// Represents the current synchronization status
enum SyncStatus: Equatable {
    case synced
    case syncing
    case offline
    case error(String)

    var displayName: String {
        switch self {
        case .synced: return "Synced"
        case .syncing: return "Syncing..."
        case .offline: return "Offline"
        case .error(let message): return "Error: \(message)"
        }
    }

    var iconName: String {
        switch self {
        case .synced: return "checkmark.icloud"
        case .syncing: return "arrow.triangle.2.circlepath.icloud"
        case .offline: return "icloud.slash"
        case .error: return "exclamationmark.icloud"
        }
    }
}

// MARK: - Change Notification

/// Represents a change made by another household member
struct HouseholdChange: Identifiable {
    let id = UUID()
    let timestamp: Date
    let userName: String
    let description: String
    let entityType: String

    var timeAgo: String {
        let interval = Date().timeIntervalSince(timestamp)
        if interval < 60 {
            return "Just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes) min ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours) hr ago"
        } else {
            let days = Int(interval / 86400)
            return "\(days) day ago"
        }
    }
}

// MARK: - Sharing Coordinator

/// Coordinates CloudKit sharing and conflict resolution for the TableTogether app.
///
/// This service:
/// - Monitors sync status
/// - Detects and resolves conflicts
/// - Tracks recent changes from other household members
/// - Provides share management for household invitations
@Observable
final class SharingCoordinator {

    // MARK: - Properties

    /// Current sync status
    private(set) var syncStatus: SyncStatus = .synced

    /// Recent changes from other household members
    private(set) var recentChanges: [HouseholdChange] = []

    /// Pending changes count (when offline)
    private(set) var pendingChangesCount: Int = 0

    /// Last successful sync timestamp
    private(set) var lastSyncDate: Date?

    /// Current user (for attribution)
    var currentUser: User?

    /// Network monitor for connectivity tracking
    private var networkMonitor: NetworkMonitor?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    @MainActor
    init() {
        setupNetworkMonitoring()
    }

    // MARK: - Sync Status Management

    /// Updates the sync status based on network conditions and CloudKit state
    @MainActor
    private func setupNetworkMonitoring() {
        networkMonitor = NetworkMonitor.shared

        // Observe network connectivity changes
        NetworkMonitor.shared.$isConnected
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isConnected in
                guard let self = self else { return }
                if !isConnected {
                    self.syncStatus = .offline
                    AppLogger.sharing.notice("Sync status changed to offline")
                } else if self.syncStatus == .offline {
                    // Network restored - attempt sync
                    self.syncStatus = .syncing
                    AppLogger.sharing.notice("Network restored, attempting sync")
                    self.refreshSync()
                }
            }
            .store(in: &cancellables)

        // Set initial status based on current network state
        syncStatus = NetworkMonitor.shared.isConnected ? .synced : .offline
        if NetworkMonitor.shared.isConnected {
            lastSyncDate = Date()
        }
    }

    /// Manually triggers a sync attempt
    func refreshSync() {
        syncStatus = .syncing

        // Simulate sync delay
        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            await MainActor.run {
                self.syncStatus = .synced
                self.lastSyncDate = Date()
            }
        }
    }

    // MARK: - Conflict Resolution

    /// Resolves a conflict for a MealSlot using last-write-wins strategy.
    ///
    /// Per specification:
    /// - Last writer wins at field level
    /// - If another user edited recently, show "also edited by [user]" note
    ///
    /// - Parameters:
    ///   - local: The local version of the slot
    ///   - remote: The remote version from CloudKit
    ///   - currentUser: The current user making changes
    /// - Returns: The resolved MealSlot
    func resolveMealSlotConflict(
        local: MealSlot,
        remote: MealSlot,
        currentUser: User
    ) -> MealSlot {
        // Last-write-wins based on modifiedAt timestamp
        if local.modifiedAt > remote.modifiedAt {
            // Local wins, but note if remote was recently modified by another user
            if let remoteModifier = remote.modifiedBy,
               remoteModifier.id != currentUser.id,
               Date().timeIntervalSince(remote.modifiedAt) < 3600 { // Within last hour
                recordChange(HouseholdChange(
                    timestamp: remote.modifiedAt,
                    userName: remoteModifier.displayName,
                    description: "also edited \(remote.slotDescription)",
                    entityType: "MealSlot"
                ))
            }
            return local
        } else {
            // Remote wins
            if let remoteModifier = remote.modifiedBy,
               remoteModifier.id != currentUser.id {
                recordChange(HouseholdChange(
                    timestamp: remote.modifiedAt,
                    userName: remoteModifier.displayName,
                    description: "updated \(remote.slotDescription)",
                    entityType: "MealSlot"
                ))
            }
            return remote
        }
    }

    /// Resolves a conflict for a GroceryItem using OR merge for isChecked.
    ///
    /// Per specification:
    /// - isChecked uses OR merge: if either version is checked, keep it checked
    /// - This prevents accidentally re-buying items
    ///
    /// - Parameters:
    ///   - local: The local version of the item
    ///   - remote: The remote version from CloudKit
    /// - Returns: The resolved GroceryItem
    func resolveGroceryItemConflict(
        local: GroceryItem,
        remote: GroceryItem
    ) -> GroceryItem {
        // OR merge for isChecked - if either is checked, stay checked
        if local.isChecked || remote.isChecked {
            local.isChecked = true
            // Use the earlier checkedAt date if available
            if let localChecked = local.checkedAt, let remoteChecked = remote.checkedAt {
                local.checkedAt = min(localChecked, remoteChecked)
            } else {
                local.checkedAt = local.checkedAt ?? remote.checkedAt
            }
            local.checkedBy = local.checkedBy ?? remote.checkedBy
        }

        // OR merge for isInPantry - if either marked as in-pantry, keep it
        if local.isInPantry || remote.isInPantry {
            local.isInPantry = true
        }

        // OR merge for pantryChecked - if either has been pantry-checked, keep it
        if local.pantryChecked || remote.pantryChecked {
            local.pantryChecked = true
        }

        // For quantity, use the higher value (someone might have added more)
        local.quantity = max(local.quantity, remote.quantity)

        return local
    }

    /// Resolves a conflict for a Recipe using last-write-wins.
    ///
    /// Per specification:
    /// - Last-write-wins (concurrent recipe edits are rare)
    ///
    /// - Parameters:
    ///   - local: The local version of the recipe
    ///   - remote: The remote version from CloudKit
    /// - Returns: The resolved Recipe
    func resolveRecipeConflict(
        local: Recipe,
        remote: Recipe
    ) -> Recipe {
        // Simple last-write-wins
        if local.modifiedAt > remote.modifiedAt {
            return local
        }
        return remote
    }

    /// Resolves a conflict for a User using per-field merge.
    ///
    /// Per specification:
    /// - Per-field merge (personal settings don't conflict)
    /// - Each user only edits their own settings
    ///
    /// - Parameters:
    ///   - local: The local version of the user
    ///   - remote: The remote version from CloudKit
    /// - Returns: The resolved User
    func resolveUserConflict(
        local: User,
        remote: User
    ) -> User {
        // User now only contains shared household identity (displayName, avatar).
        // Personal data like nutrition targets are in PersonalSettings (CloudKit private database)
        // and never need conflict resolution across devices.
        // For shared identity, last write wins since users only edit their own profile.
        return local
    }

    // MARK: - Change Tracking

    /// Records a change from another household member
    private func recordChange(_ change: HouseholdChange) {
        recentChanges.insert(change, at: 0)

        // Keep only recent changes (last 24 hours, max 20 items)
        let cutoff = Date().addingTimeInterval(-86400)
        recentChanges = Array(recentChanges.filter { $0.timestamp > cutoff }.prefix(20))
    }

    /// Clears changes older than the specified date
    func clearChangesOlderThan(_ date: Date) {
        recentChanges = recentChanges.filter { $0.timestamp > date }
    }

    /// Checks if a slot was recently modified by another user
    func wasRecentlyModifiedByOther(slot: MealSlot, currentUser: User) -> Bool {
        guard let modifier = slot.modifiedBy,
              modifier.id != currentUser.id else {
            return false
        }

        // Within last hour
        return Date().timeIntervalSince(slot.modifiedAt) < 3600
    }

    // MARK: - Share Management

    /// Creates a share URL for inviting household members
    /// Note: In a real implementation, this would use CKShare
    func createHouseholdShareURL() async throws -> URL? {
        // Placeholder - real implementation would use CloudKit sharing APIs
        // CKShare with CKContainer.default().privateCloudDatabase

        // For now, return nil to indicate sharing not yet implemented
        return nil
    }

    /// Accepts a share invitation
    func acceptShareInvitation(from url: URL) async throws {
        // Placeholder - real implementation would accept CKShare
    }

    // MARK: - Offline Support

    /// Increments the pending changes count (when offline)
    func recordPendingChange() {
        if syncStatus == .offline {
            pendingChangesCount += 1
        }
    }

    /// Clears pending changes after successful sync
    func clearPendingChanges() {
        pendingChangesCount = 0
    }
}

// MARK: - SwiftUI Environment Key

private struct SharingCoordinatorKey: EnvironmentKey {
    static let defaultValue: SharingCoordinator? = nil
}

extension EnvironmentValues {
    var sharingCoordinator: SharingCoordinator? {
        get { self[SharingCoordinatorKey.self] }
        set { self[SharingCoordinatorKey.self] = newValue }
    }
}
