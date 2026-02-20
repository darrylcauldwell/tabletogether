import Foundation

/// Centralized unit-to-gram conversion for food ingredients.
/// Handles standard units, food-specific densities, and FoodItem portion data.
enum GramConversionService {

    // MARK: - Public API

    /// Converts a quantity and unit to grams, optionally using food-specific data.
    /// Returns nil for unconvertible units (bunch, pinch, toTaste).
    static func convertToGrams(
        quantity: Double?,
        unit: MeasurementUnit?,
        foodName: String? = nil,
        foodItem: FoodItem? = nil
    ) -> Double? {
        let qty = quantity ?? 1.0

        guard let unit = unit else {
            // No unit specified — try piece weight, then common portion, then nil
            if let name = foodName, let weight = pieceWeight(for: name) {
                return qty * weight
            }
            if let portion = foodItem?.commonPortions.first {
                return qty * portion.gramWeight
            }
            return nil
        }

        switch unit {
        case .gram:
            return qty

        case .kilogram:
            return qty * 1000.0

        case .milliliter:
            return qty // approximate: 1ml ≈ 1g for most foods

        case .liter:
            return qty * 1000.0

        case .cup:
            if let name = foodName, let density = cupDensity(for: name) {
                return qty * density
            }
            return qty * 240.0 // default cup weight

        case .tablespoon:
            return qty * 15.0

        case .teaspoon:
            return qty * 5.0

        case .clove:
            return qty * 5.0

        case .piece:
            if let name = foodName, let weight = pieceWeight(for: name) {
                return qty * weight
            }
            if let portion = foodItem?.commonPortions.first(where: {
                $0.name.lowercased().contains("piece") ||
                $0.name.lowercased().contains("medium") ||
                $0.name.lowercased().contains("whole")
            }) {
                return qty * portion.gramWeight
            }
            return nil

        case .slice:
            if let name = foodName, let weight = sliceWeight(for: name) {
                return qty * weight
            }
            if let portion = foodItem?.commonPortions.first(where: {
                $0.name.lowercased().contains("slice")
            }) {
                return qty * portion.gramWeight
            }
            return nil

        case .bunch, .pinch, .toTaste:
            return nil
        }
    }

    // MARK: - Cup Densities (grams per cup)

    private static let cupDensities: [(keywords: [String], grams: Double)] = [
        (["flour", "all-purpose flour", "plain flour", "self-raising flour"], 120),
        (["sugar", "granulated sugar", "caster sugar"], 200),
        (["brown sugar"], 220),
        (["icing sugar", "powdered sugar", "confectioners sugar"], 120),
        (["rice", "white rice", "basmati"], 185),
        (["oats", "rolled oats", "porridge oats"], 90),
        (["milk", "semi-skimmed", "whole milk"], 245),
        (["butter"], 227),
        (["shredded cheese", "grated cheese", "cheese"], 113),
        (["cream cheese"], 230),
        (["sour cream"], 230),
        (["yogurt", "yoghurt"], 245),
        (["honey"], 340),
        (["oil", "olive oil", "vegetable oil"], 218),
        (["water"], 237),
        (["cocoa powder"], 85),
        (["breadcrumbs"], 120),
        (["peanut butter"], 258),
        (["chopped nuts", "nuts"], 140),
        (["chopped vegetables", "vegetables", "broccoli", "carrots"], 130),
        (["berries", "blueberries", "raspberries", "strawberries"], 150),
    ]

    private static func cupDensity(for foodName: String) -> Double? {
        let name = foodName.lowercased()
        for entry in cupDensities {
            for keyword in entry.keywords {
                if name.contains(keyword) {
                    return entry.grams
                }
            }
        }
        return nil
    }

    // MARK: - Piece Weights (grams per piece)

    private static let pieceWeights: [(keywords: [String], grams: Double)] = [
        (["banana"], 118),
        (["apple"], 182),
        (["orange", "satsuma", "clementine"], 131),
        (["egg"], 50),
        (["chicken breast"], 174),
        (["potato"], 213),
        (["avocado"], 150),
        (["tomato"], 123),
        (["onion"], 110),
        (["pepper", "bell pepper"], 119),
        (["lemon", "lime"], 58),
        (["pear"], 178),
        (["peach", "nectarine"], 150),
        (["carrot"], 61),
        (["cucumber"], 300),
        (["sausage"], 68),
        (["tortilla", "wrap"], 64),
        (["bagel"], 105),
        (["croissant"], 57),
        (["crumpet"], 55),
        (["scone"], 70),
        (["biscuit", "cookie"], 35),
    ]

    private static func pieceWeight(for foodName: String) -> Double? {
        let name = foodName.lowercased()
        for entry in pieceWeights {
            for keyword in entry.keywords {
                if name.contains(keyword) {
                    return entry.grams
                }
            }
        }
        return nil
    }

    // MARK: - Slice Weights (grams per slice)

    private static let sliceWeights: [(keywords: [String], grams: Double)] = [
        (["bread", "toast", "white bread", "brown bread", "wholemeal"], 30),
        (["cheese", "cheddar", "swiss"], 21),
        (["pizza"], 107),
        (["tomato"], 20),
        (["ham", "turkey", "salami"], 28),
        (["cake", "sponge"], 80),
        (["melon", "watermelon"], 150),
        (["cucumber"], 7),
        (["bacon"], 15),
    ]

    private static func sliceWeight(for foodName: String) -> Double? {
        let name = foodName.lowercased()
        for entry in sliceWeights {
            for keyword in entry.keywords {
                if name.contains(keyword) {
                    return entry.grams
                }
            }
        }
        return nil
    }
}
