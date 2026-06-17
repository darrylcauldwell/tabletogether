import Testing
import Foundation
@testable import TableTogetherLib

@Suite("GramConversionService Tests")
struct GramConversionServiceTests {

    private func grams(_ quantity: Double?, _ unit: MeasurementUnit?, food: String? = nil) -> Double? {
        GramConversionService.convertToGrams(quantity: quantity, unit: unit, foodName: food, foodItem: nil)
    }

    // MARK: - Direct metric units

    @Test("Grams pass through unchanged")
    func gramsPassthrough() {
        #expect(grams(100, .gram) == 100)
    }

    @Test("Kilograms convert to grams")
    func kilograms() {
        #expect(grams(2, .kilogram) == 2000)
    }

    @Test("Millilitres approximate to grams 1:1")
    func millilitres() {
        #expect(grams(250, .milliliter) == 250)
    }

    @Test("Litres convert to grams")
    func litres() {
        #expect(grams(1.5, .liter) == 1500)
    }

    @Test("Tablespoon, teaspoon and clove use fixed gram weights")
    func spoonsAndClove() {
        #expect(grams(3, .tablespoon) == 45)   // 3 * 15
        #expect(grams(2, .teaspoon) == 10)      // 2 * 5
        #expect(grams(2, .clove) == 10)         // 2 * 5
    }

    // MARK: - Cups (density-aware)

    @Test("Cup with no recognised food uses the default 240g")
    func cupDefault() {
        #expect(grams(1, .cup) == 240)
    }

    @Test("Cup uses food-specific density when the name is recognised")
    func cupDensity() {
        #expect(grams(2, .cup, food: "flour") == 240)   // 2 * 120
        #expect(grams(1, .cup, food: "granulated sugar") == 200)
    }

    // MARK: - Pieces & slices (lookup-dependent)

    @Test("Piece uses per-piece weight when the food is known")
    func pieceWithName() {
        #expect(grams(2, .piece, food: "banana") == 236) // 2 * 118
    }

    @Test("Piece with no name and no food item is unconvertible")
    func pieceWithoutName() {
        #expect(grams(1, .piece) == nil)
    }

    @Test("Slice uses per-slice weight when the food is known")
    func sliceWithName() {
        #expect(grams(2, .slice, food: "bread") == 60) // 2 * 30
    }

    @Test("Slice with no recognised food is unconvertible")
    func sliceWithoutName() {
        #expect(grams(1, .slice) == nil)
    }

    // MARK: - Unconvertible units

    @Test("Bunch, pinch and toTaste are unconvertible")
    func unconvertibleUnits() {
        #expect(grams(1, .bunch) == nil)
        #expect(grams(1, .pinch) == nil)
        #expect(grams(1, .toTaste) == nil)
    }

    // MARK: - Defaults & nil handling

    @Test("Nil quantity defaults to 1")
    func nilQuantityDefaultsToOne() {
        #expect(grams(nil, .gram) == 1)
        #expect(grams(nil, .kilogram) == 1000)
    }

    @Test("Nil unit falls back to piece weight from the food name")
    func nilUnitUsesPieceWeight() {
        #expect(grams(1, nil, food: "egg") == 50)
    }

    @Test("Nil unit with no recognised food is unconvertible")
    func nilUnitUnknownFood() {
        #expect(grams(1, nil, food: "qwerty nonsense") == nil)
        #expect(grams(1, nil) == nil)
    }
}
