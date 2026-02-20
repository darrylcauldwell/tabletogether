import SwiftUI
import SwiftData
import EventKit

/// Settings view for configuring calendar sync.
///
/// Allows users to:
/// - Enable/disable calendar sync
/// - Select which calendar to use
/// - Configure reminder timing
/// - View sync status
/// - Manually sync or clear events
struct CalendarSettingsView: View {
    @Environment(\.calendarService) private var calendarService
    @Environment(\.modelContext) private var modelContext

    @State private var showingCalendarPicker = false
    @State private var showingClearConfirmation = false
    @State private var isSyncing = false
    @State private var syncError: String?
    @State private var showingSyncSuccess = false

    private var service: CalendarService {
        calendarService ?? CalendarService.shared
    }

    var body: some View {
        List {
            // MARK: - Enable Section
            Section {
                Toggle(isOn: enabledBinding) {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Sync Meals to Calendar")
                            Text("Add meal plans to your calendar")
                                .font(.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                    } icon: {
                        Image(systemName: "calendar.badge.plus")
                            .foregroundStyle(Theme.Colors.primary)
                    }
                }
                .disabled(service.isLoading)
            } footer: {
                if !CalendarService.isAvailable {
                    Text("Calendar sync is not available on this device.")
                        .foregroundStyle(.orange)
                } else if service.authorizationStatus == .denied {
                    Text("Calendar access was denied. Enable it in Settings > Privacy > Calendars.")
                        .foregroundStyle(.orange)
                }
            }

            // MARK: - Calendar Selection
            if service.settings.isEnabled && service.isAuthorized {
                Section {
                    NavigationLink {
                        CalendarPickerView(
                            calendars: service.availableCalendars,
                            selectedCalendar: service.selectedCalendar,
                            onSelect: { calendar in
                                Task {
                                    await service.selectCalendar(calendar)
                                }
                            }
                        )
                    } label: {
                        HStack {
                            Label {
                                Text("Calendar")
                            } icon: {
                                Image(systemName: "calendar")
                                    .foregroundStyle(Theme.Colors.primary)
                            }

                            Spacer()

                            if let calendar = service.selectedCalendar {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(Color(cgColor: calendar.cgColor))
                                        .frame(width: 10, height: 10)
                                    Text(calendar.title)
                                        .foregroundStyle(Theme.Colors.textSecondary)
                                }
                            } else {
                                Text("None")
                                    .foregroundStyle(Theme.Colors.textSecondary)
                            }
                        }
                    }

                    // Reminder picker
                    NavigationLink {
                        ReminderPickerView(
                            selectedMinutes: service.settings.reminderMinutesBefore,
                            onSelect: { minutes in
                                Task {
                                    await service.setReminderMinutes(minutes)
                                }
                            }
                        )
                    } label: {
                        HStack {
                            Label {
                                Text("Reminder")
                            } icon: {
                                Image(systemName: "bell.fill")
                                    .foregroundStyle(Theme.Colors.primary)
                            }

                            Spacer()

                            Text(CalendarSettings.reminderDisplayName(service.settings.reminderMinutesBefore))
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                    }
                }

                // MARK: - Sync Status
                Section {
                    HStack {
                        Label {
                            Text("Events Synced")
                        } icon: {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Theme.Colors.positive)
                        }

                        Spacer()

                        Text("\(service.syncedEventCount)")
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }

                    if let lastSync = service.settings.lastSyncDate {
                        HStack {
                            Label {
                                Text("Last Synced")
                            } icon: {
                                Image(systemName: "clock.fill")
                                    .foregroundStyle(Theme.Colors.textSecondary)
                            }

                            Spacer()

                            Text(lastSync, style: .relative)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                    }
                }

                // MARK: - Actions
                Section {
                    Button {
                        Task {
                            await syncThisWeek()
                        }
                    } label: {
                        HStack {
                            Spacer()
                            if isSyncing {
                                ProgressView()
                                    .padding(.trailing, 8)
                            }
                            Text("Sync This Week")
                                .fontWeight(.medium)
                            Spacer()
                        }
                    }
                    .disabled(isSyncing || service.selectedCalendar == nil)

                    Button(role: .destructive) {
                        showingClearConfirmation = true
                    } label: {
                        HStack {
                            Spacer()
                            Text("Clear All Events")
                            Spacer()
                        }
                    }
                    .disabled(isSyncing || service.syncedEventCount == 0)
                }

                // Error/Success display
                if let error = syncError {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }

                if showingSyncSuccess {
                    Section {
                        Text("Sync completed successfully")
                            .foregroundStyle(Theme.Colors.positive)
                            .font(.caption)
                    }
                }
            }
        }
        .navigationTitle("Calendar Sync")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .confirmationDialog(
            "Clear All Events?",
            isPresented: $showingClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear All Events", role: .destructive) {
                Task {
                    await clearAllEvents()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove all TableTogether meal events from your calendar. Your meal plans in TableTogether are not affected.")
        }
    }

    // MARK: - Bindings

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { service.settings.isEnabled },
            set: { newValue in
                Task {
                    await service.setEnabled(newValue)
                }
            }
        )
    }

    // MARK: - Actions

    private func syncThisWeek() async {
        isSyncing = true
        syncError = nil
        showingSyncSuccess = false

        // Fetch current week plan
        let today = Date()
        let weekStart = WeekPlan.normalizeToMonday(today)

        do {
            let descriptor = FetchDescriptor<WeekPlan>()
            let allPlans = try modelContext.fetch(descriptor)
            let plans = allPlans.filter { Calendar.current.isDate($0.weekStartDate, inSameDayAs: weekStart) }

            if let weekPlan = plans.first {
                try await service.syncWeekPlan(weekPlan)
                showingSyncSuccess = true

                // Hide success message after delay
                Task {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    showingSyncSuccess = false
                }
            } else {
                syncError = "No meal plan found for this week"
            }
        } catch {
            syncError = error.localizedDescription
        }

        isSyncing = false
    }

    private func clearAllEvents() async {
        isSyncing = true
        syncError = nil

        do {
            try await service.clearAllSyncedEvents()
        } catch {
            syncError = error.localizedDescription
        }

        isSyncing = false
    }
}

// MARK: - Calendar Picker View

struct CalendarPickerView: View {
    let calendars: [EKCalendar]
    let selectedCalendar: EKCalendar?
    let onSelect: (EKCalendar) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            ForEach(calendars, id: \.calendarIdentifier) { calendar in
                Button {
                    onSelect(calendar)
                    dismiss()
                } label: {
                    HStack {
                        Circle()
                            .fill(Color(cgColor: calendar.cgColor))
                            .frame(width: 14, height: 14)

                        Text(calendar.title)
                            .foregroundStyle(Theme.Colors.textPrimary)

                        Spacer()

                        if calendar.calendarIdentifier == selectedCalendar?.calendarIdentifier {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Theme.Colors.primary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Select Calendar")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

// MARK: - Reminder Picker View

struct ReminderPickerView: View {
    let selectedMinutes: Int?
    let onSelect: (Int?) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            ForEach(CalendarSettings.reminderOptions, id: \.self) { minutes in
                Button {
                    onSelect(minutes)
                    dismiss()
                } label: {
                    HStack {
                        Text(CalendarSettings.reminderDisplayName(minutes))
                            .foregroundStyle(Theme.Colors.textPrimary)

                        Spacer()

                        if minutes == selectedMinutes {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Theme.Colors.primary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Reminder")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

#Preview {
    NavigationStack {
        CalendarSettingsView()
    }
}
