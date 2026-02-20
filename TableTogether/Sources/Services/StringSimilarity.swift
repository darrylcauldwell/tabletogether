import Foundation

/// Fuzzy string matching utilities for food name resolution.
/// Used by IngredientResolverService to rank FoodItem matches.
enum StringSimilarity {

    // MARK: - Levenshtein Distance

    /// Calculates normalized Levenshtein similarity between two strings.
    /// Returns a value from 0.0 (completely different) to 1.0 (identical).
    static func levenshtein(_ a: String, _ b: String) -> Double {
        let a = a.lowercased()
        let b = b.lowercased()

        if a == b { return 1.0 }
        if a.isEmpty || b.isEmpty { return 0.0 }

        let aChars = Array(a)
        let bChars = Array(b)
        let aLen = aChars.count
        let bLen = bChars.count

        // Dynamic programming matrix
        var matrix = [[Int]](repeating: [Int](repeating: 0, count: bLen + 1), count: aLen + 1)

        for i in 0...aLen { matrix[i][0] = i }
        for j in 0...bLen { matrix[0][j] = j }

        for i in 1...aLen {
            for j in 1...bLen {
                let cost = aChars[i - 1] == bChars[j - 1] ? 0 : 1
                matrix[i][j] = min(
                    matrix[i - 1][j] + 1,      // deletion
                    matrix[i][j - 1] + 1,      // insertion
                    matrix[i - 1][j - 1] + cost // substitution
                )
            }
        }

        let distance = matrix[aLen][bLen]
        let maxLen = max(aLen, bLen)
        return 1.0 - (Double(distance) / Double(maxLen))
    }

    // MARK: - Combined Score

    /// Calculates a combined similarity score blending multiple matching strategies.
    /// Returns a value from 0.0 (no match) to 1.0 (perfect match).
    ///
    /// Components:
    /// - Levenshtein similarity (40% weight)
    /// - Substring containment bonus (25% weight)
    /// - Prefix match bonus (15% weight)
    /// - Word overlap score (20% weight)
    static func combinedScore(_ query: String, _ candidate: String) -> Double {
        let q = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let c = candidate.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        if q == c { return 1.0 }
        if q.isEmpty || c.isEmpty { return 0.0 }

        // 1. Levenshtein similarity
        let levScore = levenshtein(q, c)

        // 2. Substring containment bonus
        let substringScore: Double
        if c.contains(q) {
            // Bonus scales with how much of the candidate the query covers
            substringScore = Double(q.count) / Double(c.count)
        } else if q.contains(c) {
            substringScore = Double(c.count) / Double(q.count)
        } else {
            substringScore = 0.0
        }

        // 3. Prefix match bonus
        let prefixScore: Double
        if c.hasPrefix(q) {
            prefixScore = 1.0
        } else if q.hasPrefix(c) {
            prefixScore = 0.8
        } else {
            // Check shared prefix length
            let commonPrefix = zip(q, c).prefix(while: { $0 == $1 }).count
            prefixScore = commonPrefix > 0 ? Double(commonPrefix) / Double(max(q.count, c.count)) : 0.0
        }

        // 4. Word overlap score
        let wordScore = wordOverlapScore(q, c)

        // Weighted combination
        return levScore * 0.40
             + substringScore * 0.25
             + prefixScore * 0.15
             + wordScore * 0.20
    }

    // MARK: - Word Overlap

    /// Calculates the proportion of words that overlap between two strings.
    private static func wordOverlapScore(_ a: String, _ b: String) -> Double {
        let aWords = Set(a.split(separator: " ").map(String.init))
        let bWords = Set(b.split(separator: " ").map(String.init))

        guard !aWords.isEmpty, !bWords.isEmpty else { return 0.0 }

        let intersection = aWords.intersection(bWords)
        let union = aWords.union(bWords)

        return Double(intersection.count) / Double(union.count)
    }
}
