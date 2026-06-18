import SwiftUI
import CoreData
import CloudKit

/// Diagnostics view showing CloudKit sync status, store health, and record counts.
/// Helps debug sync issues across devices without needing Console.app or CloudKit Dashboard.
struct CloudKitDiagnosticsView: View {
    @Environment(\.managedObjectContext) private var viewContext
    private let pc = PersistenceController.shared

    @State private var iCloudStatus: String = "Checking..."
    @State private var recordCounts: [(String, Int)] = []
    @State private var privateStoreStatus: String = "Unknown"
    @State private var sharedStoreStatus: String = "Unknown"
    @State private var shareInfo: String = "None"
    @State private var lastError: String = "None"
    @State private var containerID: String = PersistenceController.cloudKitContainerID
    @State private var isRefreshing = false
    @State private var privateRecordCount: Int = 0
    @State private var sharedRecordCount: Int = 0
    @State private var showingResetSharedConfirmation = false
    @State private var showingResetAllConfirmation = false
    @State private var copiedToClipboard = false

    var body: some View {
        List {
            // MARK: - iCloud Account
            Section("iCloud Account") {
                row("Account Status", iCloudStatus)
                row("Container ID", containerID)
            }

            // MARK: - Persistent Stores
            Section("Persistent Stores") {
                row("Private Store", privateStoreStatus)
                row("Private Records", "\(privateRecordCount)")
                row("Shared Store", sharedStoreStatus)
                row("Shared Records", sharedRecordCount == 0 ? "empty (0 records)" : "\(sharedRecordCount)")
                row("Store Load Error", pc.storeLoadError ?? "None")
            }

            // MARK: - Sync Health
            Section("Sync Health") {
                row("Shared Store Healthy", pc.sharedStoreHealthy ? "Yes" : "No")
                row("Recovery In Progress", pc.syncRecoveryInProgress ? "Yes" : "No")
                row("Recovery Attempts", "\(pc.recoveryAttemptCount)")
            }

            // MARK: - CloudKit Sharing
            Section("Sharing") {
                row("Share Exists", pc.isSharing ? "Yes" : "No")
                row("Participant Count", "\(pc.participantCount)")
                if !pc.participantNames.isEmpty {
                    row("Participants", pc.participantNames.joined(separator: ", "))
                }
                row("Last Error", pc.lastError ?? "None")
            }

            // MARK: - Record Counts
            Section("Record Counts (Local)") {
                if recordCounts.isEmpty {
                    Text("Loading...")
                        .foregroundStyle(Theme.Colors.textSecondary)
                } else {
                    ForEach(recordCounts, id: \.0) { name, count in
                        row(name, "\(count)")
                    }
                }
            }

            // MARK: - Recent Sync Events (per store)
            syncEventsSection(title: "Private Store Events", storeName: "private")
            syncEventsSection(title: "Shared Store Events", storeName: "shared")

            // MARK: - Actions
            Section("Actions") {
                Button {
                    Task { await refresh() }
                } label: {
                    HStack {
                        Label("Refresh Diagnostics", systemImage: "arrow.clockwise")
                        if isRefreshing {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(isRefreshing)

                Button {
                    Task { await pc.fetchExistingShare() }
                } label: {
                    Label("Fetch Existing Share", systemImage: "icloud.and.arrow.down")
                }

                Button {
                    copyDiagnosticsToClipboard()
                } label: {
                    Label(copiedToClipboard ? "Copied!" : "Copy Diagnostics", systemImage: "doc.on.doc")
                }
            }

            // MARK: - Recovery Actions
            Section {
                Button(role: .destructive) {
                    showingResetSharedConfirmation = true
                } label: {
                    Label("Reset Shared Store", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(pc.syncRecoveryInProgress)

                Button(role: .destructive) {
                    showingResetAllConfirmation = true
                } label: {
                    Label("Reset All Sync Data", systemImage: "exclamationmark.triangle")
                }
                .disabled(pc.syncRecoveryInProgress)
            } header: {
                Text("Recovery")
            } footer: {
                Text("Reset Shared Store clears stale sharing data. Reset All re-downloads everything from iCloud.")
            }
        }
        .navigationTitle("CloudKit Diagnostics")
        .task {
            await refresh()
        }
        .confirmationDialog("Reset Shared Store?", isPresented: $showingResetSharedConfirmation, titleVisibility: .visible) {
            Button("Reset Shared Store", role: .destructive) {
                Task { await pc.resetSharedStore() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This clears stale sharing data and re-syncs the shared database. Your recipes and plans are not affected.")
        }
        .confirmationDialog("Reset All Sync Data?", isPresented: $showingResetAllConfirmation, titleVisibility: .visible) {
            Button("Reset All Sync Data", role: .destructive) {
                Task { await pc.resetAllSyncData() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes all local data and re-downloads from iCloud. Only use this if sync is completely broken.")
        }
    }

    // MARK: - Helpers

    private func syncEventsSection(title: String, storeName: String) -> some View {
        let events = pc.lastSyncEvents.filter { pc.friendlyStoreName(for: $0.storeIdentifier) == storeName }
        return Section(title) {
            if events.isEmpty {
                Text("No events")
                    .foregroundStyle(Theme.Colors.textSecondary)
            } else {
                ForEach(events.suffix(10).reversed()) { event in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: event.succeeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(event.succeeded ? .green : .red)
                                .font(AppTypography.caption)
                            Text(event.eventType.capitalized)
                                .font(AppTypography.subheadline.bold())
                            Spacer()
                            Text(event.timestamp, style: .time)
                                .font(AppTypography.caption2)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                        if let error = event.error {
                            Text(error)
                                .font(AppTypography.caption)
                                .foregroundStyle(.red)
                                .lineLimit(3)
                        }
                    }
                }
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(AppTypography.subheadline)
            Spacer()
            Text(value)
                .font(AppTypography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func copyDiagnosticsToClipboard() {
        var lines: [String] = []
        lines.append("=== CloudKit Diagnostics ===")
        lines.append("Date: \(Date())")
        lines.append("")
        lines.append("iCloud Account: \(iCloudStatus)")
        lines.append("Container: \(containerID)")
        lines.append("")
        lines.append("Private Store: \(privateStoreStatus)")
        lines.append("Shared Store: \(sharedStoreStatus)")
        lines.append("Store Load Error: \(pc.storeLoadError ?? "None")")
        lines.append("")
        lines.append("Shared Store Healthy: \(pc.sharedStoreHealthy)")
        lines.append("Recovery In Progress: \(pc.syncRecoveryInProgress)")
        lines.append("Recovery Attempts: \(pc.recoveryAttemptCount)")
        lines.append("")
        lines.append("Share Exists: \(pc.isSharing)")
        lines.append("Participant Count: \(pc.participantCount)")
        lines.append("Last Error: \(pc.lastError ?? "None")")
        lines.append("")
        lines.append("Record Counts:")
        for (name, count) in recordCounts {
            lines.append("  \(name): \(count)")
        }
        lines.append("")
        lines.append("Private Records: \(privateRecordCount)")
        lines.append("Shared Records: \(sharedRecordCount)")
        lines.append("")
        for storeName in ["private", "shared"] {
            lines.append("Recent Sync Events (\(storeName)):")
            let storeEvents = pc.lastSyncEvents.filter { pc.friendlyStoreName(for: $0.storeIdentifier) == storeName }
            if storeEvents.isEmpty {
                lines.append("  No events")
            } else {
                for event in storeEvents.suffix(10) {
                    let status = event.succeeded ? "OK" : "FAIL"
                    lines.append("  [\(status)] \(event.eventType) — \(event.timestamp)")
                    if let error = event.error {
                        lines.append("    Error: \(error)")
                    }
                }
            }
            lines.append("")
        }

        #if os(iOS)
        UIPasteboard.general.string = lines.joined(separator: "\n")
        #endif
        copiedToClipboard = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            copiedToClipboard = false
        }
    }

    @MainActor
    private func refresh() async {
        isRefreshing = true

        // iCloud account status
        do {
            let status = try await CKContainer(identifier: PersistenceController.cloudKitContainerID).accountStatus()
            switch status {
            case .available: iCloudStatus = "Available"
            case .noAccount: iCloudStatus = "No Account"
            case .restricted: iCloudStatus = "Restricted"
            case .couldNotDetermine: iCloudStatus = "Could Not Determine"
            case .temporarilyUnavailable: iCloudStatus = "Temporarily Unavailable"
            @unknown default: iCloudStatus = "Unknown (\(status.rawValue))"
            }
        } catch {
            iCloudStatus = "Error: \(error.localizedDescription)"
        }

        // Store status
        if let store = pc.privatePersistentStore {
            let url = store.url?.lastPathComponent ?? "unknown"
            privateStoreStatus = "Loaded (\(url))"
        } else {
            privateStoreStatus = "NOT LOADED"
        }

        if let store = pc.sharedPersistentStore {
            let url = store.url?.lastPathComponent ?? "unknown"
            sharedStoreStatus = "Loaded (\(url))"
        } else {
            sharedStoreStatus = "NOT LOADED"
        }

        // Record counts (total and per-store)
        let entities = [
            "Household", "User", "Recipe", "RecipeIngredient",
            "Ingredient", "FoodItem", "MealSlot", "WeekPlan",
            "MealArchetype", "GroceryItem", "SuggestionMemory"
        ]

        var counts: [(String, Int)] = []
        var privCount = 0
        var sharCount = 0
        for entity in entities {
            let request = NSFetchRequest<NSManagedObject>(entityName: entity)
            let count = (try? viewContext.count(for: request)) ?? -1
            counts.append((entity, count))

            if let privateStore = pc.privatePersistentStore {
                let privReq = NSFetchRequest<NSManagedObject>(entityName: entity)
                privReq.affectedStores = [privateStore]
                privCount += (try? viewContext.count(for: privReq)) ?? 0
            }
            if let sharedStore = pc.sharedPersistentStore {
                let sharReq = NSFetchRequest<NSManagedObject>(entityName: entity)
                sharReq.affectedStores = [sharedStore]
                sharCount += (try? viewContext.count(for: sharReq)) ?? 0
            }
        }
        recordCounts = counts
        privateRecordCount = privCount
        sharedRecordCount = sharCount

        // Share info
        await pc.fetchExistingShare()
        lastError = pc.lastError ?? "None"

        isRefreshing = false
    }
}
