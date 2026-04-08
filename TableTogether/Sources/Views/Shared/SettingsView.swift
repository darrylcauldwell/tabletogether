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
    @State private var showingInviteNamePrompt = false
    @State private var inviteRecipientName: String = ""
    @State private var selectedHouseholdMember: PersistenceController.HouseholdMember?
    @State private var showingRemoveDemoDataConfirmation = false
    @State private var showingRemoveContactConfirmation = false
    @State private var contactToRemove: User?

    @State private var demoDataManager = DemoDataManager()
    @State private var paprikaImporter = PaprikaImporter()
    @State private var jsonRecipeImporter = JSONRecipeImporter()
    @State private var foodItemImporter = FoodItemImporter()
    @State private var showingFoodItemFilePicker = false
    @State private var ingredientBackfillService = IngredientBackfillService()
    @State private var showingBackfillConfirmation = false
    @State private var showingBackfillResult = false
    @State private var healthService = HealthKitService.shared

    @State private var showingPaprikaFilePicker = false
    @State private var showingJSONFilePicker = false
    @State private var recipeExporter = RecipeExporter()
    @State private var showingExportFilePicker = false
    @State private var exportDocument: RecipeExportDocument?
    @FetchRequest(sortDescriptors: [SortDescriptor(\.name)]) private var households: FetchedResults<Household>
    @FetchRequest(sortDescriptors: [SortDescriptor(\.title)]) private var allRecipes: FetchedResults<Recipe>

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

                    // Family members — tap for details, swipe to remove
                    if persistenceController.isSharing {
                        ForEach(persistenceController.householdMembers) { member in
                            #if os(iOS)
                            Button {
                                selectedHouseholdMember = member
                            } label: {
                                householdMemberRow(member)
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    selectedHouseholdMember = member
                                } label: {
                                    Label("Manage", systemImage: "person.crop.circle.badge.questionmark")
                                }
                                .tint(Theme.Colors.primary)
                            }
                            #else
                            householdMemberRow(member)
                            #endif
                        }
                    }

                    // Invite button — always available
                    #if os(iOS)
                    Button {
                        inviteRecipientName = ""
                        showingInviteNamePrompt = true
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

                dataSection

                // MARK: - Libraries
                Section("Libraries") {
                    NavigationLink {
                        IngredientLibraryView()
                    } label: {
                        Label("Ingredient Library", systemImage: "leaf")
                    }
                    NavigationLink {
                        FoodItemLibraryView()
                    } label: {
                        Label("Food Item Library", systemImage: "fork.knife.circle")
                    }
                }

                // MARK: - Diagnostics
                Section {
                    NavigationLink {
                        CloudKitDiagnosticsView()
                    } label: {
                        Label("CloudKit Diagnostics", systemImage: "stethoscope")
                    }
                } header: {
                    Text("Developer")
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
            .modifier(SharingAlertsModifier(
                showingSharingError: $showingSharingError,
                sharingError: sharingError,
                showingInviteNamePrompt: $showingInviteNamePrompt,
                inviteRecipientName: $inviteRecipientName,
                onContinue: startInvite
            ))
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
            .modifier(BackfillAlertsModifier(
                showingConfirmation: $showingBackfillConfirmation,
                showingResult: $showingBackfillResult,
                service: ingredientBackfillService,
                onConfirm: {
                    let result = ingredientBackfillService.run(
                        context: viewContext,
                        household: households.first
                    )
                    if result.processed > 0 {
                        showingBackfillResult = true
                    }
                }
            ))
            .modifier(FileImportersModifier(
                showingPaprikaFilePicker: $showingPaprikaFilePicker,
                showingJSONFilePicker: $showingJSONFilePicker,
                showingFoodItemFilePicker: $showingFoodItemFilePicker,
                showingExportFilePicker: $showingExportFilePicker,
                exportDocument: $exportDocument,
                paprikaImporter: paprikaImporter,
                jsonRecipeImporter: jsonRecipeImporter,
                foodItemImporter: foodItemImporter,
                viewContext: viewContext,
                household: households.first
            ))
            .onAppear {
                demoDataManager.configure(
                    modelContext: viewContext,
                    privateDataManager: privateDataManager
                )
            }
            #if os(iOS)
            .sheet(item: $selectedHouseholdMember) { member in
                HouseholdMemberDetailSheet(member: member) {
                    selectedHouseholdMember = nil
                }
            }
            #endif
        }
    }

    /// One row in the Household section showing avatar + name + status.
    @ViewBuilder
    private func householdMemberRow(_ member: PersistenceController.HouseholdMember) -> some View {
        HStack(spacing: 12) {
            Image(systemName: member.status.iconName)
                .font(.title2)
                .foregroundStyle(member.status == .accepted ? Theme.Colors.primary : .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(member.name)
                    .font(.body)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(member.status.label)
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer()
            #if os(iOS)
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
            #endif
        }
        .contentShape(Rectangle())
    }

    // MARK: - Data Section
    //
    // Extracted from `body` (rather than inlined) to keep the SwiftUI
    // type-checker within budget — adding the JSON import row + the
    // backfill button + the Libraries section pushed `body` over its
    // complexity limit and triggered the "compiler unable to type-check
    // in reasonable time" warning even though the build succeeded.

    @ViewBuilder
    private var dataSection: some View {
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

            // JSON Recipe Import (curated library)
            JSONRecipeImportRow(
                importer: jsonRecipeImporter,
                showingFilePicker: $showingJSONFilePicker
            )

            // JSON Food Item Import (curated nutrition seed)
            JSONFoodItemImportRow(
                importer: foodItemImporter,
                showingFilePicker: $showingFoodItemFilePicker
            )

            Button("Export Recipes") {
                do {
                    let data = try recipeExporter.exportRecipes(Array(allRecipes))
                    exportDocument = RecipeExportDocument(data: data)
                    showingExportFilePicker = true
                } catch {
                    AppLogger.app.error("Export failed: \(error.localizedDescription)")
                }
            }
            .disabled(allRecipes.isEmpty)

            // Reorganise Ingredient Library — backfills RecipeIngredient.ingredient
            // master FKs for rows that pre-date the resolver integration (#59).
            // Idempotent: subsequent runs only touch rows that still have nil FK.
            Button {
                showingBackfillConfirmation = true
            } label: {
                if ingredientBackfillService.isRunning {
                    HStack {
                        Text("Reorganising Ingredient Library…")
                        Spacer()
                        ProgressView()
                    }
                } else {
                    Text("Reorganise Ingredient Library")
                }
            }
            .disabled(ingredientBackfillService.isRunning || allRecipes.isEmpty)
        }
    }

    // Sharing actions are handled directly by SharingPresenter.shared
    // from the button actions in the Household section above.

    #if os(iOS)
    private func startInvite() {
        let label = inviteRecipientName.trimmingCharacters(in: .whitespaces)
        let recipientLabel = label.isEmpty ? nil : label

        SharingPresenter.shared.onError = { msg in
            sharingError = msg
            showingSharingError = true
        }

        if let share = persistenceController.existingShare {
            SharingPresenter.shared.presentInviteMore(share: share, recipientLabel: recipientLabel)
        } else if let household = households.first {
            Task {
                await SharingPresenter.shared.presentInvite(
                    for: household,
                    recipientLabel: recipientLabel
                )
            }
        }
    }
    #endif
}

// MARK: - File Importers Modifier
//
// Extracted to keep SettingsView.body within the SwiftUI type-checker's
// complexity budget. Bundles the four file picker flows that the Data
// section needs: Paprika import, JSON recipe import, JSON food item import,
// and recipe export. Each fileImporter/fileExporter has a closure-heavy
// callback and stacking four of them inline pushed the body over the
// type-checker's limit.

private struct FileImportersModifier: ViewModifier {
    @Binding var showingPaprikaFilePicker: Bool
    @Binding var showingJSONFilePicker: Bool
    @Binding var showingFoodItemFilePicker: Bool
    @Binding var showingExportFilePicker: Bool
    @Binding var exportDocument: RecipeExportDocument?
    let paprikaImporter: PaprikaImporter
    let jsonRecipeImporter: JSONRecipeImporter
    let foodItemImporter: FoodItemImporter
    let viewContext: NSManagedObjectContext
    let household: Household?

    func body(content: Content) -> some View {
        content
            .fileImporter(
                isPresented: $showingPaprikaFilePicker,
                allowedContentTypes: [.paprikaRecipes, .data],
                allowsMultipleSelection: false
            ) { result in
                handlePaprikaResult(result)
            }
            .fileImporter(
                isPresented: $showingJSONFilePicker,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                handleJSONResult(result)
            }
            .fileImporter(
                isPresented: $showingFoodItemFilePicker,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                handleFoodItemResult(result)
            }
            .fileExporter(
                isPresented: $showingExportFilePicker,
                document: exportDocument,
                contentType: .json,
                defaultFilename: "TableTogether-Recipes.json"
            ) { result in
                if case .failure(let error) = result {
                    AppLogger.app.error("Export save failed: \(error.localizedDescription)")
                }
                exportDocument = nil
            }
    }

    private func handlePaprikaResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            if let url = urls.first {
                Task {
                    await paprikaImporter.importRecipes(
                        from: url,
                        context: viewContext,
                        household: household
                    )
                }
            }
        case .failure(let error):
            paprikaImporter.errorMessage = error.localizedDescription
        }
    }

    private func handleJSONResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            if let url = urls.first {
                Task {
                    await jsonRecipeImporter.importRecipes(
                        from: url,
                        context: viewContext,
                        household: household
                    )
                }
            }
        case .failure(let error):
            jsonRecipeImporter.errorMessage = error.localizedDescription
        }
    }

    private func handleFoodItemResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            if let url = urls.first {
                Task {
                    await foodItemImporter.importFoodItems(
                        from: url,
                        context: viewContext,
                        household: household
                    )
                }
            }
        case .failure(let error):
            foodItemImporter.errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Backfill Alerts Modifier
//
// Extracted (like SharingAlertsModifier below) to keep SettingsView.body within
// the SwiftUI type-checker's complexity budget. Hosts the confirm-and-result
// dialogs for the "Reorganise Ingredient Library" action (#59 Phase 5).

private struct BackfillAlertsModifier: ViewModifier {
    @Binding var showingConfirmation: Bool
    @Binding var showingResult: Bool
    let service: IngredientBackfillService
    let onConfirm: () -> Void

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                "Reorganise Ingredient Library?",
                isPresented: $showingConfirmation,
                titleVisibility: .visible
            ) {
                Button("Reorganise") {
                    onConfirm()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Walks every recipe ingredient in your library, deduplicates them by exact name match, and creates Ingredient master records. Safe to re-run — already-linked rows are skipped.")
            }
            .alert(
                "Ingredient Library Reorganised",
                isPresented: $showingResult,
                presenting: service.result
            ) { _ in
                Button("OK") {}
            } message: { result in
                Text(
                    "Processed \(result.processed) ingredient rows.\n" +
                    "Newly linked: \(result.linked)\n" +
                    "Already linked: \(result.alreadyLinked)\n" +
                    "Created \(result.mastersCreated) new Ingredient master records."
                )
            }
    }
}

// MARK: - Sharing Alerts Modifier
//
// Extracted to keep SettingsView.body within the SwiftUI type-checker's complexity
// budget. The body has many alerts/sheets and adding more inline causes timeouts.

private struct SharingAlertsModifier: ViewModifier {
    @Binding var showingSharingError: Bool
    let sharingError: String?
    @Binding var showingInviteNamePrompt: Bool
    @Binding var inviteRecipientName: String
    let onContinue: () -> Void

    func body(content: Content) -> some View {
        content
            .alert("Sharing Error", isPresented: $showingSharingError) {
                Button("OK") {}
            } message: {
                Text(sharingError ?? "Unknown error")
            }
            .alert("Invite Family Member", isPresented: $showingInviteNamePrompt) {
                #if os(iOS)
                TextField("Name (optional)", text: $inviteRecipientName)
                    .textInputAutocapitalization(.words)
                #endif
                Button("Cancel", role: .cancel) {}
                Button("Continue") { onContinue() }
            } message: {
                Text("Optionally enter the name of the person you're inviting. This helps you identify pending invites in your household list.")
            }
    }
}

#Preview {
    SettingsView()
        .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
}
