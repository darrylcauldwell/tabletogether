import Foundation
import HealthKit
import SwiftUI

/// Service for reading and writing health data via Apple HealthKit.
///
/// Reads:
/// - Weight (for BMR/TDEE calculations)
/// - Height (for BMR/TDEE calculations)
/// - Biological sex (for BMR calculations)
/// - Date of birth (for age-based BMR calculations)
///
/// Writes:
/// - Dietary energy (calories)
/// - Dietary protein
/// - Dietary carbohydrates
/// - Dietary fat
///
/// Note: All health data is personal and private. This service respects
/// the app's principle that "Food is shared. Bodies are not."
@MainActor
final class HealthKitService: ObservableObject {
    static let shared = HealthKitService()

    private let healthStore = HKHealthStore()

    // MARK: - Published Properties

    @Published private(set) var isAuthorized = false
    @Published private(set) var authorizationStatus: HKAuthorizationStatus = .notDetermined

    @Published private(set) var latestWeight: Double? // in kg
    @Published private(set) var latestHeight: Double? // in cm
    @Published private(set) var biologicalSex: HKBiologicalSex?
    @Published private(set) var dateOfBirth: Date?

    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    // MARK: - Manual Fallback Properties

    /// Manual values loaded from PersonalSettings when HealthKit data is unavailable
    @Published var manualWeightKg: Double?
    @Published var manualHeightCm: Double?
    @Published var manualAge: Int?
    @Published var manualBiologicalSex: String?

    // MARK: - Computed Properties

    /// Age in years, calculated from date of birth
    var age: Int? {
        guard let dob = dateOfBirth else { return nil }
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year], from: dob, to: Date())
        return components.year
    }

    /// Height in feet and inches (for display)
    var heightInFeetAndInches: (feet: Int, inches: Int)? {
        guard let heightCm = latestHeight else { return nil }
        let totalInches = heightCm / 2.54
        let feet = Int(totalInches) / 12
        let inches = Int(totalInches) % 12
        return (feet, inches)
    }

    /// Weight in pounds (for display)
    var weightInPounds: Double? {
        guard let weightKg = latestWeight else { return nil }
        return weightKg * 2.20462
    }

    // MARK: - Effective Values (HealthKit with manual fallback)

    /// Weight used for calculations — HealthKit value preferred, manual fallback
    var effectiveWeightKg: Double? {
        latestWeight ?? manualWeightKg
    }

    /// Height used for calculations — HealthKit value preferred, manual fallback
    var effectiveHeightCm: Double? {
        latestHeight ?? manualHeightCm
    }

    /// Age used for calculations — HealthKit value preferred, manual fallback
    var effectiveAge: Int? {
        age ?? manualAge
    }

    /// Biological sex used for calculations — HealthKit value preferred, manual fallback
    var effectiveBiologicalSex: HKBiologicalSex? {
        if let sex = biologicalSex { return sex }
        switch manualBiologicalSex {
        case "male": return .male
        case "female": return .female
        case "other": return .other
        default: return nil
        }
    }

    /// Loads manual values from PersonalSettings
    func loadManualValues(from settings: PersonalSettings) {
        manualWeightKg = settings.manualWeightKg
        manualHeightCm = settings.manualHeightCm
        manualAge = settings.manualAge
        manualBiologicalSex = settings.manualBiologicalSex
    }

    /// Estimated Basal Metabolic Rate using Mifflin-St Jeor equation
    /// Uses HealthKit values when available, falls back to manual values
    /// Returns nil if required data is missing from both sources
    var estimatedBMR: Int? {
        guard let weight = effectiveWeightKg,
              let height = effectiveHeightCm,
              let age = effectiveAge,
              let sex = effectiveBiologicalSex else {
            return nil
        }

        // Mifflin-St Jeor equation
        let baseBMR = (10 * weight) + (6.25 * height) - (5 * Double(age))

        switch sex {
        case .male:
            return Int(baseBMR + 5)
        case .female:
            return Int(baseBMR - 161)
        default:
            // Use average for other/not set
            return Int(baseBMR - 78)
        }
    }

    /// Estimated daily calorie needs at sedentary activity level
    var estimatedDailyCalories: Int? {
        guard let bmr = estimatedBMR else { return nil }
        // Sedentary multiplier (little/no exercise)
        return Int(Double(bmr) * 1.2)
    }

    // MARK: - HealthKit Availability

    /// Check if HealthKit is available on this device
    static var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    // MARK: - Authorization

    /// Request authorization to read and write health data
    func requestAuthorization() async {
        guard HealthKitService.isAvailable else {
            errorMessage = "HealthKit is not available on this device"
            return
        }

        // Types to read
        let readTypes: Set<HKObjectType> = [
            HKQuantityType(.bodyMass),
            HKQuantityType(.height),
            HKCharacteristicType(.biologicalSex),
            HKCharacteristicType(.dateOfBirth)
        ]

        // Types to write (nutrition data)
        let writeTypes: Set<HKSampleType> = [
            HKQuantityType(.dietaryEnergyConsumed),
            HKQuantityType(.dietaryProtein),
            HKQuantityType(.dietaryCarbohydrates),
            HKQuantityType(.dietaryFatTotal)
        ]

        do {
            try await healthStore.requestAuthorization(toShare: writeTypes, read: readTypes)
            isAuthorized = true

            // Fetch initial data after authorization
            await fetchAllHealthData()
        } catch {
            errorMessage = "Failed to authorize HealthKit: \(error.localizedDescription)"
            isAuthorized = false
        }
    }

    /// Check current authorization status for a specific type
    func checkAuthorizationStatus() {
        let weightType = HKQuantityType(.bodyMass)
        authorizationStatus = healthStore.authorizationStatus(for: weightType)
    }

    // MARK: - Reading Data

    /// Fetch all available health data
    func fetchAllHealthData() async {
        isLoading = true
        errorMessage = nil

        async let weight: () = fetchLatestWeight()
        async let height: () = fetchLatestHeight()
        async let characteristics: () = fetchCharacteristics()

        _ = await (weight, height, characteristics)

        isLoading = false
    }

    /// Fetch the most recent weight measurement
    func fetchLatestWeight() async {
        let weightType = HKQuantityType(.bodyMass)

        do {
            let sample = try await fetchMostRecentSample(for: weightType)
            if let quantity = sample?.quantity {
                latestWeight = quantity.doubleValue(for: .gramUnit(with: .kilo))
            }
        } catch {
            // Weight might not be available - not an error
        }
    }

    /// Fetch the most recent height measurement
    func fetchLatestHeight() async {
        let heightType = HKQuantityType(.height)

        do {
            let sample = try await fetchMostRecentSample(for: heightType)
            if let quantity = sample?.quantity {
                latestHeight = quantity.doubleValue(for: .meterUnit(with: .centi))
            }
        } catch {
            // Height might not be available - not an error
        }
    }

    /// Fetch biological sex and date of birth
    func fetchCharacteristics() async {
        do {
            biologicalSex = try healthStore.biologicalSex().biologicalSex
        } catch {
            // Biological sex might not be set
        }

        do {
            let dobComponents = try healthStore.dateOfBirthComponents()
            dateOfBirth = Calendar.current.date(from: dobComponents)
        } catch {
            // Date of birth might not be set
        }
    }

    private func fetchMostRecentSample(for type: HKQuantityType) async throws -> HKQuantitySample? {
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        let predicate = HKQuery.predicateForSamples(withStart: nil, end: Date(), options: .strictEndDate)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: 1,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: samples?.first as? HKQuantitySample)
                }
            }

            healthStore.execute(query)
        }
    }

    // MARK: - Writing Data

    /// Log a meal's nutrition data to HealthKit
    /// - Parameters:
    ///   - calories: Calories consumed
    ///   - protein: Protein in grams
    ///   - carbs: Carbohydrates in grams
    ///   - fat: Fat in grams
    ///   - date: When the meal was consumed
    ///   - mealName: Optional name for metadata
    func logMealToHealthKit(
        calories: Int?,
        protein: Int?,
        carbs: Int?,
        fat: Int?,
        date: Date = Date(),
        mealName: String? = nil
    ) async throws {
        var samplesToSave: [HKQuantitySample] = []

        let metadata: [String: Any] = mealName.map { ["HKFoodMeal": $0] } ?? [:]

        // Calories
        if let cal = calories, cal > 0 {
            let calorieType = HKQuantityType(.dietaryEnergyConsumed)
            let calorieQuantity = HKQuantity(unit: .kilocalorie(), doubleValue: Double(cal))
            let sample = HKQuantitySample(
                type: calorieType,
                quantity: calorieQuantity,
                start: date,
                end: date,
                metadata: metadata
            )
            samplesToSave.append(sample)
        }

        // Protein
        if let prot = protein, prot > 0 {
            let proteinType = HKQuantityType(.dietaryProtein)
            let proteinQuantity = HKQuantity(unit: .gram(), doubleValue: Double(prot))
            let sample = HKQuantitySample(
                type: proteinType,
                quantity: proteinQuantity,
                start: date,
                end: date,
                metadata: metadata
            )
            samplesToSave.append(sample)
        }

        // Carbs
        if let carb = carbs, carb > 0 {
            let carbsType = HKQuantityType(.dietaryCarbohydrates)
            let carbsQuantity = HKQuantity(unit: .gram(), doubleValue: Double(carb))
            let sample = HKQuantitySample(
                type: carbsType,
                quantity: carbsQuantity,
                start: date,
                end: date,
                metadata: metadata
            )
            samplesToSave.append(sample)
        }

        // Fat
        if let f = fat, f > 0 {
            let fatType = HKQuantityType(.dietaryFatTotal)
            let fatQuantity = HKQuantity(unit: .gram(), doubleValue: Double(f))
            let sample = HKQuantitySample(
                type: fatType,
                quantity: fatQuantity,
                start: date,
                end: date,
                metadata: metadata
            )
            samplesToSave.append(sample)
        }

        guard !samplesToSave.isEmpty else { return }

        try await healthStore.save(samplesToSave)
    }

    // MARK: - Initialization

    private init() {
        checkAuthorizationStatus()
    }
}

// MARK: - Environment Key

struct HealthKitServiceKey: EnvironmentKey {
    static let defaultValue: HealthKitService? = nil
}

extension EnvironmentValues {
    var healthKitService: HealthKitService? {
        get { self[HealthKitServiceKey.self] }
        set { self[HealthKitServiceKey.self] = newValue }
    }
}
