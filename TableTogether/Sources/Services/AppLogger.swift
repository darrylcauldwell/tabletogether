import Foundation
import os.log

/// Unified logging system for TableTogether app.
///
/// Uses Apple's os.log framework for structured, privacy-aware logging
/// that integrates with Console.app for debugging.
///
/// ## Log Levels
/// - **debug**: Detailed information for debugging (not shown in release builds)
/// - **info**: General informational messages
/// - **notice**: Important events that are expected
/// - **warning**: Potential issues that don't stop execution
/// - **error**: Errors that affect functionality
/// - **fault**: Critical errors indicating bugs
///
/// ## Usage
/// ```swift
/// AppLogger.cloudKit.info("Fetching settings from CloudKit")
/// AppLogger.cloudKit.error("Failed to save: \(error.localizedDescription)")
/// AppLogger.swiftData.debug("Saving \(count) items")
/// ```
enum AppLogger {
    /// Bundle identifier for the app subsystem
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.snap.app"

    // MARK: - Category Loggers

    /// Logger for CloudKit operations (sync, fetch, save)
    static let cloudKit = Logger(subsystem: subsystem, category: "CloudKit")

    /// Logger for SwiftData/persistence operations
    static let swiftData = Logger(subsystem: subsystem, category: "SwiftData")

    /// Logger for app lifecycle events
    static let app = Logger(subsystem: subsystem, category: "App")

    /// Logger for UI-related events
    static let ui = Logger(subsystem: subsystem, category: "UI")

    /// Logger for recipe parsing operations
    static let parser = Logger(subsystem: subsystem, category: "Parser")

    /// Logger for sharing/collaboration features
    static let sharing = Logger(subsystem: subsystem, category: "Sharing")

    /// Logger for grocery list operations
    static let grocery = Logger(subsystem: subsystem, category: "Grocery")

    /// Logger for insights/analytics
    static let insights = Logger(subsystem: subsystem, category: "Insights")

    /// Logger for network monitoring
    static let network = Logger(subsystem: subsystem, category: "Network")

    /// Logger for nutrition lookup and resolution
    static let nutrition = Logger(subsystem: subsystem, category: "Nutrition")
}

// MARK: - Logger Convenience Extensions

extension Logger {
    /// Logs a debug message (only visible in debug builds)
    /// - Parameter message: The message to log
    func debug(_ message: String) {
        self.debug("\(message, privacy: .public)")
    }

    /// Logs an informational message
    /// - Parameter message: The message to log
    func info(_ message: String) {
        self.info("\(message, privacy: .public)")
    }

    /// Logs a notice (important expected events)
    /// - Parameter message: The message to log
    func notice(_ message: String) {
        self.notice("\(message, privacy: .public)")
    }

    /// Logs a warning (potential issues)
    /// - Parameter message: The message to log
    func warning(_ message: String) {
        self.warning("\(message, privacy: .public)")
    }

    /// Logs an error
    /// - Parameter message: The message to log
    func error(_ message: String) {
        self.error("\(message, privacy: .public)")
    }

    /// Logs a fault (critical bug)
    /// - Parameter message: The message to log
    func fault(_ message: String) {
        self.fault("\(message, privacy: .public)")
    }

    /// Logs an error with the associated Error object
    /// - Parameters:
    ///   - message: Context message
    ///   - error: The error that occurred
    func error(_ message: String, error: Error) {
        self.error("\(message, privacy: .public): \(error.localizedDescription, privacy: .public)")
    }

    /// Logs a SwiftData save operation result
    /// - Parameters:
    ///   - context: Description of what was being saved
    ///   - success: Whether the save succeeded
    ///   - error: Optional error if save failed
    func logSave(context: String, success: Bool, error: Error? = nil) {
        if success {
            self.debug("Save succeeded: \(context, privacy: .public)")
        } else if let error = error {
            self.error("Save failed (\(context, privacy: .public)): \(error.localizedDescription, privacy: .public)")
        } else {
            self.error("Save failed (\(context, privacy: .public)): Unknown error")
        }
    }
}

// MARK: - Debug Helpers

#if DEBUG
extension AppLogger {
    /// Prints all log categories for testing
    static func testAllCategories() {
        cloudKit.debug("CloudKit logger test")
        swiftData.debug("SwiftData logger test")
        app.debug("App logger test")
        ui.debug("UI logger test")
        parser.debug("Parser logger test")
        sharing.debug("Sharing logger test")
        grocery.debug("Grocery logger test")
        insights.debug("Insights logger test")
        network.debug("Network logger test")
        nutrition.debug("Nutrition logger test")
    }
}
#endif
