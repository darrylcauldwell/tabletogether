import SwiftUI
import CoreData
import CloudKit
// MARK: - HealthKit Settings Row

struct HealthKitSettingsRow: View {
    var healthService: HealthKitService
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
                    .font(AppTypography.caption)
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
                .font(AppTypography.caption)
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
            .font(AppTypography.subheadline)
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
