import SwiftUI
import CoreData
import CloudKit

// MARK: - App URLs

/// Safe URL constants for the app
/// Note: URLs will be configured when domain is established
private enum AppURLs {
    static let help: URL? = nil
    static let privacy: URL? = nil
}

struct SettingsView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.privateDataManager) private var privateDataManager
    @Environment(\.calendarService) private var calendarService
    private var persistenceController: PersistenceController { PersistenceController.shared }

    @FetchRequest(sortDescriptors: []) private var users: FetchedResults<User>

    @AppStorage("appearanceMode") private var appearanceMode: Int = AppearanceMode.system.rawValue

    @State private var sharingError: String?
    @State private var showingSharingError = false
    @State private var showingStopSharingConfirmation = false
    @State private var isStoppingShare = false
    @State private var showingRemoveDemoDataConfirmation = false
    @State private var showingRemoveContactConfirmation = false
    @State private var contactToRemove: User?

    @State private var demoDataManager = DemoDataManager()
    @State private var paprikaImporter = PaprikaImporter()
    @State private var healthService = HealthKitService.shared

    @State private var showingPaprikaFilePicker = false
    @FetchRequest(sortDescriptors: []) private var households: FetchedResults<Household>

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
                    // Sync status
                    HStack {
                        Image(systemName: "checkmark.icloud")
                            .foregroundStyle(.green)
                        Text("iCloud Sync")
                        Spacer()
                        Text("Active")
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }

                    // Participant list (when sharing)
                    if persistenceController.isSharing {
                        ForEach(persistenceController.participantNames, id: \.self) { name in
                            HStack {
                                Image(systemName: "person.circle.fill")
                                    .foregroundStyle(Theme.Colors.primary)
                                Text(name)
                            }
                        }
                    }

                    #if os(iOS)
                    if persistenceController.isSharing, let share = persistenceController.existingShare {
                        // Invite more people
                        Button {
                            SharingPresenter.shared.onError = { msg in
                                sharingError = msg
                                showingSharingError = true
                            }
                            SharingPresenter.shared.presentInviteMore(share: share)
                        } label: {
                            Label("Invite More People", systemImage: "person.badge.plus")
                        }

                        // Stop sharing — simple custom UI, no UICloudSharingController
                        Button(role: .destructive) {
                            showingStopSharingConfirmation = true
                        } label: {
                            Label("Stop Sharing", systemImage: "xmark.circle")
                        }
                    } else if let household = households.first {
                        // No share yet — create one and invite
                        Button {
                            SharingPresenter.shared.onError = { msg in
                                sharingError = msg
                                showingSharingError = true
                            }
                            Task {
                                await SharingPresenter.shared.presentInvite(for: household)
                            }
                        } label: {
                            Label("Invite to Household", systemImage: "person.badge.plus")
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
                    if persistenceController.isSharing {
                        if persistenceController.participantCount > 0 {
                            Text("Sharing with \(persistenceController.participantCount) people")
                        } else {
                            Text("No one has joined yet. Send an invitation to get started.")
                        }
                    } else {
                        Text("Share your meal plans, recipes, and grocery lists with others.")
                    }
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
                    SyncStatusRow()

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
            .alert("Sharing Error", isPresented: $showingSharingError) {
                Button("OK") {}
            } message: {
                Text(sharingError ?? "Unknown error")
            }
            .confirmationDialog(
                "Stop Sharing?",
                isPresented: $showingStopSharingConfirmation,
                titleVisibility: .visible
            ) {
                Button("Stop Sharing", role: .destructive) {
                    Task {
                        isStoppingShare = true
                        if let share = persistenceController.existingShare {
                            await persistenceController.purgeObjectsAndRecords(for: share)
                        }
                        await persistenceController.fetchExistingShare()
                        isStoppingShare = false
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Others will lose access to your shared meal plans, recipes, and grocery lists. This cannot be undone.")
            }
            #endif
            .confirmationDialog(
                "Remove Contact?",
                isPresented: $showingRemoveContactConfirmation,
                titleVisibility: .visible
            ) {
                Button("Remove", role: .destructive) {
                    if let user = contactToRemove {
                        viewContext.delete(user)
                        viewContext.saveWithLogging(context: "remove trusted contact")
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
                                context: viewContext,
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
                    modelContext: viewContext,
                    privateDataManager: privateDataManager
                )
            }
        }
    }

    // Sharing actions are handled directly by SharingPresenter.shared
    // from the button actions in the Household section above.
}

#Preview {
    SettingsView()
        .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
}
