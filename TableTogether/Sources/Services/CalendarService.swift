import Foundation
import EventKit
import SwiftUI

// MARK: - Calendar Settings

/// Settings for calendar integration, stored locally in UserDefaults.
struct CalendarSettings: Codable, Equatable {
    var isEnabled: Bool = false
    var selectedCalendarIdentifier: String?
    var reminderMinutesBefore: Int? // nil = no reminder, 15, 30, 60
    var lastSyncDate: Date?

    /// Default reminder options available to users.
    static let reminderOptions: [Int?] = [nil, 15, 30, 60]

    /// Display string for a reminder option.
    static func reminderDisplayName(_ minutes: Int?) -> String {
        guard let minutes = minutes else { return "None" }
        if minutes == 60 {
            return "1 hour before"
        }
        return "\(minutes) minutes before"
    }
}

// MARK: - Calendar Event Mapping

/// Tracks the relationship between a MealSlot and its synced calendar event.
struct CalendarEventMapping: Codable, Equatable {
    var mealSlotId: UUID
    var eventIdentifier: String
    var lastSyncedAt: Date
    var contentHash: Int
}

// MARK: - Calendar Service

/// Service for syncing meal plans to Apple Calendar via EventKit.
///
/// Features:
/// - Request calendar access
/// - Sync meal slots to calendar events
/// - Deep link back to TableTogether via URL scheme
/// - Optional reminders before events
/// - Conflict detection with existing events
///
/// Note: Calendar sync is a personal feature. Event mappings are stored locally
/// and not shared between household members.
@MainActor
final class CalendarService: ObservableObject {
    static let shared = CalendarService()

    private let eventStore = EKEventStore()
    private let userDefaults = UserDefaults.standard

    private let settingsKey = "CalendarSettings"
    private let mappingsKey = "CalendarEventMappings"

    // MARK: - Published Properties

    @Published private(set) var isAuthorized = false
    @Published private(set) var authorizationStatus: EKAuthorizationStatus = .notDetermined
    @Published private(set) var availableCalendars: [EKCalendar] = []
    @Published private(set) var selectedCalendar: EKCalendar?
    @Published private(set) var settings: CalendarSettings
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var syncedEventCount: Int = 0

    // MARK: - Private State

    private var eventMappings: [UUID: CalendarEventMapping] = [:]

    // MARK: - Initialization

    private init() {
        // Load settings from UserDefaults
        if let data = userDefaults.data(forKey: settingsKey),
           let decoded = try? JSONDecoder().decode(CalendarSettings.self, from: data) {
            self.settings = decoded
        } else {
            self.settings = CalendarSettings()
        }

        // Load event mappings
        if let data = userDefaults.data(forKey: mappingsKey),
           let decoded = try? JSONDecoder().decode([UUID: CalendarEventMapping].self, from: data) {
            self.eventMappings = decoded
        }

        // Check initial authorization status
        checkAuthorizationStatus()

        // Load calendars if authorized
        if isAuthorized {
            loadCalendars()
            updateSyncedEventCount()
        }
    }

    // MARK: - EventKit Availability

    /// Check if EventKit is available on this device.
    static var isAvailable: Bool {
        // EventKit is available on iOS/iPadOS, not on tvOS
        #if os(iOS)
        return true
        #else
        return false
        #endif
    }

    // MARK: - Authorization

    /// Check the current authorization status.
    func checkAuthorizationStatus() {
        if #available(iOS 17.0, *) {
            authorizationStatus = EKEventStore.authorizationStatus(for: .event)
            isAuthorized = authorizationStatus == .fullAccess
        } else {
            authorizationStatus = EKEventStore.authorizationStatus(for: .event)
            isAuthorized = authorizationStatus == .authorized
        }
    }

    /// Request full calendar access.
    func requestAuthorization() async {
        guard CalendarService.isAvailable else {
            errorMessage = "Calendar is not available on this device"
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            var granted = false

            if #available(iOS 17.0, *) {
                granted = try await eventStore.requestFullAccessToEvents()
            } else {
                granted = try await eventStore.requestAccess(to: .event)
            }

            isAuthorized = granted
            checkAuthorizationStatus()

            if granted {
                loadCalendars()

                // If no calendar selected, pick the default
                if settings.selectedCalendarIdentifier == nil {
                    selectDefaultCalendar()
                }
            } else {
                errorMessage = "Calendar access was denied. You can enable it in Settings."
                await updateSettings { $0.isEnabled = false }
            }
        } catch {
            errorMessage = "Failed to request calendar access: \(error.localizedDescription)"
            isAuthorized = false
        }

        isLoading = false
    }

    // MARK: - Calendar Management

    /// Load available calendars that can be written to.
    private func loadCalendars() {
        availableCalendars = eventStore.calendars(for: .event).filter { calendar in
            calendar.allowsContentModifications
        }.sorted { $0.title < $1.title }

        // Update selected calendar reference
        if let identifier = settings.selectedCalendarIdentifier {
            selectedCalendar = availableCalendars.first { $0.calendarIdentifier == identifier }
        }

        // If selected calendar no longer exists, clear it
        if selectedCalendar == nil && settings.selectedCalendarIdentifier != nil {
            Task {
                await updateSettings { $0.selectedCalendarIdentifier = nil }
            }
        }
    }

    /// Select the default calendar for events.
    private func selectDefaultCalendar() {
        if let defaultCalendar = eventStore.defaultCalendarForNewEvents {
            Task {
                await selectCalendar(defaultCalendar)
            }
        } else if let firstCalendar = availableCalendars.first {
            Task {
                await selectCalendar(firstCalendar)
            }
        }
    }

    /// Select a calendar for syncing events.
    func selectCalendar(_ calendar: EKCalendar) async {
        selectedCalendar = calendar
        await updateSettings { $0.selectedCalendarIdentifier = calendar.calendarIdentifier }
    }

    // MARK: - Settings Management

    /// Update settings and persist to UserDefaults.
    func updateSettings(_ update: (inout CalendarSettings) -> Void) async {
        var newSettings = settings
        update(&newSettings)
        settings = newSettings
        saveSettings()
    }

    /// Enable or disable calendar sync.
    func setEnabled(_ enabled: Bool) async {
        if enabled && !isAuthorized {
            await requestAuthorization()
            if !isAuthorized {
                return // Authorization failed, don't enable
            }
        }

        await updateSettings { $0.isEnabled = enabled }

        if !enabled {
            // Optionally clear all synced events when disabled
            // For now, we leave them in place
        }
    }

    /// Set the reminder time.
    func setReminderMinutes(_ minutes: Int?) async {
        await updateSettings { $0.reminderMinutesBefore = minutes }
    }

    private func saveSettings() {
        if let data = try? JSONEncoder().encode(settings) {
            userDefaults.set(data, forKey: settingsKey)
        }
    }

    private func saveMappings() {
        if let data = try? JSONEncoder().encode(eventMappings) {
            userDefaults.set(data, forKey: mappingsKey)
        }
        updateSyncedEventCount()
    }

    private func updateSyncedEventCount() {
        syncedEventCount = eventMappings.count
    }

    // MARK: - Event Sync

    /// Sync a single meal slot to the calendar.
    func syncMealSlot(_ slot: MealSlot, weekPlan: WeekPlan) async throws {
        guard settings.isEnabled, isAuthorized, let calendar = selectedCalendar else {
            return
        }

        guard slot.isPlanned else {
            // If slot is not planned, remove any existing event
            try await removeSyncedEvent(for: slot.id)
            return
        }

        // Calculate the date for this slot
        guard let eventDate = calculateEventDate(for: slot, weekPlan: weekPlan) else {
            throw CalendarSyncError.invalidDate
        }

        // Calculate event duration
        let durationMinutes = calculateDuration(for: slot)
        let endDate = eventDate.addingTimeInterval(TimeInterval(durationMinutes * 60))

        // Create content hash to detect changes
        let contentHash = calculateContentHash(for: slot)

        // Check if we already have this event synced
        if let existing = eventMappings[slot.id] {
            // Check if content changed
            if existing.contentHash == contentHash {
                // No changes, skip update
                return
            }

            // Try to update existing event
            if let event = eventStore.event(withIdentifier: existing.eventIdentifier) {
                configureEvent(event, for: slot, startDate: eventDate, endDate: endDate, calendar: calendar)
                try eventStore.save(event, span: .thisEvent)

                eventMappings[slot.id] = CalendarEventMapping(
                    mealSlotId: slot.id,
                    eventIdentifier: event.eventIdentifier,
                    lastSyncedAt: Date(),
                    contentHash: contentHash
                )
                saveMappings()
                return
            }
        }

        // Create new event
        let event = EKEvent(eventStore: eventStore)
        configureEvent(event, for: slot, startDate: eventDate, endDate: endDate, calendar: calendar)

        try eventStore.save(event, span: .thisEvent)

        eventMappings[slot.id] = CalendarEventMapping(
            mealSlotId: slot.id,
            eventIdentifier: event.eventIdentifier,
            lastSyncedAt: Date(),
            contentHash: contentHash
        )
        saveMappings()

        await updateSettings { $0.lastSyncDate = Date() }
    }

    /// Sync all slots in a week plan.
    func syncWeekPlan(_ weekPlan: WeekPlan) async throws {
        guard settings.isEnabled, isAuthorized else {
            throw CalendarSyncError.notEnabled
        }

        isLoading = true
        errorMessage = nil

        defer { isLoading = false }

        var errors: [Error] = []

        for slot in weekPlan.slots {
            do {
                try await syncMealSlot(slot, weekPlan: weekPlan)
            } catch {
                errors.append(error)
            }
        }

        await updateSettings { $0.lastSyncDate = Date() }

        if !errors.isEmpty {
            throw CalendarSyncError.partialFailure(errors.count)
        }
    }

    /// Remove the synced event for a meal slot.
    func removeSyncedEvent(for slotId: UUID) async throws {
        guard let mapping = eventMappings[slotId],
              let event = eventStore.event(withIdentifier: mapping.eventIdentifier) else {
            eventMappings.removeValue(forKey: slotId)
            saveMappings()
            return
        }

        try eventStore.remove(event, span: .thisEvent)
        eventMappings.removeValue(forKey: slotId)
        saveMappings()
    }

    /// Remove all TableTogether events from the calendar.
    func clearAllSyncedEvents() async throws {
        isLoading = true
        errorMessage = nil

        defer {
            isLoading = false
            saveMappings()
        }

        var errors: [Error] = []

        for (slotId, mapping) in eventMappings {
            if let event = eventStore.event(withIdentifier: mapping.eventIdentifier) {
                do {
                    try eventStore.remove(event, span: .thisEvent)
                } catch {
                    errors.append(error)
                }
            }
            eventMappings.removeValue(forKey: slotId)
        }

        if !errors.isEmpty {
            throw CalendarSyncError.partialFailure(errors.count)
        }
    }

    // MARK: - Conflict Detection

    /// Check for calendar events that overlap with the proposed time.
    func checkForConflicts(at startDate: Date, duration: TimeInterval) async -> [EKEvent] {
        let endDate = startDate.addingTimeInterval(duration)
        let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: nil)
        return eventStore.events(matching: predicate)
    }

    // MARK: - Event Configuration

    private func configureEvent(_ event: EKEvent, for slot: MealSlot, startDate: Date, endDate: Date, calendar: EKCalendar) {
        event.calendar = calendar
        event.startDate = startDate
        event.endDate = endDate
        event.title = slot.displayTitle
        event.notes = buildEventNotes(for: slot)
        event.url = buildDeepLinkURL(for: slot)

        // Clear existing alarms
        event.alarms?.forEach { event.removeAlarm($0) }

        // Add reminder if configured
        if let reminderMinutes = settings.reminderMinutesBefore {
            let alarm = EKAlarm(relativeOffset: TimeInterval(-reminderMinutes * 60))
            event.addAlarm(alarm)
        }
    }

    private func buildEventNotes(for slot: MealSlot) -> String {
        var notes: [String] = []

        for recipe in slot.recipes {
            notes.append("Recipe: \(recipe.title)")

            var timeInfo: [String] = []
            if let prep = recipe.prepTimeMinutes {
                timeInfo.append("Prep: \(prep) min")
            }
            if let cook = recipe.cookTimeMinutes {
                timeInfo.append("Cook: \(cook) min")
            }
            if !timeInfo.isEmpty {
                notes.append(timeInfo.joined(separator: " | "))
            }
            notes.append("")
        }

        if !slot.assignedTo.isEmpty {
            let names = slot.assignedTo.map { $0.displayName }.joined(separator: ", ")
            notes.append("Assigned to: \(names)")
        }

        if let slotNotes = slot.notes, !slotNotes.isEmpty {
            notes.append("")
            notes.append("Notes: \(slotNotes)")
        }

        notes.append("")
        notes.append("Open in TableTogether: tabletogether://meal/\(slot.id.uuidString)")

        return notes.joined(separator: "\n")
    }

    private func buildDeepLinkURL(for slot: MealSlot) -> URL? {
        URL(string: "tabletogether://meal/\(slot.id.uuidString)")
    }

    // MARK: - Date Calculation

    private func calculateEventDate(for slot: MealSlot, weekPlan: WeekPlan) -> Date? {
        let calendar = Calendar.current

        // Get the day offset from Monday
        let dayOffset = slot.dayOfWeek.rawValue - 1 // Monday = 0

        // Calculate the date
        guard let slotDate = calendar.date(byAdding: .day, value: dayOffset, to: weekPlan.weekStartDate) else {
            return nil
        }

        // Set the time based on meal type
        let (hour, minute) = defaultStartTime(for: slot.mealType)

        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: slotDate)
    }

    /// Default start times for each meal type.
    private func defaultStartTime(for mealType: MealType) -> (hour: Int, minute: Int) {
        switch mealType {
        case .breakfast: return (8, 0)
        case .lunch: return (12, 0)
        case .dinner: return (18, 0)
        case .snack: return (15, 0)
        }
    }

    /// Calculate event duration based on meal type and recipe time.
    private func calculateDuration(for slot: MealSlot) -> Int {
        // Sum total time across all recipes
        if !slot.recipes.isEmpty {
            var totalTime = 0
            for recipe in slot.recipes {
                totalTime += (recipe.prepTimeMinutes ?? 0) + (recipe.cookTimeMinutes ?? 0)
            }
            if totalTime > 0 {
                return totalTime
            }
        }

        // Default durations by meal type
        switch slot.mealType {
        case .breakfast: return 30
        case .lunch: return 30
        case .dinner: return 60
        case .snack: return 15
        }
    }

    /// Calculate a hash of the slot content for change detection.
    private func calculateContentHash(for slot: MealSlot) -> Int {
        var hasher = Hasher()
        hasher.combine(slot.displayTitle)
        for recipe in slot.recipes {
            hasher.combine(recipe.id)
        }
        hasher.combine(slot.notes)
        hasher.combine(slot.dayOfWeek)
        hasher.combine(slot.mealType)
        hasher.combine(slot.assignedTo.map { $0.id })
        hasher.combine(settings.reminderMinutesBefore)
        return hasher.finalize()
    }
}

// MARK: - Errors

enum CalendarSyncError: LocalizedError {
    case notEnabled
    case notAuthorized
    case noCalendarSelected
    case invalidDate
    case partialFailure(Int)

    var errorDescription: String? {
        switch self {
        case .notEnabled:
            return "Calendar sync is not enabled"
        case .notAuthorized:
            return "Calendar access is not authorized"
        case .noCalendarSelected:
            return "No calendar selected"
        case .invalidDate:
            return "Could not calculate event date"
        case .partialFailure(let count):
            return "Failed to sync \(count) event\(count == 1 ? "" : "s")"
        }
    }
}

// MARK: - Environment Key

struct CalendarServiceKey: EnvironmentKey {
    static let defaultValue: CalendarService? = nil
}

extension EnvironmentValues {
    var calendarService: CalendarService? {
        get { self[CalendarServiceKey.self] }
        set { self[CalendarServiceKey.self] = newValue }
    }
}

// Note: ArchetypeType.color and IngredientCategory.color are defined in Color+Extensions.swift
