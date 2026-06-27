import SwiftUI
import CoreData
import CloudKit
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
                        .font(AppTypography.subheadline)
                    Text("Your macro insights will reference these if set, but there's no pressure to meet them.")
                        .font(AppTypography.caption)
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
enum HealthMeasurementSystem {
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
