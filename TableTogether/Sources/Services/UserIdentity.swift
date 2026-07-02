import CloudKit
import CoreData
import CryptoKit
import Foundation

/// Resolves the local person's `User` identity.
///
/// Identity is keyed per Apple ID: the UUID is derived deterministically from the
/// CloudKit user record name, so every device signed into the same account computes
/// the same UUID with no coordination (preserving the multi-device convergence that
/// `User.defaultMeID` provided), while different household members get distinct IDs
/// (fixing cross-member misattribution after a household is shared).
///
/// Offline-first: before CloudKit is reachable the "Me" user is seeded with the
/// provisional `User.defaultMeID`; `resolveIfNeeded` upgrades it once the record
/// name becomes available.
enum UserIdentity {

    static let meIDKey = "userIdentity.meID"
    static let recordNameKey = "userIdentity.recordName"

    /// The resolved per-account user ID, or nil while identity is still provisional.
    static var storedID: UUID? {
        UserDefaults.standard.string(forKey: meIDKey).flatMap(UUID.init(uuidString:))
    }

    /// Derives a stable UUID from a CloudKit user record name (SHA-256, first 16
    /// bytes, RFC 4122 version/variant bits). Deterministic so all devices on the
    /// same Apple ID converge on the same ID without coordination.
    static func deterministicID(fromRecordName recordName: String) -> UUID {
        let digest = SHA256.hash(data: Data(recordName.utf8))
        var bytes = [UInt8](digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3],
                           bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11],
                           bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    /// Picks the local person's row among same-ID provisional candidates. A single
    /// candidate is unambiguous; with several, only a lone private-store row
    /// (locally created) can be claimed. Returns nil when ownership cannot be
    /// determined — callers must not guess, because rewriting another member's row
    /// would swap identities.
    static func chooseMyRow(from candidates: [(user: User, isInPrivateStore: Bool)]) -> User? {
        if candidates.count == 1 { return candidates[0].user }
        let privateRows = candidates.filter(\.isInPrivateStore)
        return privateRows.count == 1 ? privateRows[0].user : nil
    }

    /// Fetches (or reuses the cached) CloudKit user record name, stores the derived
    /// per-account ID, and migrates the provisional `defaultMeID` row to it. Safe to
    /// call every launch; does nothing when already resolved, and stays provisional
    /// when CloudKit is unreachable.
    @MainActor
    static func resolveIfNeeded(context: NSManagedObjectContext) async {
        let recordName: String
        if let cached = UserDefaults.standard.string(forKey: recordNameKey) {
            recordName = cached
        } else {
            do {
                let recordID = try await CKContainer(
                    identifier: PersistenceController.cloudKitContainerID
                ).userRecordID()
                recordName = recordID.recordName
                UserDefaults.standard.set(recordName, forKey: recordNameKey)
            } catch {
                AppLogger.sync.info("User identity stays provisional; CloudKit user record unavailable: \(error.localizedDescription)")
                return
            }
        }

        let meID = deterministicID(fromRecordName: recordName)
        UserDefaults.standard.set(meID.uuidString, forKey: meIDKey)

        let meRequest = NSFetchRequest<User>(entityName: "User")
        meRequest.predicate = NSPredicate(format: "id == %@", meID as CVarArg)
        if let me = context.fetchWithLogging(meRequest, context: "resolved Me user").first {
            if me.cloudKitRecordID == nil {
                me.cloudKitRecordID = recordName
                context.saveWithLogging(context: "record CloudKit user record name")
            }
            return
        }

        let provisionalRequest = NSFetchRequest<User>(entityName: "User")
        provisionalRequest.predicate = NSPredicate(format: "id == %@", User.defaultMeID as CVarArg)
        let provisionals = context.fetchWithLogging(provisionalRequest, context: "provisional Me users")
        guard !provisionals.isEmpty else {
            return // Fresh install: ensureUserExists seeds directly with the resolved ID.
        }

        let candidates = provisionals.map { user in
            (user: user,
             isInPrivateStore: user.objectID.persistentStore?.url?.lastPathComponent
                == PersistenceController.privateStoreFileName)
        }
        guard let mine = chooseMyRow(from: candidates) else {
            // Several indistinguishable provisional rows (shared household where no
            // member has migrated yet). Claiming one could swap identities, so leave
            // them; ensureUserExists creates a fresh identified row instead.
            AppLogger.sync.notice("Ambiguous provisional Me rows (\(provisionals.count)); creating a fresh identified user instead of claiming one")
            return
        }
        mine.id = meID
        mine.cloudKitRecordID = recordName
        context.saveWithLogging(context: "migrate Me user to per-account ID")
    }
}
