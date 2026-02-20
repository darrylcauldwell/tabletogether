import Foundation
import CloudKit

// MARK: - MealLogStatus

/// Status of a meal log entry for plan-to-log auto-population
enum MealLogStatus: String, Codable {
    case planned    // Auto-populated from meal plan, not yet confirmed
    case consumed   // User confirmed they ate this
    case skipped    // User marked they didn't eat this
}

/// Record of an actually eaten meal.
/// Stored in CloudKit private database - never shared with other household members.
///
/// References shared data by ID only:
/// - recipeID: References a Recipe in the shared database
/// - mealSlotID: References a MealSlot in the shared database
///
/// Note: This is NOT a SwiftData model - it's stored directly in CloudKit
/// private database to ensure strict privacy separation.
struct PrivateMealLog: Identifiable, Codable {
    /// Primary identifier
    var id: UUID

    /// When the meal was eaten
    var date: Date

    /// Type of meal (stored as raw value)
    var mealTypeRaw: String

    /// Portion eaten (e.g., 1.0, 1.5, 0.5 servings)
    var servingsConsumed: Double

    /// Reference to recipe in shared database (optional)
    var recipeID: UUID?

    /// Reference to meal slot in shared database (optional)
    var mealSlotID: UUID?

    /// Name for unplanned meals (quick log)
    var quickLogName: String?

    /// Manual calorie entry for quick logs
    var quickLogCalories: Int?

    /// Manual protein entry for quick logs (grams)
    var quickLogProtein: Int?

    /// Manual carb entry for quick logs (grams)
    var quickLogCarbs: Int?

    /// Manual fat entry for quick logs (grams)
    var quickLogFat: Int?

    /// Optional notes about the meal
    var notes: String?

    /// Status of this log entry (planned, consumed, or skipped)
    var status: MealLogStatus

    /// Creation timestamp
    var createdAt: Date

    // MARK: - Computed Properties

    /// MealType enum value
    var mealType: MealType {
        get { MealType(rawValue: mealTypeRaw) ?? .dinner }
        set { mealTypeRaw = newValue.rawValue }
    }

    /// Whether this is a quick log (manual entry) vs. recipe-based
    var isQuickLog: Bool {
        quickLogName != nil
    }

    /// Display name for the meal (used when recipe isn't fetched)
    var displayName: String {
        if let name = quickLogName, !name.isEmpty {
            return name
        }
        return "Logged Meal"
    }

    /// Formatted date display
    var dateDisplay: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    /// Short date display (just the date, no time)
    var shortDateDisplay: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    // MARK: - Initialization

    /// Creates a meal log from a recipe
    init(
        id: UUID = UUID(),
        date: Date = Date(),
        mealType: MealType,
        recipeID: UUID? = nil,
        mealSlotID: UUID? = nil,
        servingsConsumed: Double = 1.0,
        notes: String? = nil,
        status: MealLogStatus = .consumed
    ) {
        self.id = id
        self.date = date
        self.mealTypeRaw = mealType.rawValue
        self.servingsConsumed = servingsConsumed
        self.recipeID = recipeID
        self.mealSlotID = mealSlotID
        self.quickLogName = nil
        self.quickLogCalories = nil
        self.quickLogProtein = nil
        self.quickLogCarbs = nil
        self.quickLogFat = nil
        self.notes = notes
        self.status = status
        self.createdAt = Date()
    }

    /// Creates a quick log meal entry with manual macro values
    init(
        id: UUID = UUID(),
        date: Date = Date(),
        mealType: MealType,
        quickLogName: String,
        calories: Int? = nil,
        protein: Int? = nil,
        carbs: Int? = nil,
        fat: Int? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.date = date
        self.mealTypeRaw = mealType.rawValue
        self.servingsConsumed = 1.0
        self.recipeID = nil
        self.mealSlotID = nil
        self.quickLogName = quickLogName
        self.quickLogCalories = calories
        self.quickLogProtein = protein
        self.quickLogCarbs = carbs
        self.quickLogFat = fat
        self.notes = notes
        self.status = .consumed
        self.createdAt = Date()
    }

    // MARK: - Calorie/Macro Calculation

    /// Returns calculated macros when provided with recipe data
    /// Quick log values take priority over calculated values
    func calculatedCalories(recipeCaloriesPerServing: Double?) -> Int? {
        if let quickCal = quickLogCalories {
            return quickCal
        }
        if let perServing = recipeCaloriesPerServing {
            return Int(perServing * servingsConsumed)
        }
        return nil
    }

    func calculatedProtein(recipeProteinPerServing: Double?) -> Int? {
        if let quickProt = quickLogProtein {
            return quickProt
        }
        if let perServing = recipeProteinPerServing {
            return Int(perServing * servingsConsumed)
        }
        return nil
    }

    func calculatedCarbs(recipeCarbsPerServing: Double?) -> Int? {
        if let quickCarbs = quickLogCarbs {
            return quickCarbs
        }
        if let perServing = recipeCarbsPerServing {
            return Int(perServing * servingsConsumed)
        }
        return nil
    }

    func calculatedFat(recipeFatPerServing: Double?) -> Int? {
        if let quickFat = quickLogFat {
            return quickFat
        }
        if let perServing = recipeFatPerServing {
            return Int(perServing * servingsConsumed)
        }
        return nil
    }

    /// Whether this log has any macro data (for quick logs)
    var hasQuickLogMacroData: Bool {
        quickLogCalories != nil ||
        quickLogProtein != nil ||
        quickLogCarbs != nil ||
        quickLogFat != nil
    }

    // MARK: - CloudKit Record Conversion

    /// CloudKit record type identifier
    static let recordType = "MealLog"

    /// Creates a PrivateMealLog from a CloudKit record
    init?(from record: CKRecord) {
        guard record.recordType == Self.recordType else { return nil }

        guard let idString = record["id"] as? String,
              let id = UUID(uuidString: idString),
              let date = record["date"] as? Date,
              let mealTypeRaw = record["mealType"] as? String else {
            return nil
        }

        self.id = id
        self.date = date
        self.mealTypeRaw = mealTypeRaw
        self.servingsConsumed = record["servingsConsumed"] as? Double ?? 1.0

        if let recipeIDString = record["recipeID"] as? String {
            self.recipeID = UUID(uuidString: recipeIDString)
        } else {
            self.recipeID = nil
        }

        if let slotIDString = record["mealSlotID"] as? String {
            self.mealSlotID = UUID(uuidString: slotIDString)
        } else {
            self.mealSlotID = nil
        }

        self.quickLogName = record["quickLogName"] as? String
        self.quickLogCalories = record["quickLogCalories"] as? Int
        self.quickLogProtein = record["quickLogProtein"] as? Int
        self.quickLogCarbs = record["quickLogCarbs"] as? Int
        self.quickLogFat = record["quickLogFat"] as? Int
        self.notes = record["notes"] as? String

        if let statusRaw = record["status"] as? String,
           let parsedStatus = MealLogStatus(rawValue: statusRaw) {
            self.status = parsedStatus
        } else {
            self.status = .consumed // Default for backward compat with existing records
        }

        self.createdAt = record["createdAt"] as? Date ?? record.creationDate ?? Date()
    }

    /// Converts to a CloudKit record for saving
    func toRecord(existingRecord: CKRecord? = nil) -> CKRecord {
        let recordID = CKRecord.ID(recordName: id.uuidString)
        let record = existingRecord ?? CKRecord(recordType: Self.recordType, recordID: recordID)

        record["id"] = id.uuidString as CKRecordValue
        record["date"] = date as CKRecordValue
        record["mealType"] = mealTypeRaw as CKRecordValue
        record["servingsConsumed"] = servingsConsumed as CKRecordValue
        record["status"] = status.rawValue as CKRecordValue
        record["createdAt"] = createdAt as CKRecordValue

        // Optional references
        if let recipeID = recipeID {
            record["recipeID"] = recipeID.uuidString as CKRecordValue
        } else {
            record["recipeID"] = nil
        }

        if let mealSlotID = mealSlotID {
            record["mealSlotID"] = mealSlotID.uuidString as CKRecordValue
        } else {
            record["mealSlotID"] = nil
        }

        // Quick log fields
        if let name = quickLogName {
            record["quickLogName"] = name as CKRecordValue
        } else {
            record["quickLogName"] = nil
        }

        if let cal = quickLogCalories {
            record["quickLogCalories"] = cal as CKRecordValue
        } else {
            record["quickLogCalories"] = nil
        }

        if let prot = quickLogProtein {
            record["quickLogProtein"] = prot as CKRecordValue
        } else {
            record["quickLogProtein"] = nil
        }

        if let carbs = quickLogCarbs {
            record["quickLogCarbs"] = carbs as CKRecordValue
        } else {
            record["quickLogCarbs"] = nil
        }

        if let fat = quickLogFat {
            record["quickLogFat"] = fat as CKRecordValue
        } else {
            record["quickLogFat"] = nil
        }

        if let notes = notes {
            record["notes"] = notes as CKRecordValue
        } else {
            record["notes"] = nil
        }

        return record
    }
}
