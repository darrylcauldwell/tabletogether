import Foundation
import CloudKit
import Combine
import SwiftUI

/// Manages personal data in CloudKit's private database.
/// This data is strictly private to the current Apple ID and never shared.
///
/// Handles:
/// - PersonalSettings (macro goals, display preferences)
/// - PrivateMealLog (meal consumption records)
///
/// Design principles:
/// - Never blocks on network availability
/// - Local cache for offline access
/// - Eventual consistency with CloudKit
/// - No conflicts shown to user (last write wins)
@MainActor
final class PrivateDataManager: ObservableObject {

    // MARK: - Published State

    @Published private(set) var settings: PersonalSettings = PersonalSettings()
    @Published private(set) var mealLogs: [PrivateMealLog] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var lastSyncDate: Date?
    @Published private(set) var syncError: SyncError?

    /// Represents a sync error that can be displayed to the user
    struct SyncError: Identifiable, Equatable {
        let id = UUID()
        let message: String
        let isRetryable: Bool
        let timestamp: Date

        init(message: String, isRetryable: Bool = true) {
            self.message = message
            self.isRetryable = isRetryable
            self.timestamp = Date()
        }

        static func == (lhs: SyncError, rhs: SyncError) -> Bool {
            lhs.id == rhs.id
        }
    }

    // MARK: - Private Properties

    private var container: CKContainer?
    private var privateDatabase: CKDatabase?
    private var settingsRecord: CKRecord?
    private var mealLogRecords: [UUID: CKRecord] = [:]

    /// Whether CloudKit is available (false in simulator without entitlements)
    private(set) var isCloudKitAvailable: Bool = false

    /// Local cache keys
    private let mealLogsCacheKey = "PrivateMealLogsCache"
    private let lastSyncKey = "PrivateDataLastSync"

    // MARK: - Initialization

    init(containerIdentifier: String = "iCloud.dev.dreamfold.tabletogether") {
        // Load from local cache immediately (before attempting CloudKit)
        loadFromLocalCache()

        // Attempt to initialize CloudKit (may fail in simulator)
        initializeCloudKit(containerIdentifier: containerIdentifier)
    }

    /// Attempts to initialize CloudKit, gracefully handling unavailability
    private func initializeCloudKit(containerIdentifier: String) {
        // Check if iCloud is available before trying to create a CKContainer.
        // CKContainer(identifier:) will crash (SIGTRAP) if entitlements are
        // missing or iCloud is not signed in, so we must check first.
        let fileManager = FileManager.default
        guard fileManager.ubiquityIdentityToken != nil else {
            AppLogger.cloudKit.info("CloudKit unavailable (no iCloud account). Using local-only mode.")
            isCloudKitAvailable = false
            return
        }

        let ckContainer = CKContainer(identifier: containerIdentifier)
        self.container = ckContainer
        self.privateDatabase = ckContainer.privateCloudDatabase
        self.isCloudKitAvailable = true
        AppLogger.cloudKit.info("CloudKit initialized successfully")
    }

    // MARK: - Settings Operations

    /// Fetches personal settings from CloudKit, falling back to local cache
    func fetchSettings() async {
        guard isCloudKitAvailable, let privateDatabase = privateDatabase else {
            // CloudKit unavailable, use local cache only
            AppLogger.cloudKit.info("CloudKit unavailable, using local cache for settings")
            return
        }

        isLoading = true
        defer { isLoading = false }

        let recordID = CKRecord.ID(recordName: "personal_settings")

        do {
            let record = try await privateDatabase.record(for: recordID)
            settingsRecord = record

            if let fetchedSettings = PersonalSettings(from: record) {
                settings = fetchedSettings
                settings.saveToLocalCache()
                updateLastSync()
            }
        } catch let error as CKError where error.code == .unknownItem {
            // No settings exist yet - use defaults (already loaded from cache or init)
            AppLogger.cloudKit.info("No personal settings found in CloudKit, using defaults")
            clearSyncError()
        } catch let error as CKError {
            AppLogger.cloudKit.error("Failed to fetch personal settings", error: error)
            setSyncError(from: error)
            // Keep using cached/default settings
        } catch {
            AppLogger.cloudKit.error("Failed to fetch personal settings", error: error)
            syncError = SyncError(message: "Unable to load settings. Using cached data.")
            // Keep using cached/default settings
        }
    }

    /// Saves personal settings to CloudKit
    func saveSettings(_ newSettings: PersonalSettings) async {
        var updatedSettings = newSettings
        updatedSettings.modifiedAt = Date()

        // Update local state immediately for responsiveness
        settings = updatedSettings
        settings.saveToLocalCache()

        // Skip CloudKit if unavailable
        guard isCloudKitAvailable, let privateDatabase = privateDatabase else {
            AppLogger.cloudKit.info("CloudKit unavailable, settings saved to local cache only")
            return
        }

        // Save to CloudKit in background
        let record = updatedSettings.toRecord(existingRecord: settingsRecord)

        do {
            let savedRecord = try await privateDatabase.save(record)
            settingsRecord = savedRecord
            updateLastSync()
            clearSyncError()
        } catch let error as CKError {
            AppLogger.cloudKit.error("Failed to save personal settings", error: error)
            setSyncError(from: error)
            // Local state already updated, CloudKit will sync eventually
        } catch {
            AppLogger.cloudKit.error("Failed to save personal settings", error: error)
            syncError = SyncError(message: "Changes saved locally. Will sync when online.")
            // Local state already updated, CloudKit will sync eventually
        }
    }

    /// Updates macro goals
    func updateGoals(
        calories: Int? = nil,
        protein: Int? = nil,
        carbs: Int? = nil,
        fat: Int? = nil
    ) async {
        var updated = settings
        if calories != nil { updated.dailyCalorieTarget = calories }
        if protein != nil { updated.dailyProteinTarget = protein }
        if carbs != nil { updated.dailyCarbTarget = carbs }
        if fat != nil { updated.dailyFatTarget = fat }
        await saveSettings(updated)
    }

    /// Clears all macro goals
    func clearGoals() async {
        let cleared = settings.withClearedGoals()
        await saveSettings(cleared)
    }

    /// Toggles macro insights visibility
    func setShowMacroInsights(_ show: Bool) async {
        var updated = settings
        updated.showMacroInsights = show
        await saveSettings(updated)
    }

    // MARK: - Meal Log Operations

    /// Fetches meal logs from CloudKit for a date range
    func fetchMealLogs(from startDate: Date, to endDate: Date) async {
        guard isCloudKitAvailable, let privateDatabase = privateDatabase else {
            // CloudKit unavailable, use local cache only
            AppLogger.cloudKit.info("CloudKit unavailable, using local cache for meal logs")
            return
        }

        isLoading = true
        defer { isLoading = false }

        let predicate = NSPredicate(format: "date >= %@ AND date <= %@", startDate as NSDate, endDate as NSDate)
        let query = CKQuery(recordType: PrivateMealLog.recordType, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]

        do {
            let (results, _) = try await privateDatabase.records(matching: query)

            var fetchedLogs: [PrivateMealLog] = []
            var fetchedRecords: [UUID: CKRecord] = [:]

            for (_, result) in results {
                if case .success(let record) = result,
                   let log = PrivateMealLog(from: record) {
                    fetchedLogs.append(log)
                    fetchedRecords[log.id] = record
                }
            }

            mealLogs = fetchedLogs.sorted { $0.date > $1.date }
            mealLogRecords = fetchedRecords
            saveMealLogsToCache()
            updateLastSync()
            clearSyncError()
        } catch let error as CKError {
            AppLogger.cloudKit.error("Failed to fetch meal logs", error: error)
            setSyncError(from: error)
            // Keep using cached logs
        } catch {
            AppLogger.cloudKit.error("Failed to fetch meal logs", error: error)
            syncError = SyncError(message: "Unable to load meal logs. Using cached data.")
            // Keep using cached logs
        }
    }

    /// Fetches meal logs for the current week
    func fetchCurrentWeekLogs() async {
        let calendar = Calendar.current
        let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())) ?? Date()
        let endOfWeek = calendar.date(byAdding: .day, value: 7, to: startOfWeek) ?? Date()

        await fetchMealLogs(from: startOfWeek, to: endOfWeek)
    }

    /// Saves a new meal log
    func saveMealLog(_ log: PrivateMealLog) async {
        // Update local state immediately
        if let index = mealLogs.firstIndex(where: { $0.id == log.id }) {
            mealLogs[index] = log
        } else {
            mealLogs.insert(log, at: 0)
            mealLogs.sort { $0.date > $1.date }
        }
        saveMealLogsToCache()

        // Skip CloudKit if unavailable
        guard isCloudKitAvailable, let privateDatabase = privateDatabase else {
            AppLogger.cloudKit.info("CloudKit unavailable, meal log saved to local cache only")
            return
        }

        // Save to CloudKit
        let record = log.toRecord(existingRecord: mealLogRecords[log.id])

        do {
            let savedRecord = try await privateDatabase.save(record)
            mealLogRecords[log.id] = savedRecord
            updateLastSync()
            clearSyncError()
        } catch let error as CKError {
            AppLogger.cloudKit.error("Failed to save meal log", error: error)
            setSyncError(from: error)
            // Local state already updated
        } catch {
            AppLogger.cloudKit.error("Failed to save meal log", error: error)
            syncError = SyncError(message: "Meal log saved locally. Will sync when online.")
            // Local state already updated
        }
    }

    /// Deletes a meal log
    func deleteMealLog(_ log: PrivateMealLog) async {
        // Update local state immediately
        mealLogs.removeAll { $0.id == log.id }
        mealLogRecords.removeValue(forKey: log.id)
        saveMealLogsToCache()

        // Skip CloudKit if unavailable
        guard isCloudKitAvailable, let privateDatabase = privateDatabase else {
            AppLogger.cloudKit.info("CloudKit unavailable, meal log deletion saved to local cache only")
            return
        }

        // Delete from CloudKit
        let recordID = CKRecord.ID(recordName: log.id.uuidString)

        do {
            try await privateDatabase.deleteRecord(withID: recordID)
            updateLastSync()
            clearSyncError()
        } catch let error as CKError {
            AppLogger.cloudKit.error("Failed to delete meal log", error: error)
            setSyncError(from: error)
        } catch {
            AppLogger.cloudKit.error("Failed to delete meal log", error: error)
            syncError = SyncError(message: "Deletion saved locally. Will sync when online.")
        }
    }

    // MARK: - Meal Plan Auto-Population

    /// Auto-populates meal logs from planned meal slots for the current user.
    /// Called when the meal log view appears or app becomes active.
    /// Creates `.planned` log entries for assigned slots that don't yet have a log.
    func syncPlannedMeals(slots: [MealSlot], currentUser: User) async {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today

        // Filter to slots from today and yesterday where current user is assigned
        let relevantSlots = slots.filter { slot in
            guard slot.isPlanned,
                  slot.assignedTo.contains(where: { $0.id == currentUser.id }) else {
                return false
            }

            // Check if slot's weekPlan contains today or yesterday
            guard let weekPlan = slot.weekPlan else { return false }
            let slotDate = weekPlan.date(for: slot.dayOfWeek)
            let slotDay = calendar.startOfDay(for: slotDate)
            return slotDay == today || slotDay == yesterday
        }

        for slot in relevantSlots {
            // Check if a log already exists for this slot
            let alreadyLogged = mealLogs.contains { $0.mealSlotID == slot.id }
            guard !alreadyLogged else { continue }

            // Calculate per-person servings
            let assignedCount = max(slot.assignedTo.count, 1)
            let perPersonServings = Double(slot.servingsPlanned) / Double(assignedCount)

            let slotDate: Date
            if let weekPlan = slot.weekPlan {
                slotDate = weekPlan.date(for: slot.dayOfWeek)
            } else {
                slotDate = Date()
            }

            let log = PrivateMealLog(
                date: slotDate,
                mealType: slot.mealType,
                recipeID: slot.recipes.first?.id,
                mealSlotID: slot.id,
                servingsConsumed: perPersonServings,
                status: .planned
            )

            await saveMealLog(log)
        }
    }

    /// Updates the status of a meal log entry and syncs to CloudKit
    func updateLogStatus(_ log: PrivateMealLog, status: MealLogStatus) async {
        var updated = log
        updated.status = status
        await saveMealLog(updated)
    }

    /// Returns meal logs for a specific date
    func mealLogs(for date: Date) -> [PrivateMealLog] {
        let calendar = Calendar.current
        return mealLogs.filter { log in
            calendar.isDate(log.date, inSameDayAs: date)
        }
    }

    /// Returns meal logs grouped by day
    func mealLogsByDay() -> [Date: [PrivateMealLog]] {
        let calendar = Calendar.current
        var grouped: [Date: [PrivateMealLog]] = [:]

        for log in mealLogs {
            let day = calendar.startOfDay(for: log.date)
            grouped[day, default: []].append(log)
        }

        return grouped
    }

    // MARK: - Sync Status

    /// Refreshes all private data from CloudKit
    func refresh() async {
        await fetchSettings()
        await fetchCurrentWeekLogs()
    }

    // MARK: - Private Helpers

    private func loadFromLocalCache() {
        // Load settings
        if let cachedSettings = PersonalSettings.loadFromLocalCache() {
            settings = cachedSettings
        }

        // Load meal logs
        if let data = UserDefaults.standard.data(forKey: mealLogsCacheKey),
           let cached = try? JSONDecoder().decode([PrivateMealLog].self, from: data) {
            mealLogs = cached
        }

        // Load last sync date
        if let date = UserDefaults.standard.object(forKey: lastSyncKey) as? Date {
            lastSyncDate = date
        }
    }

    private func saveMealLogsToCache() {
        if let data = try? JSONEncoder().encode(mealLogs) {
            UserDefaults.standard.set(data, forKey: mealLogsCacheKey)
        }
    }

    private func updateLastSync() {
        lastSyncDate = Date()
        UserDefaults.standard.set(lastSyncDate, forKey: lastSyncKey)
    }

    // MARK: - Error Handling

    /// Sets the sync error based on a CloudKit error
    private func setSyncError(from error: CKError) {
        let message: String
        let isRetryable: Bool

        switch error.code {
        case .networkUnavailable, .networkFailure:
            message = "No network connection. Changes saved locally."
            isRetryable = true
        case .serviceUnavailable:
            message = "iCloud is temporarily unavailable. Changes saved locally."
            isRetryable = true
        case .quotaExceeded:
            message = "iCloud storage is full. Please free up space."
            isRetryable = false
        case .notAuthenticated:
            message = "Please sign in to iCloud to sync your data."
            isRetryable = false
        case .permissionFailure:
            message = "Unable to access iCloud. Please check your settings."
            isRetryable = false
        case .serverRejectedRequest:
            message = "Request was rejected. Please try again later."
            isRetryable = true
        default:
            message = "Sync issue occurred. Changes saved locally."
            isRetryable = true
        }

        syncError = SyncError(message: message, isRetryable: isRetryable)
    }

    /// Clears the current sync error
    func clearSyncError() {
        syncError = nil
    }

    /// Dismisses the sync error (user acknowledged)
    func dismissSyncError() {
        syncError = nil
    }
}

// MARK: - Environment Key

private struct PrivateDataManagerKey: EnvironmentKey {
    static let defaultValue: PrivateDataManager? = nil
}

extension EnvironmentValues {
    var privateDataManager: PrivateDataManager? {
        get { self[PrivateDataManagerKey.self] }
        set { self[PrivateDataManagerKey.self] = newValue }
    }
}
