import SwiftData
import Foundation

// MARK: - ModelContext Logging Extensions

extension ModelContext {
    /// Saves the context with error logging.
    ///
    /// Use this instead of `try? save()` to ensure failures are logged.
    ///
    /// - Parameter context: A description of what was being saved (for logging)
    /// - Returns: `true` if save succeeded, `false` if it failed
    @discardableResult
    func saveWithLogging(context: String = "data") -> Bool {
        do {
            try save()
            AppLogger.swiftData.debug("Save succeeded: \(context)")
            return true
        } catch {
            AppLogger.swiftData.error("Save failed (\(context)): \(error.localizedDescription)")
            return false
        }
    }

    /// Fetches data with error logging.
    ///
    /// - Parameters:
    ///   - descriptor: The fetch descriptor
    ///   - context: A description of what's being fetched (for logging)
    /// - Returns: The fetched results, or empty array if fetch failed
    func fetchWithLogging<T: PersistentModel>(
        _ descriptor: FetchDescriptor<T>,
        context: String = "data"
    ) -> [T] {
        do {
            let results = try fetch(descriptor)
            AppLogger.swiftData.debug("Fetch succeeded: \(context) (\(results.count) items)")
            return results
        } catch {
            AppLogger.swiftData.error("Fetch failed (\(context)): \(error.localizedDescription)")
            return []
        }
    }

    /// Deletes an object and saves with logging.
    ///
    /// - Parameters:
    ///   - object: The object to delete
    ///   - context: A description of what's being deleted (for logging)
    /// - Returns: `true` if delete and save succeeded, `false` otherwise
    @discardableResult
    func deleteWithLogging<T: PersistentModel>(_ object: T, context: String = "item") -> Bool {
        delete(object)
        return saveWithLogging(context: "delete \(context)")
    }
}
