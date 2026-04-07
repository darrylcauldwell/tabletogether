import Foundation
import CryptoKit

extension UUID {
    /// Generates a deterministic UUID from a string using SHA-256.
    /// The same input always produces the same UUID, allowing multiple devices
    /// to converge on the same record ID without coordination.
    ///
    /// Used for entities that should be unique by their semantic key
    /// (e.g. MealArchetype by systemType, WeekPlan by weekStartDate)
    /// to prevent duplication when multiple devices create the "same"
    /// record before CloudKit sync completes.
    static func deterministic(from string: String) -> UUID {
        let hash = SHA256.hash(data: Data(string.utf8))
        let bytes = Array(hash.prefix(16))
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
