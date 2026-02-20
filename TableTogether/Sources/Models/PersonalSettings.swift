import Foundation
import CloudKit

/// Personal settings stored in CloudKit private database.
/// This data is never shared with other household members.
///
/// Includes:
/// - Nutrition goals/targets
/// - Display preferences for personal insights
///
/// Note: This is NOT a SwiftData model - it's stored directly in CloudKit
/// private database to ensure strict privacy separation from shared household data.
struct PersonalSettings: Identifiable, Codable {
    /// Record identifier (matches CloudKit record ID)
    var id: String

    /// Optional personal daily calorie goal
    var dailyCalorieTarget: Int?

    /// Optional personal daily protein goal in grams
    var dailyProteinTarget: Int?

    /// Optional personal daily carbohydrate goal in grams
    var dailyCarbTarget: Int?

    /// Optional personal daily fat goal in grams
    var dailyFatTarget: Int?

    /// Personal preference for showing macro insights
    var showMacroInsights: Bool

    // MARK: - Manual Health Data (Private)

    /// Manual weight in kilograms (always stored in metric internally)
    var manualWeightKg: Double?

    /// Manual height in centimetres (always stored in metric internally)
    var manualHeightCm: Double?

    /// Manual age in years
    var manualAge: Int?

    /// Manual biological sex: "male", "female", or "other"
    var manualBiologicalSex: String?

    /// Last modified timestamp
    var modifiedAt: Date

    // MARK: - Initialization

    init(
        id: String = "personal_settings",
        dailyCalorieTarget: Int? = nil,
        dailyProteinTarget: Int? = nil,
        dailyCarbTarget: Int? = nil,
        dailyFatTarget: Int? = nil,
        showMacroInsights: Bool = true,
        manualWeightKg: Double? = nil,
        manualHeightCm: Double? = nil,
        manualAge: Int? = nil,
        manualBiologicalSex: String? = nil
    ) {
        self.id = id
        self.dailyCalorieTarget = dailyCalorieTarget
        self.dailyProteinTarget = dailyProteinTarget
        self.dailyCarbTarget = dailyCarbTarget
        self.dailyFatTarget = dailyFatTarget
        self.showMacroInsights = showMacroInsights
        self.manualWeightKg = manualWeightKg
        self.manualHeightCm = manualHeightCm
        self.manualAge = manualAge
        self.manualBiologicalSex = manualBiologicalSex
        self.modifiedAt = Date()
    }

    // MARK: - Computed Properties

    /// Whether the user has any macro goals set
    var hasGoalsSet: Bool {
        dailyCalorieTarget != nil ||
        dailyProteinTarget != nil ||
        dailyCarbTarget != nil ||
        dailyFatTarget != nil
    }

    // MARK: - CloudKit Record Conversion

    /// CloudKit record type identifier
    static let recordType = "PersonalSettings"

    /// Creates a PersonalSettings from a CloudKit record
    init?(from record: CKRecord) {
        guard record.recordType == Self.recordType else { return nil }

        self.id = record.recordID.recordName
        self.dailyCalorieTarget = record["dailyCalorieTarget"] as? Int
        self.dailyProteinTarget = record["dailyProteinTarget"] as? Int
        self.dailyCarbTarget = record["dailyCarbTarget"] as? Int
        self.dailyFatTarget = record["dailyFatTarget"] as? Int
        self.showMacroInsights = (record["showMacroInsights"] as? Int ?? 1) == 1
        self.manualWeightKg = record["manualWeightKg"] as? Double
        self.manualHeightCm = record["manualHeightCm"] as? Double
        self.manualAge = record["manualAge"] as? Int
        self.manualBiologicalSex = record["manualBiologicalSex"] as? String
        self.modifiedAt = record.modificationDate ?? Date()
    }

    /// Converts to a CloudKit record for saving
    func toRecord(existingRecord: CKRecord? = nil) -> CKRecord {
        let recordID = CKRecord.ID(recordName: id)
        let record = existingRecord ?? CKRecord(recordType: Self.recordType, recordID: recordID)

        // Set values, using NSNull for nil to clear existing values
        if let calories = dailyCalorieTarget {
            record["dailyCalorieTarget"] = calories as CKRecordValue
        } else {
            record["dailyCalorieTarget"] = nil
        }

        if let protein = dailyProteinTarget {
            record["dailyProteinTarget"] = protein as CKRecordValue
        } else {
            record["dailyProteinTarget"] = nil
        }

        if let carbs = dailyCarbTarget {
            record["dailyCarbTarget"] = carbs as CKRecordValue
        } else {
            record["dailyCarbTarget"] = nil
        }

        if let fat = dailyFatTarget {
            record["dailyFatTarget"] = fat as CKRecordValue
        } else {
            record["dailyFatTarget"] = nil
        }

        record["showMacroInsights"] = (showMacroInsights ? 1 : 0) as CKRecordValue

        if let weight = manualWeightKg {
            record["manualWeightKg"] = weight as CKRecordValue
        } else {
            record["manualWeightKg"] = nil
        }

        if let height = manualHeightCm {
            record["manualHeightCm"] = height as CKRecordValue
        } else {
            record["manualHeightCm"] = nil
        }

        if let age = manualAge {
            record["manualAge"] = age as CKRecordValue
        } else {
            record["manualAge"] = nil
        }

        if let sex = manualBiologicalSex {
            record["manualBiologicalSex"] = sex as CKRecordValue
        } else {
            record["manualBiologicalSex"] = nil
        }

        return record
    }

    // MARK: - Methods

    /// Returns a copy with updated goals
    func withUpdatedGoals(
        calories: Int?? = nil,
        protein: Int?? = nil,
        carbs: Int?? = nil,
        fat: Int?? = nil
    ) -> PersonalSettings {
        var copy = self
        if case .some(let value) = calories { copy.dailyCalorieTarget = value }
        if case .some(let value) = protein { copy.dailyProteinTarget = value }
        if case .some(let value) = carbs { copy.dailyCarbTarget = value }
        if case .some(let value) = fat { copy.dailyFatTarget = value }
        copy.modifiedAt = Date()
        return copy
    }

    /// Returns a copy with all goals cleared
    func withClearedGoals() -> PersonalSettings {
        var copy = self
        copy.dailyCalorieTarget = nil
        copy.dailyProteinTarget = nil
        copy.dailyCarbTarget = nil
        copy.dailyFatTarget = nil
        copy.modifiedAt = Date()
        return copy
    }

    // MARK: - Local Cache

    /// UserDefaults key for local cache
    private static let cacheKey = "PersonalSettingsCache"

    /// Saves to local cache for offline access
    func saveToLocalCache() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.cacheKey)
        }
    }

    /// Loads from local cache
    static func loadFromLocalCache() -> PersonalSettings? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let settings = try? JSONDecoder().decode(PersonalSettings.self, from: data) else {
            return nil
        }
        return settings
    }

    /// Clears local cache
    static func clearLocalCache() {
        UserDefaults.standard.removeObject(forKey: cacheKey)
    }
}
