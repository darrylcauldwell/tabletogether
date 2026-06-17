import Testing
import Foundation
@testable import TableTogetherLib

@Suite("StringSimilarity Tests")
struct StringSimilarityTests {

    private let tolerance = 0.0001

    // MARK: - Levenshtein

    @Test("Identical strings score 1.0")
    func levenshteinIdentical() {
        #expect(StringSimilarity.levenshtein("tomato", "tomato") == 1.0)
    }

    @Test("Levenshtein is case-insensitive")
    func levenshteinCaseInsensitive() {
        #expect(StringSimilarity.levenshtein("Apple", "apple") == 1.0)
    }

    @Test("An empty string scores 0.0 against a non-empty one")
    func levenshteinEmpty() {
        #expect(StringSimilarity.levenshtein("", "apple") == 0.0)
        #expect(StringSimilarity.levenshtein("apple", "") == 0.0)
    }

    @Test("Completely different equal-length strings score 0.0")
    func levenshteinFullyDifferent() {
        // distance 3 over maxLen 3 -> 1 - 1 = 0
        #expect(StringSimilarity.levenshtein("abc", "xyz") == 0.0)
    }

    @Test("One-edit difference is scored proportionally")
    func levenshteinOneEdit() {
        // "cat" vs "cap": distance 1, maxLen 3 -> 1 - 1/3
        let score = StringSimilarity.levenshtein("cat", "cap")
        #expect(abs(score - (1.0 - 1.0 / 3.0)) < tolerance)
    }

    // MARK: - Combined score

    @Test("Combined score of identical strings is 1.0")
    func combinedIdentical() {
        #expect(StringSimilarity.combinedScore("chicken breast", "chicken breast") == 1.0)
    }

    @Test("Combined score against an empty string is 0.0")
    func combinedEmpty() {
        #expect(StringSimilarity.combinedScore("", "chicken") == 0.0)
        #expect(StringSimilarity.combinedScore("chicken", "") == 0.0)
    }

    @Test("Combined score whitespace-trims before comparing")
    func combinedTrims() {
        #expect(StringSimilarity.combinedScore("  milk  ", "milk") == 1.0)
    }

    @Test("All combined scores stay within [0, 1]")
    func combinedBounds() {
        let pairs = [("milk", "whole milk"), ("flour", "sugar"), ("egg", "eggs"),
                     ("chicken", "chicken breast"), ("tomato", "potato"), ("a", "zzzzz")]
        for (q, c) in pairs {
            let s = StringSimilarity.combinedScore(q, c)
            #expect(s >= 0.0 && s <= 1.0)
        }
    }

    @Test("A closer candidate scores higher than a distant one")
    func combinedOrdering() {
        // "chicken" is a prefix/substring of "chicken breast" but unrelated to "beef stew"
        let close = StringSimilarity.combinedScore("chicken", "chicken breast")
        let far = StringSimilarity.combinedScore("chicken", "beef stew")
        #expect(close > far)
    }

    @Test("A substring match outscores an unrelated candidate")
    func combinedSubstringBeatsUnrelated() {
        let substring = StringSimilarity.combinedScore("milk", "whole milk")
        let unrelated = StringSimilarity.combinedScore("milk", "sugar")
        #expect(substring > unrelated)
    }

    @Test("A shared prefix outscores no shared prefix, all else equal")
    func combinedPrefixHelps() {
        // "straw" prefixes "strawberry"; "berry" shares no prefix with it.
        let prefixed = StringSimilarity.combinedScore("straw", "strawberry")
        let notPrefixed = StringSimilarity.combinedScore("xxxxx", "strawberry")
        #expect(prefixed > notPrefixed)
    }
}
