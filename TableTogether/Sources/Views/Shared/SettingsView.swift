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

    @FetchRequest(sortDescriptors: [SortDescriptor(\.displayName)]) private var users: FetchedResults<User>

    @AppStorage("appearanceMode") private var appearanceMode: Int = AppearanceMode.system.rawValue

    @State private var sharingError: String?
    @State private var showingSharingError = false
    @State private var showingRemoveParticipantConfirmation = false
    @State private var participantToRemove: String?
    @State private var showingRemoveDemoDataConfirmation = false
    @State private var showingRemoveContactConfirmation = false
    @State private var contactToRemove: User?

    @State private var demoDataManager = DemoDataManager()
    @State private var paprikaImporter = PaprikaImporter()
    @State private var healthService = HealthKitService.shared

    @State private var showingPaprikaFilePicker = false
    @FetchRequest(sortDescriptors: [SortDescriptor(\.name)]) private var households: FetchedResults<Household>

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
                    // Owner (you) — editable name
                    if let user = currentUser {
                        HStack(spacing: 12) {
                            Image(systemName: "person.circle.fill")
                                .font(.title2)
                                .foregroundStyle(Theme.Colors.primary)
                            VStack(alignment: .leading, spacing: 2) {
                                TextField("Your Name", text: Binding(
                                    get: { user.displayName },
                                    set: { newValue in
                                        user.displayName = newValue
                                        viewContext.saveWithLogging(context: "update display name")
                                    }
                                ))
                                .font(.body)
                                Text("You")
                                    .font(.caption)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                            }
                        }
                    }

                    // Family members — swipe to remove
                    if persistenceController.isSharing {
                        ForEach(persistenceController.householdMembers) { member in
                            HStack(spacing: 12) {
                                Image(systemName: member.status.iconName)
                                    .font(.title2)
                                    .foregroundStyle(member.status == .accepted ? Theme.Colors.primary : .orange)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(member.name)
                                        .font(.body)
                                    Text(member.status.label)
                                        .font(.caption)
                                        .foregroundStyle(Theme.Colors.textSecondary)
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    participantToRemove = member.name
                                    showingRemoveParticipantConfirmation = true
                                } label: {
                                    Label("Remove", systemImage: "person.badge.minus")
                                }
                            }
                        }
                    }

                    // Invite button — always available
                    #if os(iOS)
                    Button {
                        SharingPresenter.shared.onError = { msg in
                            sharingError = msg
                            showingSharingError = true
                        }
                        if let share = persistenceController.existingShare {
                            SharingPresenter.shared.presentInviteMore(share: share)
                        } else if let household = households.first {
                            Task {
                                await SharingPresenter.shared.presentInvite(for: household)
                            }
                        }
                    } label: {
                        Label("Invite Family Member", systemImage: "person.badge.plus")
                    }
                    #else
                    Text("Share from iPhone or iPad to invite others")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    #endif
                } header: {
                    Text("Household")
                } footer: {
                    if persistenceController.participantCount > 0 {
                        Text("Swipe left on a person to remove them from the household.")
                    } else {
                        Text("Invite family members to share meal plans, recipes, and grocery lists.")
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
                "Remove from Household?",
                isPresented: $showingRemoveParticipantConfirmation,
                titleVisibility: .visible
            ) {
                Button("Remove", role: .destructive) {
                    Task {
                        // TODO: Remove specific participant from CKShare
                        // For now, if this is the last participant, stop sharing entirely
                        if persistenceController.participantCount <= 1 {
                            if let share = persistenceController.existingShare {
                                await persistenceController.purgeObjectsAndRecords(for: share)
                            }
                        }
                        await persistenceController.fetchExistingShare()
                        participantToRemove = nil
                    }
                }
                Button("Cancel", role: .cancel) {
                    participantToRemove = nil
                }
            } message: {
                if let name = participantToRemove {
                    Text("\(name) will lose access to your shared meal plans, recipes, and grocery lists.")
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
