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
/// - Active + resting energy burned today (surfaced next to energy eaten)
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
@Observable
final class HealthKitService {
    static let shared = HealthKitService()

    private let healthStore = HKHealthStore()

    // MARK: - Observable Properties

    private(set) var isAuthorized = false
    private(set) var authorizationStatus: HKAuthorizationStatus = .notDetermined

    private(set) var latestWeight: Double? // in kg
    private(set) var latestHeight: Double? // in cm
    private(set) var biologicalSex: HKBiologicalSex?
    private(set) var dateOfBirth: Date?

    /// Today's energy burned, read from HealthKit (active + resting), in kcal.
    /// Used for a neutral energy-balance readout on the personal Nutrition
    /// surface — informational, never a target/pass-fail (product spec).
    private(set) var todayActiveEnergy: Double?
    private(set) var todayRestingEnergy: Double?

    /// Total energy burned today (active + resting), when either is available.
    var todayEnergyBurned: Double? {
        guard todayActiveEnergy != nil || todayRestingEnergy != nil else { return nil }
        return (todayActiveEnergy ?? 0) + (todayRestingEnergy ?? 0)
    }

    private(set) var isLoading = false
    private(set) var errorMessage: String?

    // MARK: - Manual Fallback Properties

    /// Manual values loaded from PersonalSettings when HealthKit data is unavailable
    var manualWeightKg: Double?
    var manualHeightCm: Double?
    var manualAge: Int?
    var manualBiologicalSex: String?

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
            HKCharacteristicType(.dateOfBirth),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.basalEnergyBurned)
        ]

        do {
            try await healthStore.requestAuthorization(toShare: Self.nutritionWriteTypes, read: readTypes)
            // requestAuthorization does NOT throw when the user denies access, so
            // "the call returned" is not the same as "we're authorized". Derive the
            // flag from the actual write status, which gates HealthKit writes.
            isAuthorized = hasWriteAuthorization

            // Fetch initial data after authorization
            await fetchAllHealthData()
        } catch {
            errorMessage = "Failed to authorize HealthKit: \(error.localizedDescription)"
            isAuthorized = false
        }
    }

    /// Nutrition sample types the app writes to HealthKit.
    private static let nutritionWriteTypes: Set<HKSampleType> = [
        HKQuantityType(.dietaryEnergyConsumed),
        HKQuantityType(.dietaryProtein),
        HKQuantityType(.dietaryCarbohydrates),
        HKQuantityType(.dietaryFatTotal)
    ]

    /// Whether every nutrition write type is actually granted. Unlike the request
    /// completing, this reflects real permission and is queryable on launch without
    /// re-prompting.
    private var hasWriteAuthorization: Bool {
        Self.nutritionWriteTypes.allSatisfy {
            healthStore.authorizationStatus(for: $0) == .sharingAuthorized
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
        async let energy: () = fetchTodayEnergyBurned()

        _ = await (weight, height, characteristics, energy)

        isLoading = false
    }

    /// Sums today's active and resting energy burned, in kcal. Surfaced as-is
    /// on the Nutrition tab next to energy eaten — no target, no net balance,
    /// no judgement (product spec: informational, not evaluative).
    func fetchTodayEnergyBurned() async {
        async let active = sumEnergyToday(for: HKQuantityType(.activeEnergyBurned))
        async let resting = sumEnergyToday(for: HKQuantityType(.basalEnergyBurned))
        todayActiveEnergy = await active
        todayRestingEnergy = await resting
    }

    /// Cumulative kcal for a quantity type over today, or nil if unavailable.
    private func sumEnergyToday(for type: HKQuantityType) async -> Double? {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: Date(), options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, _ in
                let kcal = statistics?.sumQuantity()?.doubleValue(for: .kilocalorie())
                continuation.resume(returning: kcal)
            }
            healthStore.execute(query)
        }
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
            // Weight may simply not be recorded; log so a genuine query failure is visible.
            AppLogger.app.debug("fetchLatestWeight failed: \(error.localizedDescription)")
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
            // Height may simply not be recorded; log so a genuine query failure is visible.
            AppLogger.app.debug("fetchLatestHeight failed: \(error.localizedDescription)")
        }
    }

    /// Fetch biological sex and date of birth
    func fetchCharacteristics() async {
        do {
            biologicalSex = try healthStore.biologicalSex().biologicalSex
        } catch {
            // Biological sex may simply not be set; log so a genuine failure is visible.
            AppLogger.app.debug("fetchCharacteristics biologicalSex failed: \(error.localizedDescription)")
        }

        do {
            let dobComponents = try healthStore.dateOfBirthComponents()
            dateOfBirth = Calendar.current.date(from: dobComponents)
        } catch {
            // Date of birth may simply not be set; log so a genuine failure is visible.
            AppLogger.app.debug("fetchCharacteristics dateOfBirth failed: \(error.localizedDescription)")
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
        // Restore the connected state without re-prompting: write authorization is
        // queryable on launch, so a previously-connected user isn't shown the
        // "Connect to Apple Health" prompt again and their metric/estimate cards reappear.
        if hasWriteAuthorization {
            isAuthorized = true
            Task { await fetchAllHealthData() }
        }
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
