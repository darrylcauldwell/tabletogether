import Testing
@testable import TableTogetherLib

/// Tests for ``NaturalLanguageMealParser``'s regex fallback parsing.
///
/// In the test environment no Apple Intelligence model is available, so
/// `parse(description:)` falls through to the deterministic regex path. These
/// tests therefore exercise the regex fallback (`parseWithRegex`).
///
/// The suite is marked `@MainActor` to match the parser's isolation
/// (`@MainActor @Observable final class`).
@MainActor
@Suite("NaturalLanguageMealParser Tests")
struct NaturalLanguageMealParserTests {

    // MARK: - Multi-item splitting

    @Test("Splits multi-item input joined by 'and' into separate ingredients")
    func splitsOnAnd() async {
        let parser = NaturalLanguageMealParser()
        let result = await parser.parse(description: "2 eggs and 200g chicken")

        #expect(result.ingredients.count == 2)

        let eggs = result.ingredients[0]
        #expect(eggs.name == "eggs")
        #expect(eggs.quantity == 2)

        let chicken = result.ingredients[1]
        #expect(chicken.name == "chicken")
        #expect(chicken.quantity == 200)
        #expect(chicken.unit == .gram)
    }

    @Test("Splits on commas, plus signs, and 'with'")
    func splitsOnVariedSeparators() async {
        let parser = NaturalLanguageMealParser()

        let comma = await parser.parse(description: "rice, beans")
        #expect(comma.ingredients.count == 2)

        let plus = await parser.parse(description: "rice + beans")
        #expect(plus.ingredients.count == 2)

        let with = await parser.parse(description: "rice with beans")
        #expect(with.ingredients.count == 2)
    }

    // MARK: - Quantity + unit + name

    @Test("Parses quantity, recognised unit, and name: '2 cups rice'")
    func parsesQuantityUnitName() async {
        let parser = NaturalLanguageMealParser()
        let result = await parser.parse(description: "2 cups rice")

        #expect(result.ingredients.count == 1)
        let item = result.ingredients[0]
        #expect(item.quantity == 2)
        #expect(item.unit == .cup)
        #expect(item.name == "rice")
        #expect(item.confidence == .high)
    }

    @Test("Parses gram unit with multi-word name: '200g chicken breast'")
    func parsesGramsWithMultiWordName() async {
        let parser = NaturalLanguageMealParser()
        let result = await parser.parse(description: "200g chicken breast")

        #expect(result.ingredients.count == 1)
        let item = result.ingredients[0]
        #expect(item.quantity == 200)
        #expect(item.unit == .gram)
        #expect(item.name == "chicken breast")
    }

    @Test("Parses fractional quantity: '1/2 cup milk'")
    func parsesFractionalQuantity() async {
        let parser = NaturalLanguageMealParser()
        let result = await parser.parse(description: "1/2 cup milk")

        #expect(result.ingredients.count == 1)
        let item = result.ingredients[0]
        #expect(item.quantity == 0.5)
        #expect(item.unit == .cup)
        #expect(item.name == "milk")
    }

    // MARK: - Plain food name, no quantity

    @Test("Plain food name with no quantity sets name and leaves quantity nil")
    func plainFoodNameNoQuantity() async {
        let parser = NaturalLanguageMealParser()
        let result = await parser.parse(description: "broccoli")

        #expect(result.ingredients.count == 1)
        let item = result.ingredients[0]
        #expect(item.name == "broccoli")
        #expect(item.quantity == nil)
        #expect(item.unit == nil)
    }

    // MARK: - Unrecognised unit token folds into name

    @Test("Unrecognised unit token becomes part of name: '3 ripe bananas'")
    func unrecognisedUnitFoldsIntoName() async {
        let parser = NaturalLanguageMealParser()
        let result = await parser.parse(description: "3 ripe bananas")

        #expect(result.ingredients.count == 1)
        let item = result.ingredients[0]
        // "ripe" is not a known unit, so it folds back into the food name.
        #expect(item.quantity == 3)
        #expect(item.unit == nil)
        #expect(item.name == "ripe bananas")
    }

    // MARK: - Robustness / no-crash (pins the safe-range-binding fix)

    @Test("Empty string returns no ingredients without crashing")
    func emptyStringDoesNotCrash() async {
        let parser = NaturalLanguageMealParser()
        let result = await parser.parse(description: "")
        #expect(result.ingredients.isEmpty)
        #expect(result.isAIParsed == false)
    }

    @Test("Whitespace-only string returns no ingredients without crashing")
    func whitespaceOnlyDoesNotCrash() async {
        let parser = NaturalLanguageMealParser()
        let result = await parser.parse(description: "   \n\t  ")
        #expect(result.ingredients.isEmpty)
    }

    @Test("Only-a-number input does not crash and yields a sensible result")
    func onlyANumberDoesNotCrash() async {
        let parser = NaturalLanguageMealParser()
        let result = await parser.parse(description: "5")

        // A bare number has no food name; it should not crash and should
        // produce at most a single (name-only) ingredient.
        #expect(result.ingredients.count <= 1)
        if let item = result.ingredients.first {
            #expect(item.name == "5")
        }
    }

    @Test("Leading and trailing separators do not crash and are dropped")
    func strayLeadingTrailingSeparatorsDoNotCrash() async {
        let parser = NaturalLanguageMealParser()
        let result = await parser.parse(description: ", rice ,")

        // Empty segments produced by the stray commas are filtered out.
        #expect(result.ingredients.count == 1)
        #expect(result.ingredients.first?.name == "rice")
    }

    @Test("Repeated separators with empty segments do not crash")
    func repeatedSeparatorsDoNotCrash() async {
        let parser = NaturalLanguageMealParser()
        let result = await parser.parse(description: "eggs and and bacon")

        // The empty middle segment is filtered; two real ingredients remain.
        #expect(result.ingredients.count == 2)
        #expect(result.ingredients[0].name == "eggs")
        #expect(result.ingredients[1].name == "bacon")
    }

    @Test("Irregular internal spacing does not crash and trims correctly")
    func weirdSpacingDoesNotCrash() async {
        let parser = NaturalLanguageMealParser()
        let result = await parser.parse(description: "2    cups     rice")

        #expect(result.ingredients.count == 1)
        let item = result.ingredients[0]
        #expect(item.quantity == 2)
        #expect(item.unit == .cup)
        #expect(item.name == "rice")
    }

    @Test("Unicode and emoji input does not crash and returns a result")
    func unicodeInputDoesNotCrash() async {
        let parser = NaturalLanguageMealParser()
        let result = await parser.parse(description: "2 cups café crème 🍰")

        // The key assertion is that parsing a multi-byte/emoji string over
        // NSRange-backed regex ranges does not crash. A result is returned.
        #expect(result.ingredients.count == 1)
        #expect(result.ingredients.first?.quantity == 2)
    }

    @Test("Decimal-only and lone-symbol inputs do not crash")
    func miscEdgeInputsDoNotCrash() async {
        let parser = NaturalLanguageMealParser()

        let decimalOnly = await parser.parse(description: "2.5")
        #expect(decimalOnly.ingredients.count <= 1)

        let symbols = await parser.parse(description: "+++")
        #expect(symbols.ingredients.isEmpty)
    }
}
