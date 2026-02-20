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

    @StateObject private var demoDataManager = DemoDataManager()
    @StateObject private var paprikaImporter = PaprikaImporter()
    @StateObject private var healthService = HealthKitService.shared

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

// MARK: - Macro Goals Editor

struct MacroGoalsEditor: View {
    @Environment(\.privateDataManager) private var privateDataManager

    @State private var calorieText = ""
    @State private var proteinText = ""
    @State private var carbText = ""
    @State private var fatText = ""

    private var settings: PersonalSettings {
        privateDataManager?.settings ?? PersonalSettings()
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("These goals are personal and optional.")
                        .font(.subheadline)
                    Text("Your macro insights will reference these if set, but there's no pressure to meet them.")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }

            Section("Daily Targets (Optional)") {
                SettingsNumberField(
                    label: "Calories",
                    value: $calorieText,
                    unit: "cal"
                )

                SettingsNumberField(
                    label: "Protein",
                    value: $proteinText,
                    unit: "g"
                )

                SettingsNumberField(
                    label: "Carbohydrates",
                    value: $carbText,
                    unit: "g"
                )

                SettingsNumberField(
                    label: "Fat",
                    value: $fatText,
                    unit: "g"
                )
            }

            Section {
                Button("Clear All Goals", role: .destructive) {
                    Task {
                        await privateDataManager?.clearGoals()
                        loadCurrentValues()
                    }
                }

                Button("Save Goals") {
                    Task {
                        await saveGoals()
                    }
                }
                .fontWeight(.semibold)
            }
        }
        .navigationTitle("Nutrition Goals")
        .onAppear {
            loadCurrentValues()
        }
    }

    private func loadCurrentValues() {
        calorieText = settings.dailyCalorieTarget.map { String($0) } ?? ""
        proteinText = settings.dailyProteinTarget.map { String($0) } ?? ""
        carbText = settings.dailyCarbTarget.map { String($0) } ?? ""
        fatText = settings.dailyFatTarget.map { String($0) } ?? ""
    }

    private func saveGoals() async {
        var updated = settings
        updated.dailyCalorieTarget = Int(calorieText)
        updated.dailyProteinTarget = Int(proteinText)
        updated.dailyCarbTarget = Int(carbText)
        updated.dailyFatTarget = Int(fatText)
        await privateDataManager?.saveSettings(updated)
    }
}

// MARK: - Settings Number Field

struct SettingsNumberField: View {
    let label: String
    @Binding var value: String
    let unit: String

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            TextField("Not set", text: $value)
                #if os(iOS)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                #endif
                .frame(width: 80)
            Text(unit)
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(width: 30, alignment: .leading)
        }
    }
}

// MARK: - Measurement System Helper

/// Determines the measurement system for the current locale
private enum HealthMeasurementSystem {
    case metric    // kg, cm
    case uk        // stones + lbs, cm
    case us        // lbs, ft + in

    static var current: HealthMeasurementSystem {
        let system = Locale.current.measurementSystem
        switch system {
        case .uk: return .uk
        case .us: return .us
        default: return .metric
        }
    }

    var weightLabel: String {
        switch self {
        case .metric: return "kg"
        case .uk: return "st lbs"
        case .us: return "lbs"
        }
    }

    var heightLabel: String {
        switch self {
        case .metric: return "cm"
        case .uk: return "cm"
        case .us: return "ft in"
        }
    }

    /// Converts a display weight value to kg for storage
    func weightToKg(_ value: Double, stoneRemainder: Double = 0) -> Double {
        switch self {
        case .metric: return value
        case .uk: return (value * 6.35029) + (stoneRemainder * 0.453592)
        case .us: return value * 0.453592
        }
    }

    /// Converts kg to display weight value
    func weightFromKg(_ kg: Double) -> Double {
        switch self {
        case .metric: return kg
        case .uk: return kg / 6.35029 // returns stones (fractional)
        case .us: return kg * 2.20462
        }
    }

    /// Converts kg to whole stones
    func stonesFromKg(_ kg: Double) -> Int {
        Int(kg / 6.35029)
    }

    /// Converts kg to remainder lbs (after stones)
    func stoneLbsRemainderFromKg(_ kg: Double) -> Int {
        let totalLbs = kg * 2.20462
        let stones = Int(totalLbs / 14)
        return Int(totalLbs) - (stones * 14)
    }

    /// Converts a display height value to cm for storage
    func heightToCm(_ value: Double, inchesRemainder: Double = 0) -> Double {
        switch self {
        case .metric, .uk: return value
        case .us: return (value * 30.48) + (inchesRemainder * 2.54)
        }
    }

    /// Converts cm to display height value
    func heightFromCm(_ cm: Double) -> Double {
        switch self {
        case .metric, .uk: return cm
        case .us: return cm / 30.48 // returns feet (fractional)
        }
    }

    /// Converts cm to whole feet
    func feetFromCm(_ cm: Double) -> Int {
        Int(cm / 30.48)
    }

    /// Converts cm to remainder inches (after feet)
    func inchesRemainderFromCm(_ cm: Double) -> Int {
        let totalInches = cm / 2.54
        let feet = Int(totalInches / 12)
        return Int(totalInches) - (feet * 12)
    }
}

// MARK: - HealthKit Settings Row

struct HealthKitSettingsRow: View {
    @ObservedObject var healthService: HealthKitService
    var privateDataManager: PrivateDataManager?

    @State private var weightText = ""
    @State private var weightRemainderText = "" // for UK stones remainder lbs
    @State private var heightText = ""
    @State private var heightRemainderText = "" // for US inches remainder
    @State private var ageText = ""
    @State private var selectedSex = "other"

    private var settings: PersonalSettings {
        privateDataManager?.settings ?? PersonalSettings()
    }

    private var units: HealthMeasurementSystem { .current }

    /// Whether HealthKit has some data missing that could benefit from manual entry
    private var hasHealthKitGaps: Bool {
        healthService.latestWeight == nil ||
        healthService.latestHeight == nil ||
        healthService.age == nil ||
        healthService.biologicalSex == nil
    }

    var body: some View {
        Group {
            if healthService.isAuthorized {
                healthKitAuthorizedContent
            } else {
                healthKitNotAuthorizedContent
            }

            if let error = healthService.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .onAppear {
            loadCurrentValues()
        }
    }

    // MARK: - HealthKit Authorized

    @ViewBuilder
    private var healthKitAuthorizedContent: some View {
        // Show metrics from HealthKit
        if let weight = healthService.latestWeight {
            healthMetricRow(
                label: "Weight",
                icon: "scalemass",
                value: formattedWeight(kg: weight)
            )
        }
        if let height = healthService.latestHeight {
            healthMetricRow(
                label: "Height",
                icon: "ruler",
                value: formattedHeight(cm: height)
            )
        }
        if let age = healthService.age {
            healthMetricRow(
                label: "Age",
                icon: "calendar",
                value: "\(age) years"
            )
        }

        // If gaps in HealthKit data, offer manual fields for missing values
        if hasHealthKitGaps {
            Text("Some data not found in Health. You can enter it manually below.")
                .font(.caption)
                .foregroundStyle(Theme.Colors.textSecondary)

            manualFieldsForMissingData
        }

        Button("Refresh from Health") {
            Task { await healthService.fetchAllHealthData() }
        }

        // Link to Health app settings
        if let healthURL = URL(string: "x-apple-health://") {
            Link(destination: healthURL) {
                Label("Open Health App", systemImage: "heart.fill")
            }
        }
    }

    // MARK: - HealthKit Not Authorized

    @ViewBuilder
    private var healthKitNotAuthorizedContent: some View {
        Button {
            Task { await healthService.requestAuthorization() }
        } label: {
            Label("Connect to Apple Health", systemImage: "heart.circle.fill")
                .foregroundStyle(.red)
        }

        Text("Or enter manually:")
            .font(.subheadline)
            .foregroundStyle(Theme.Colors.textSecondary)

        allManualFields

        Button("Save") {
            Task { await saveManualValues() }
        }
        .fontWeight(.semibold)
    }

    // MARK: - Manual Fields

    /// All manual entry fields (when HealthKit is not connected)
    @ViewBuilder
    private var allManualFields: some View {
        weightField
        heightField
        ageField
        sexPicker
    }

    /// Manual fields only for data missing from HealthKit
    @ViewBuilder
    private var manualFieldsForMissingData: some View {
        if healthService.latestWeight == nil {
            weightField
        }
        if healthService.latestHeight == nil {
            heightField
        }
        if healthService.age == nil {
            ageField
        }
        if healthService.biologicalSex == nil {
            sexPicker
        }

        Button("Save") {
            Task { await saveManualValues() }
        }
        .fontWeight(.semibold)
    }

    @ViewBuilder
    private var weightField: some View {
        switch units {
        case .uk:
            HStack {
                Text("Weight")
                Spacer()
                TextField("0", text: $weightText)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    #endif
                    .frame(width: 50)
                Text("st")
                    .foregroundStyle(Theme.Colors.textSecondary)
                TextField("0", text: $weightRemainderText)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    #endif
                    .frame(width: 40)
                Text("lbs")
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        default:
            SettingsNumberField(
                label: "Weight",
                value: $weightText,
                unit: units.weightLabel
            )
        }
    }

    @ViewBuilder
    private var heightField: some View {
        switch units {
        case .us:
            HStack {
                Text("Height")
                Spacer()
                TextField("0", text: $heightText)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    #endif
                    .frame(width: 50)
                Text("ft")
                    .foregroundStyle(Theme.Colors.textSecondary)
                TextField("0", text: $heightRemainderText)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    #endif
                    .frame(width: 40)
                Text("in")
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        default:
            SettingsNumberField(
                label: "Height",
                value: $heightText,
                unit: units.heightLabel
            )
        }
    }

    private var ageField: some View {
        SettingsNumberField(
            label: "Age",
            value: $ageText,
            unit: "years"
        )
    }

    private var sexPicker: some View {
        Picker("Sex", selection: $selectedSex) {
            Text("Male").tag("male")
            Text("Female").tag("female")
            Text("Other").tag("other")
        }
    }

    // MARK: - Helpers

    private func healthMetricRow(label: String, icon: String, value: String) -> some View {
        HStack {
            Label(label, systemImage: icon)
            Spacer()
            Text(value)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }

    private func formattedWeight(kg: Double) -> String {
        switch units {
        case .metric:
            return String(format: "%.1f kg", kg)
        case .uk:
            let stones = units.stonesFromKg(kg)
            let lbs = units.stoneLbsRemainderFromKg(kg)
            return "\(stones) st \(lbs) lbs"
        case .us:
            return String(format: "%.1f lbs", kg * 2.20462)
        }
    }

    private func formattedHeight(cm: Double) -> String {
        switch units {
        case .metric, .uk:
            return String(format: "%.0f cm", cm)
        case .us:
            let feet = units.feetFromCm(cm)
            let inches = units.inchesRemainderFromCm(cm)
            return "\(feet)' \(inches)\""
        }
    }

    private func loadCurrentValues() {
        let s = settings
        if let kg = s.manualWeightKg {
            switch units {
            case .metric:
                weightText = String(format: "%.1f", kg)
            case .uk:
                weightText = String(units.stonesFromKg(kg))
                weightRemainderText = String(units.stoneLbsRemainderFromKg(kg))
            case .us:
                weightText = String(format: "%.1f", kg * 2.20462)
            }
        }
        if let cm = s.manualHeightCm {
            switch units {
            case .metric, .uk:
                heightText = String(format: "%.0f", cm)
            case .us:
                heightText = String(units.feetFromCm(cm))
                heightRemainderText = String(units.inchesRemainderFromCm(cm))
            }
        }
        if let age = s.manualAge {
            ageText = String(age)
        }
        selectedSex = s.manualBiologicalSex ?? "other"
    }

    private func saveManualValues() async {
        var updated = settings

        // Convert weight to kg
        if let weightVal = Double(weightText) {
            let remainder = Double(weightRemainderText) ?? 0
            updated.manualWeightKg = units.weightToKg(weightVal, stoneRemainder: remainder)
        }

        // Convert height to cm
        if let heightVal = Double(heightText) {
            let remainder = Double(heightRemainderText) ?? 0
            updated.manualHeightCm = units.heightToCm(heightVal, inchesRemainder: remainder)
        }

        updated.manualAge = Int(ageText)
        updated.manualBiologicalSex = selectedSex

        await privateDataManager?.saveSettings(updated)

        // Update health service manual values for BMR calculation
        healthService.loadManualValues(from: updated)
    }
}


// MARK: - Sync Status Row

struct SyncStatusRow: View {
    let coordinator: SharingCoordinator?

    private var syncStatus: SyncStatus {
        coordinator?.syncStatus ?? .offline
    }

    private var statusColor: Color {
        switch syncStatus {
        case .synced: return .green
        case .syncing: return .blue
        case .offline: return .orange
        case .error: return .red
        }
    }

    var body: some View {
        HStack {
            Text("iCloud Sync")
            Spacer()

            if syncStatus == .syncing {
                ProgressView()
                    .scaleEffect(0.8)
                    .padding(.trailing, 4)
            } else {
                Image(systemName: syncStatus.iconName)
                    .foregroundStyle(statusColor)
            }

            Text(syncStatus.displayName)
                .font(.subheadline)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            coordinator?.refreshSync()
        }
    }
}

// MARK: - Placeholder Views

struct DefaultArchetypesView: View {
    var body: some View {
        List {
            ForEach(ArchetypeType.allCases, id: \.self) { archetype in
                HStack {
                    Image(systemName: archetype.icon)
                        .foregroundStyle(archetype.color)
                        .frame(width: 30)
                    VStack(alignment: .leading) {
                        Text(archetype.displayName)
                        Text(archetype.description)
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
            }
        }
        .navigationTitle("Meal Archetypes")
    }
}

struct IngredientDatabaseView: View {
    @Query private var ingredients: [Ingredient]

    var body: some View {
        List {
            ForEach(ingredients) { ingredient in
                HStack {
                    Circle()
                        .fill(ingredient.category.color)
                        .frame(width: 8, height: 8)
                    Text(ingredient.name)
                    Spacer()
                    if let cal = ingredient.caloriesPer100g {
                        Text("\(Int(cal)) cal/100g")
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
            }
        }
        .navigationTitle("Ingredients")
    }
}

// MARK: - Demo Data Toggle Row

struct DemoDataToggleRow: View {
    @ObservedObject var demoDataManager: DemoDataManager
    @Binding var showingConfirmation: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label {
                    Text("Demo Data")
                } icon: {
                    Image(systemName: "theatermasks.fill")
                        .foregroundStyle(Theme.Colors.secondary)
                }

                Spacer()

                if demoDataManager.isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Toggle("", isOn: Binding(
                        get: { demoDataManager.isDemoDataEnabled },
                        set: { newValue in
                            if newValue {
                                // Turning on - no confirmation needed
                                Task {
                                    await demoDataManager.toggleDemoData()
                                }
                            } else {
                                // Turning off - show confirmation
                                showingConfirmation = true
                            }
                        }
                    ))
                    .labelsHidden()
                }
            }

            Text("Show sample data for testing")
                .font(.caption)
                .foregroundStyle(Theme.Colors.textSecondary)

            if let error = demoDataManager.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .disabled(demoDataManager.isLoading)
    }
}

// MARK: - Paprika Import Row

struct PaprikaImportRow: View {
    @ObservedObject var importer: PaprikaImporter
    @Binding var showingFilePicker: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if importer.isImporting {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text(importer.progress)
                        .font(.subheadline)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            } else if let result = importer.result {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Import complete", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.subheadline)

                    Text("\(result.imported) imported, \(result.skipped) skipped")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)

                    if !result.errors.isEmpty {
                        Text(result.errors.joined(separator: ". "))
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            } else {
                Button {
                    showingFilePicker = true
                } label: {
                    Label("Import from Paprika 3", systemImage: "square.and.arrow.down")
                }
            }

            if let error = importer.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .disabled(importer.isImporting)
    }
}

// MARK: - Nutrition Disclaimer View

struct NutritionDisclaimerView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Group {
                    Text("Nutrition Estimates")
                        .font(.headline)
                        .foregroundStyle(Theme.Colors.textPrimary)

                    Text("Nutrition data in TableTogether is estimated using public food databases, including USDA FoodData Central and Open Food Facts. Estimates are generated through on-device language processing and database lookups.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.Colors.textSecondary)

                    Text("Estimates may vary from actual values due to preparation methods, portion sizes, regional product variations, and database coverage. All values should be considered approximate.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }

                Group {
                    Text("Not Medical Advice")
                        .font(.headline)
                        .foregroundStyle(Theme.Colors.textPrimary)

                    Text("TableTogether is not a medical device and does not diagnose, treat, cure, or prevent any medical condition. The nutrition information provided is for general informational purposes only.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.Colors.textSecondary)

                    Text("Always consult a qualified healthcare professional before making changes to your diet, especially if you have a medical condition or specific dietary requirements.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }

                Group {
                    Text("Your Privacy")
                        .font(.headline)
                        .foregroundStyle(Theme.Colors.textPrimary)

                    Text("Meal logs, nutrition targets, and personal insights are stored privately and never shared with other household members. If connected to Apple Health, nutrition data is written to HealthKit on your device.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.Colors.textSecondary)

                    Text("Food search queries sent to USDA and Open Food Facts are anonymous and not linked to your identity.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }

                Group {
                    Text("Data Sources")
                        .font(.headline)
                        .foregroundStyle(Theme.Colors.textPrimary)

                    VStack(alignment: .leading, spacing: 8) {
                        dataSourceRow(
                            name: "USDA FoodData Central",
                            detail: "U.S. Department of Agriculture, public domain"
                        )
                        dataSourceRow(
                            name: "Open Food Facts",
                            detail: "Community database, Open Database License (ODbL)"
                        )
                        dataSourceRow(
                            name: "Apple Intelligence",
                            detail: "On-device processing, iOS 26+"
                        )
                    }
                }
            }
            .padding()
        }
        .background(Theme.Colors.background)
        .navigationTitle("Nutrition Disclaimer")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func dataSourceRow(name: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(Theme.Colors.textPrimary)
            Text(detail)
                .font(.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }
}

#Preview {
    SettingsView()
        .modelContainer(for: User.self, inMemory: true)
}
