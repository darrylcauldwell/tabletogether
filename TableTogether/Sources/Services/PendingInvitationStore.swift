import Foundation

/// Stores user-provided labels for pending CloudKit share invitations.
///
/// CloudKit doesn't expose participant identity until the invite is accepted.
/// This store lets the owner annotate "who they sent the invite to" so the
/// pending invitation row in Settings shows a meaningful name instead of
/// "Invited Person".
///
/// Storage is local UserDefaults — the label is informational, not authoritative.
/// Once the participant accepts and CloudKit reports their real identity, the
/// local label is no longer needed.
enum PendingInvitationStore {
    private static let storageKey = "PendingInvitationLabels"

    /// All stored labels keyed by share recordName.
    private static var labels: [String: String] {
        get {
            UserDefaults.standard.dictionary(forKey: storageKey) as? [String: String] ?? [:]
        }
        set {
            UserDefaults.standard.set(newValue, forKey: storageKey)
        }
    }

    /// Store a label for a share invitation.
    static func setLabel(_ label: String, forShareRecordName recordName: String) {
        var current = labels
        current[recordName] = label
        labels = current
    }

    /// Retrieve the label for a share invitation.
    static func label(forShareRecordName recordName: String) -> String? {
        labels[recordName]
    }

    /// Remove the label for a share invitation (e.g. when the share is deleted).
    static func removeLabel(forShareRecordName recordName: String) {
        var current = labels
        current.removeValue(forKey: recordName)
        labels = current
    }

    /// Remove all stored labels (e.g. when the share is fully reset).
    static func clearAll() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }
}
