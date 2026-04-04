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
                row("Shared Store", sharedStoreStatus)
                row("Store Load Error", pc.storeLoadError ?? "None")
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

            // MARK: - Actions
            Section {
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
            }
        }
        .navigationTitle("CloudKit Diagnostics")
        .task {
            await refresh()
        }
    }

    // MARK: - Helpers

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
            Spacer()
            Text(value)
                .font(.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.trailing)
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

        // Record counts
        let entities = [
            "Household", "User", "Recipe", "RecipeIngredient",
            "Ingredient", "FoodItem", "MealSlot", "WeekPlan",
            "MealArchetype", "GroceryItem", "SuggestionMemory"
        ]

        var counts: [(String, Int)] = []
        for entity in entities {
            let request = NSFetchRequest<NSManagedObject>(entityName: entity)
            let count = (try? viewContext.count(for: request)) ?? -1
            counts.append((entity, count))
        }
        recordCounts = counts

        // Share info
        await pc.fetchExistingShare()
        lastError = pc.lastError ?? "None"

        isRefreshing = false
    }
}
