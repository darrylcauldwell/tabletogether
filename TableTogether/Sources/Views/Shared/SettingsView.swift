import SwiftUI
import SwiftData
import CloudKit

// MARK: - App URLs

/// Safe URL constants for the app
/// Note: URLs will be configured when domain is established
private enum AppURLs {
    static let help: URL? = nil
    static let privacy: URL? = nil
}

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.sharingCoordinator) private var sharingCoordinator
    @Environment(\.privateDataManager) private var privateDataManager
    @Environment(\.calendarService) private var calendarService
    @Environment(\.cloudSharingManager) private var cloudSharingManager

    @Query private var users: [User]

    @AppStorage("appearanceMode") private var appearanceMode: Int = AppearanceMode.system.rawValue

    @State private var showingAddMember = false
    @State private var showingSharingSheet = false
    @State private var sharingShare: CKShare?
    @State private var showingRemoveDemoDataConfirmation = false
    @State private var showingRemoveContactConfirmation = false
    @State private var contactToRemove: User?

    @State private var demoDataManager = DemoDataManager()
    @State private var paprikaImporter = PaprikaImporter()
    @State private var healthService = HealthKitService.shared

    @State private var showingPaprikaFilePicker = false
    @Query private var households: [Household]

    private var selectedAppearanceMode: AppearanceMode {
        AppearanceMode(rawValue: appearanceMode) ?? .system
    }

    var currentUser: User? {
        users.first // In a real app, would be based on CloudKit identity
    }

    /// Personal settings from private storage
    private var settings: PersonalSettings {
        privateDataManager?.settings ?? PersonalSettings()
    }

    var body: some View {
        NavigationStack {
            List {
                // MARK: - Apple Health Section
                Section {
                    HealthKitSettingsRow(
                        healthService: healthService,
                        privateDataManager: privateDataManager
                    )
                    .onAppear {
                        healthService.loadManualValues(from: settings)
                    }
                } header: {
                    Text("Apple Health")
                } footer: {
                    Text("Used for estimating daily calorie needs. This data is personal and never shared.")
                }

                // MARK: - Household Section
                Section {
                    // Sharing status
                    if let manager = cloudSharingManager {
                        if manager.isSharing {
                            HStack {
                                Image(systemName: "checkmark.icloud.fill")
                                    .foregroundStyle(.green)
                                Text("Sharing active")
                                Spacer()
                                Text("\(manager.participantCount) people")
                                    .foregroundStyle(Theme.Colors.textSecondary)
                            }
                        }
                    }

                    // Household members from SwiftData
                    ForEach(users.filter { $0.id != currentUser?.id }) { user in
                        HStack {
                            UserAvatar(user: user, size: 40)
                            VStack(alignment: .leading) {
                                Text(user.displayName)
                                    .font(.body)
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                contactToRemove = user
                                showingRemoveContactConfirmation = true
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                    }

                    // Share / manage button
                    #if os(iOS)
                    Button {
                        Task { await prepareSharingSheet() }
                    } label: {
                        if cloudSharingManager?.isSharing == true {
                            Label("Manage Sharing", systemImage: "person.2.fill")
                        } else {
                            Label("Share Household", systemImage: "person.badge.plus")
                        }
                    }
                    #else
                    Text("Share from iPhone or iPad to invite others")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    #endif
                } header: {
                    Text("Household")
                } footer: {
                    Text("Share your meal plans, recipes, and grocery lists with others.")
                }

                // MARK: - Personal Preferences Section
                Section("Personal Preferences") {
                    Toggle("Show Macro Insights", isOn: Binding(
                        get: { settings.showMacroInsights },
                        set: { newValue in
                            Task {
                                await privateDataManager?.setShowMacroInsights(newValue)
                            }
                        }
                    ))

                    NavigationLink {
                        MacroGoalsEditor()
                    } label: {
                        HStack {
                            Text("Nutrition Goals")
                            Spacer()
                            if settings.hasGoalsSet {
                                Text("Set")
                                    .foregroundStyle(Theme.Colors.textSecondary)
                            } else {
                                Text("Not set")
                                    .foregroundStyle(Theme.Colors.textSecondary)
                            }
                        }
                    }
                }

                // MARK: - Calendar Section
                Section("Calendar") {
                    NavigationLink {
                        CalendarSettingsView()
                    } label: {
                        HStack {
                            Image(systemName: "calendar")
                                .foregroundStyle(Theme.Colors.primary)
                            Text("Calendar Sync")
                            Spacer()
                            Text(calendarService?.settings.isEnabled == true ? "On" : "Off")
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                    }
                }

                // MARK: - Appearance Section
                Section("Appearance") {
                    Picker("Mode", selection: $appearanceMode) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(mode.displayName).tag(mode.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                // MARK: - App Defaults Section
                Section("App Defaults") {
                    NavigationLink {
                        DefaultArchetypesView()
                    } label: {
                        Text("Default Meal Archetypes")
                    }

                    NavigationLink {
                        IngredientDatabaseView()
                    } label: {
                        Text("Ingredient Database")
                    }
                }

                // MARK: - Data Section
                Section("Data") {
                    SyncStatusRow(coordinator: sharingCoordinator)

                    DemoDataToggleRow(
                        demoDataManager: demoDataManager,
                        showingConfirmation: $showingRemoveDemoDataConfirmation
                    )

                    // Paprika Import
                    PaprikaImportRow(
                        importer: paprikaImporter,
                        showingFilePicker: $showingPaprikaFilePicker
                    )

                    Button("Export Data") {
                        // Export functionality
                    }
                }

                // MARK: - About Section
                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }

                    if let helpURL = AppURLs.help {
                        Link(destination: helpURL) {
                            HStack {
                                Text("Help & Support")
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.caption)
                            }
                        }
                    }

                    if let privacyURL = AppURLs.privacy {
                        Link(destination: privacyURL) {
                            HStack {
                                Text("Privacy Policy")
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.caption)
                            }
                        }
                    }

                    NavigationLink {
                        NutritionDisclaimerView()
                    } label: {
                        Text("Nutrition Disclaimer")
                    }
                }
            }
            .navigationTitle("Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            #if os(iOS)
            .sheet(isPresented: $showingSharingSheet) {
                if let share = sharingShare, let manager = cloudSharingManager {
                    CloudSharingSheet(
                        share: share,
                        container: manager.ckContainer,
                        onDismiss: {
                            Task { await manager.fetchExistingShare() }
                        }
                    )
                }
            }
            #endif
            .confirmationDialog(
                "Remove Contact?",
                isPresented: $showingRemoveContactConfirmation,
                titleVisibility: .visible
            ) {
                Button("Remove", role: .destructive) {
                    if let user = contactToRemove {
                        modelContext.delete(user)
                        modelContext.saveWithLogging(context: "remove trusted contact")
                    }
                    contactToRemove = nil
                }
                Button("Cancel", role: .cancel) {
                    contactToRemove = nil
                }
            } message: {
                if let user = contactToRemove {
                    Text("Remove \(user.displayName) from your trusted contacts? They will no longer have access to shared meal plans and recipes.")
                }
            }
            .confirmationDialog(
                "Remove Demo Data?",
                isPresented: $showingRemoveDemoDataConfirmation,
                titleVisibility: .visible
            ) {
                Button("Remove Demo Data", role: .destructive) {
                    Task {
                        await demoDataManager.toggleDemoData()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will remove all sample recipes, meal plans, and household members. Your real data is not affected.")
            }
            .fileImporter(
                isPresented: $showingPaprikaFilePicker,
                allowedContentTypes: [.paprikaRecipes, .data],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first {
                        Task {
                            await paprikaImporter.importRecipes(
                                from: url,
                                context: modelContext,
                                household: households.first
                            )
                        }
                    }
                case .failure(let error):
                    paprikaImporter.errorMessage = error.localizedDescription
                }
            }
            .onAppear {
                demoDataManager.configure(
                    modelContext: modelContext,
                    privateDataManager: privateDataManager
                )
            }
        }
    }

    // MARK: - Sharing Actions

    #if os(iOS)
    private func prepareSharingSheet() async {
        guard let manager = cloudSharingManager else { return }

        do {
            if let existing = manager.existingShare {
                sharingShare = existing
            } else {
                sharingShare = try await manager.createShare()
            }
            showingSharingSheet = true
        } catch {
            AppLogger.sharing.error("Failed to prepare sharing: \(error.localizedDescription)")
        }
    }
    #endif
}

#Preview {
    SettingsView()
        .modelContainer(for: User.self, inMemory: true)
}
