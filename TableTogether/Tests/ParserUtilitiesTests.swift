import Testing
@testable import TableTogetherLib

struct ParserUtilitiesTests {

    // MARK: - Unicode fractions

    @Test("Bare unicode fraction normalizes to ASCII")
    func unicodeFractionNormalizes() {
        #expect(ParserUtilities.normalizeUnicodeFractions("½ cup sugar") == "1/2 cup sugar")
        #expect(ParserUtilities.normalizeUnicodeFractions("¼ tsp salt") == "1/4 tsp salt")
        #expect(ParserUtilities.normalizeUnicodeFractions("⅓ cup oil") == "1/3 cup oil")
    }

    // MARK: - parseFraction

    @Test("Simple and mixed fractions sum correctly")
    func parseFractionSums() {
        #expect(ParserUtilities.parseFraction("1/2") == 0.5)
        #expect(ParserUtilities.parseFraction("1 1/2") == 1.5)
        #expect(ParserUtilities.parseFraction("3") == 3)
        #expect(ParserUtilities.parseFraction("") == 1) // assume-one default
        #expect(ParserUtilities.parseFraction("1/0") == 1) // divide-by-zero guard
    }

    // MARK: - Single-letter T/t (the 3x bug)

    @Test("Lowercase t is teaspoon, not tablespoon")
    func lowercaseTIsTeaspoon() {
        let result = ParserUtilities.parseLeadingQuantityAndUnit("1 t salt")
        #expect(result.unit == .teaspoon)
        #expect(result.quantity == 1)
        #expect(result.remainder == "salt")
    }

    @Test("Uppercase T is tablespoon")
    func uppercaseTIsTablespoon() {
        let result = ParserUtilities.parseLeadingQuantityAndUnit("1 T sugar")
        #expect(result.unit == .tablespoon)
        #expect(result.remainder == "sugar")
    }

    @Test("Spelled-out and multi-letter abbreviations resolve correctly")
    func spelledOutUnits() {
        #expect(ParserUtilities.parseLeadingQuantityAndUnit("3 tbsp olive oil").unit == .tablespoon)
        #expect(ParserUtilities.parseLeadingQuantityAndUnit("1/2 tsp salt").unit == .teaspoon)
        #expect(ParserUtilities.parseLeadingQuantityAndUnit("2 tablespoons butter").unit == .tablespoon)
        #expect(ParserUtilities.parseLeadingQuantityAndUnit("1 teaspoon vanilla").unit == .teaspoon)
    }

    // MARK: - Imperial weight conversion

    @Test("Ounces convert quantity to grams")
    func ouncesToGrams() {
        let result = ParserUtilities.parseLeadingQuantityAndUnit("4 oz butter")
        #expect(result.unit == .gram)
        #expect(abs(result.quantity - 4 * ParserUtilities.gramsPerOunce) < 0.0001)
        #expect(result.remainder == "butter")
    }

    @Test("Pounds convert quantity to kilograms")
    func poundsToKilograms() {
        let result = ParserUtilities.parseLeadingQuantityAndUnit("2 pounds chicken")
        #expect(result.unit == .kilogram)
        #expect(abs(result.quantity - 2 * ParserUtilities.kilogramsPerPound) < 0.0001)
    }

    // MARK: - Unicode fraction inside the tokenizer

    @Test("Unicode-fraction quantity is parsed by the tokenizer")
    func unicodeFractionQuantity() {
        let result = ParserUtilities.parseLeadingQuantityAndUnit("½ cup sugar")
        #expect(result.unit == .cup)
        #expect(result.quantity == 0.5)
        #expect(result.remainder == "sugar")
    }

    // MARK: - Other units and the no-unit fallback

    @Test("Cloves, cups and a bare name resolve")
    func variousUnits() {
        #expect(ParserUtilities.parseLeadingQuantityAndUnit("3 cloves garlic").unit == .clove)
        #expect(ParserUtilities.parseLeadingQuantityAndUnit("2 cups flour").quantity == 2)
        let noUnit = ParserUtilities.parseLeadingQuantityAndUnit("salt")
        #expect(noUnit.unit == .piece)
        #expect(noUnit.quantity == 1)
        #expect(noUnit.remainder == "salt")
    }
}
