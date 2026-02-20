import Foundation

// MARK: - MacroSummary

/// A summary of macro nutrient values for a recipe, meal, or daily total.
/// All values are optional to support recipes with incomplete nutritional data.
struct MacroSummary: Codable, Hashable, Equatable {

    // MARK: - Properties

    /// Total calories (kcal).
    var calories: Double?

    /// Protein content in grams.
    var protein: Double?

    /// Carbohydrate content in grams.
    var carbs: Double?

    /// Fat content in grams.
    var fat: Double?

    // MARK: - Initialization

    /// Creates a new macro summary with the specified values.
    /// - Parameters:
    ///   - calories: Total calories in kcal.
    ///   - protein: Protein in grams.
    ///   - carbs: Carbohydrates in grams.
    ///   - fat: Fat in grams.
    init(calories: Double? = nil, protein: Double? = nil, carbs: Double? = nil, fat: Double? = nil) {
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
    }

    // MARK: - Computed Properties

    /// Whether all macro values are nil.
    var isEmpty: Bool {
        calories == nil && protein == nil && carbs == nil && fat == nil
    }

    /// Whether at least one macro value is available.
    var hasData: Bool {
        !isEmpty
    }

    /// Whether all macro values are available.
    var isComplete: Bool {
        calories != nil && protein != nil && carbs != nil && fat != nil
    }

    // MARK: - Formatted Display Strings

    /// Formatted calorie string (e.g., "450 cal" or "--").
    var formattedCalories: String {
        guard let calories = calories else { return "--" }
        return "\(Int(calories.rounded())) cal"
    }

    /// Formatted protein string (e.g., "32g" or "--").
    var formattedProtein: String {
        guard let protein = protein else { return "--" }
        return "\(Int(protein.rounded()))g"
    }

    /// Formatted carbs string (e.g., "45g" or "--").
    var formattedCarbs: String {
        guard let carbs = carbs else { return "--" }
        return "\(Int(carbs.rounded()))g"
    }

    /// Formatted fat string (e.g., "18g" or "--").
    var formattedFat: String {
        guard let fat = fat else { return "--" }
        return "\(Int(fat.rounded()))g"
    }

    /// Compact summary string (e.g., "450 cal | P: 32g | C: 45g | F: 18g").
    var compactSummary: String {
        var components: [String] = []

        if let calories = calories {
            components.append("\(Int(calories.rounded())) cal")
        }
        if let protein = protein {
            components.append("P: \(Int(protein.rounded()))g")
        }
        if let carbs = carbs {
            components.append("C: \(Int(carbs.rounded()))g")
        }
        if let fat = fat {
            components.append("F: \(Int(fat.rounded()))g")
        }

        return components.isEmpty ? "No nutrition data" : components.joined(separator: " | ")
    }

    /// Short summary for space-constrained UI (e.g., "450 cal").
    var shortSummary: String {
        formattedCalories
    }

    // MARK: - Arithmetic Operations

    /// Creates a new MacroSummary scaled by the given factor.
    /// Useful for adjusting servings.
    /// - Parameter factor: The scaling factor to apply.
    /// - Returns: A new MacroSummary with scaled values.
    func scaled(by factor: Double) -> MacroSummary {
        MacroSummary(
            calories: calories.map { $0 * factor },
            protein: protein.map { $0 * factor },
            carbs: carbs.map { $0 * factor },
            fat: fat.map { $0 * factor }
        )
    }

    /// Creates a new MacroSummary divided by the given divisor.
    /// Useful for calculating per-serving values.
    /// - Parameter divisor: The divisor to apply.
    /// - Returns: A new MacroSummary with divided values, or the same values if divisor is zero.
    func divided(by divisor: Double) -> MacroSummary {
        guard divisor != 0 else { return self }
        return scaled(by: 1.0 / divisor)
    }

    /// Returns a new MacroSummary with values added from another summary.
    /// Nil values are treated as zero when the other value exists.
    /// - Parameter other: The MacroSummary to add.
    /// - Returns: A new MacroSummary with combined values.
    func adding(_ other: MacroSummary) -> MacroSummary {
        MacroSummary(
            calories: Self.addOptional(calories, other.calories),
            protein: Self.addOptional(protein, other.protein),
            carbs: Self.addOptional(carbs, other.carbs),
            fat: Self.addOptional(fat, other.fat)
        )
    }

    // MARK: - Static Helpers

    /// Adds two optional doubles, returning nil only if both are nil.
    private static func addOptional(_ a: Double?, _ b: Double?) -> Double? {
        switch (a, b) {
        case (.none, .none): return nil
        case (.some(let val), .none): return val
        case (.none, .some(let val)): return val
        case (.some(let valA), .some(let valB)): return valA + valB
        }
    }

    /// A zero-value MacroSummary for use as an initial accumulator.
    static let zero = MacroSummary(calories: 0, protein: 0, carbs: 0, fat: 0)

    /// An empty MacroSummary with all nil values.
    static let empty = MacroSummary()
}

// MARK: - Operator Overloads

extension MacroSummary {

    /// Adds two MacroSummary values together.
    static func + (lhs: MacroSummary, rhs: MacroSummary) -> MacroSummary {
        lhs.adding(rhs)
    }

    /// Scales a MacroSummary by a factor.
    static func * (lhs: MacroSummary, rhs: Double) -> MacroSummary {
        lhs.scaled(by: rhs)
    }

    /// Scales a MacroSummary by a factor.
    static func * (lhs: Double, rhs: MacroSummary) -> MacroSummary {
        rhs.scaled(by: lhs)
    }

    /// Divides a MacroSummary by a divisor.
    static func / (lhs: MacroSummary, rhs: Double) -> MacroSummary {
        lhs.divided(by: rhs)
    }
}

// MARK: - CustomStringConvertible

extension MacroSummary: CustomStringConvertible {
    var description: String {
        compactSummary
    }
}
