import Testing
@testable import TableTogetherLib

@Suite("CookbookTextParser Tests")
struct CookbookTextParserTests {

    // Conversion constants mirrored from CookbookTextParser. The imperial weight
    // tokens have no dedicated MeasurementUnit case, so quantities are converted
    // into the metric unit rather than aliasing the token 1:1.
    private let gramsPerOunce = 28.349523
    private let kilogramsPerPound = 0.45359237
    private let tolerance = 0.001

    // MARK: - Metric units

    @Test("Grams parse to .gram with quantity preserved")
    func parsesGrams() {
        let result = CookbookTextParser.parseIngredientLine("200 g flour")
        #expect(result != nil)
        #expect(result?.quantity == 200)
        #expect(result?.unit == .gram)
        #expect(result?.name == "flour")
    }

    @Test("Cups parse to .cup")
    func parsesCups() {
        let result = CookbookTextParser.parseIngredientLine("2 cups rice")
        #expect(result?.quantity == 2)
        #expect(result?.unit == .cup)
        #expect(result?.name == "rice")
    }

    @Test("Kilograms map to .kilogram with quantity preserved (no scaling)")
    func parsesKilograms() {
        let result = CookbookTextParser.parseIngredientLine("1 kg potatoes")
        #expect(result?.quantity == 1)
        #expect(result?.unit == .kilogram)
        #expect(result?.name == "potatoes")
    }

    @Test("Milliliters parse to .milliliter")
    func parsesMilliliters() {
        let result = CookbookTextParser.parseIngredientLine("500 ml stock")
        #expect(result?.quantity == 500)
        #expect(result?.unit == .milliliter)
        #expect(result?.name == "stock")
    }

    @Test("Tablespoons abbreviated parse to .tablespoon")
    func parsesTablespoons() {
        let result = CookbookTextParser.parseIngredientLine("3 tbsp olive oil")
        #expect(result?.quantity == 3)
        #expect(result?.unit == .tablespoon)
        #expect(result?.name == "olive oil")
    }

    // MARK: - Imperial conversion (regression)

    @Test("Ounces convert quantity into grams")
    func ouncesConvertToGrams() {
        let result = CookbookTextParser.parseIngredientLine("4 oz butter")
        #expect(result != nil)
        #expect(result?.unit == .gram)
        let expected = 4 * gramsPerOunce // 113.398092
        #expect(abs((result?.quantity ?? 0) - expected) < tolerance)
        #expect(result?.name == "butter")
    }

    @Test("Pounds convert quantity into kilograms")
    func poundsConvertToKilograms() {
        let result = CookbookTextParser.parseIngredientLine("1 lb beef")
        #expect(result != nil)
        #expect(result?.unit == .kilogram)
        let expected = 1 * kilogramsPerPound // 0.45359237
        #expect(abs((result?.quantity ?? 0) - expected) < tolerance)
        #expect(result?.name == "beef")
    }

    @Test("Plural ounces spelled out also convert")
    func ouncesSpelledOutConvert() {
        let result = CookbookTextParser.parseIngredientLine("8 ounces cheese")
        #expect(result?.unit == .gram)
        let expected = 8 * gramsPerOunce
        #expect(abs((result?.quantity ?? 0) - expected) < tolerance)
    }

    @Test("Pounds spelled out also convert")
    func poundsSpelledOutConvert() {
        let result = CookbookTextParser.parseIngredientLine("2 pounds chicken")
        #expect(result?.unit == .kilogram)
        let expected = 2 * kilogramsPerPound
        #expect(abs((result?.quantity ?? 0) - expected) < tolerance)
    }

    // MARK: - Unicode fractions

    @Test("Unicode half normalizes and parses")
    func unicodeHalfCup() {
        let result = CookbookTextParser.parseIngredientLine("½ cup sugar")
        #expect(result?.quantity == 0.5)
        #expect(result?.unit == .cup)
        #expect(result?.name == "sugar")
    }

    @Test("Mixed number with unicode fraction parses")
    func mixedUnicodeFraction() {
        let result = CookbookTextParser.parseIngredientLine("1 ½ cups milk")
        #expect(result?.quantity == 1.5)
        #expect(result?.unit == .cup)
        #expect(result?.name == "milk")
    }

    @Test("ASCII mixed number parses")
    func asciiMixedNumber() {
        let result = CookbookTextParser.parseIngredientLine("1 1/2 cups water")
        #expect(result?.quantity == 1.5)
        #expect(result?.unit == .cup)
        #expect(result?.name == "water")
    }

    // MARK: - Preparation note & optional

    @Test("Preparation note extracted after comma")
    func preparationNoteAfterComma() {
        let result = CookbookTextParser.parseIngredientLine("2 cloves garlic, minced")
        #expect(result?.unit == .clove)
        #expect(result?.quantity == 2)
        #expect(result?.name == "garlic")
        #expect(result?.preparationNote == "minced")
    }

    @Test("Optional flagged from parenthetical")
    func optionalParenthetical() {
        let result = CookbookTextParser.parseIngredientLine("1 pinch saffron (optional)")
        #expect(result?.isOptional == true)
        #expect(result?.unit == .pinch)
        #expect(result?.name == "saffron")
    }

    @Test("Optional flagged from preparation note")
    func optionalFromNote() {
        let result = CookbookTextParser.parseIngredientLine("2 tbsp cream, optional")
        #expect(result?.isOptional == true)
        #expect(result?.preparationNote == "optional")
    }

    @Test("Non-optional ingredient is not flagged optional")
    func notOptional() {
        let result = CookbookTextParser.parseIngredientLine("200 g flour")
        #expect(result?.isOptional == false)
    }

    // MARK: - Fallback & edge cases

    @Test("Bare number falls back to .piece")
    func bareNumberFallsBackToPiece() {
        let result = CookbookTextParser.parseIngredientLine("3 eggs")
        #expect(result?.quantity == 3)
        #expect(result?.unit == .piece)
        #expect(result?.name == "eggs")
    }

    @Test("Empty line returns nil")
    func emptyLineReturnsNil() {
        #expect(CookbookTextParser.parseIngredientLine("   ") == nil)
    }

    @Test("Original text preserved")
    func originalTextPreserved() {
        let result = CookbookTextParser.parseIngredientLine("4 oz butter")
        #expect(result?.originalText == "4 oz butter")
    }

    // MARK: - Line classification

    @Test("Line starting with quantity is an ingredient line")
    func quantityLineIsIngredient() {
        #expect(CookbookTextParser.isIngredientLine("2 cups flour") == true)
    }

    @Test("Line with a unit keyword is an ingredient line")
    func unitKeywordLineIsIngredient() {
        #expect(CookbookTextParser.isIngredientLine("salt, a pinch to season") == true)
    }

    @Test("Numbered instruction step is not an ingredient line")
    func numberedStepNotIngredient() {
        #expect(CookbookTextParser.isIngredientLine("1. Preheat the oven to 200C") == false)
    }

    @Test("Plain prose without units is not an ingredient line")
    func plainProseNotIngredient() {
        #expect(CookbookTextParser.isIngredientLine("Stir gently until combined") == false)
    }

    // MARK: - Full parse with section headers

    @Test("Full parse splits title, ingredients, and instructions")
    func fullParseWithHeaders() {
        let text = """
        Tomato Soup
        Serves 4
        Ingredients
        200 g tomatoes
        1 kg potatoes
        Method
        1. Chop the tomatoes.
        2. Simmer for 20 minutes.
        """
        let result = CookbookTextParser.parse(text)
        #expect(result.title == "Tomato Soup")
        #expect(result.ingredients.count == 2)
        #expect(result.ingredients.first?.name == "tomatoes")
        #expect(result.ingredients.first?.unit == .gram)
        #expect(result.instructions.count == 2)
        // Leading step numbers are stripped.
        #expect(result.instructions.first == "Chop the tomatoes.")
    }

    @Test("Empty input yields untitled recipe with no content")
    func emptyInput() {
        let result = CookbookTextParser.parse("")
        #expect(result.title == "Untitled Recipe")
        #expect(result.ingredients.isEmpty)
        #expect(result.instructions.isEmpty)
    }
}
