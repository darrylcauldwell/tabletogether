import Testing
@testable import TableTogetherLib

@Suite("IngredientParser Tests")
struct IngredientParserTests {

    // MARK: - parseFraction

    @Test("Whole number parses correctly")
    func wholeNumber() {
        #expect(IngredientParser.parseFraction("3") == 3)
    }

    @Test("Decimal number parses correctly")
    func decimalNumber() {
        #expect(IngredientParser.parseFraction("2.5") == 2.5)
    }

    @Test("Simple fraction parses correctly")
    func simpleFraction() {
        #expect(IngredientParser.parseFraction("1/2") == 0.5)
    }

    @Test("Mixed number parses correctly")
    func mixedNumber() {
        #expect(IngredientParser.parseFraction("1 1/2") == 1.5)
    }

    @Test("Empty string returns 1 as fallback")
    func emptyString() {
        #expect(IngredientParser.parseFraction("") == 1)
    }

    @Test("Invalid input returns 1 as fallback")
    func invalidInput() {
        #expect(IngredientParser.parseFraction("xyz") == 1)
    }

    @Test("Division by zero returns 1 as fallback")
    func divisionByZero() {
        #expect(IngredientParser.parseFraction("1/0") == 1)
    }

    // MARK: - parse

    @Test("Parses cups with name")
    func parsesCupsWithName() {
        let result = IngredientParser.parse("2 cups flour")
        #expect(result.quantity == 2)
        #expect(result.unit == .cup)
        #expect(result.name == "flour")
    }

    @Test("Parses tablespoons abbreviated")
    func parsesTablespoonsAbbreviated() {
        let result = IngredientParser.parse("3 tbsp olive oil")
        #expect(result.quantity == 3)
        #expect(result.unit == .tablespoon)
        #expect(result.name == "olive oil")
    }

    @Test("Parses fractional teaspoons")
    func parsesFractionalTeaspoons() {
        let result = IngredientParser.parse("1/2 tsp salt")
        #expect(result.quantity == 0.5)
        #expect(result.unit == .teaspoon)
        #expect(result.name == "salt")
    }

    @Test("Parses grams")
    func parsesGrams() {
        let result = IngredientParser.parse("250 g butter")
        #expect(result.quantity == 250)
        #expect(result.unit == .gram)
        #expect(result.name == "butter")
    }

    @Test("Parses preparation note after comma")
    func parsesPreparationNote() {
        let result = IngredientParser.parse("2 cups onions, finely diced")
        #expect(result.quantity == 2)
        #expect(result.unit == .cup)
        #expect(result.name == "onions")
        #expect(result.preparationNote == "finely diced")
    }

    @Test("Falls back to piece when no unit detected")
    func fallsBackToPiece() {
        let result = IngredientParser.parse("2 eggs")
        #expect(result.quantity == 2)
        #expect(result.unit == .piece)
        #expect(result.name == "eggs")
    }

    @Test("Bare ingredient name with no quantity")
    func bareIngredientName() {
        let result = IngredientParser.parse("salt to taste")
        #expect(result.name == "salt to taste")
        #expect(result.quantity == 1)
        #expect(result.unit == .piece)
    }

    @Test("Trims whitespace")
    func trimsWhitespace() {
        let result = IngredientParser.parse("   2 cups flour   ")
        #expect(result.name == "flour")
        #expect(result.quantity == 2)
    }
}
