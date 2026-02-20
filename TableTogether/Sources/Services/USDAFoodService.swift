import Foundation

/// Hybrid nutrition API client combining USDA FoodData Central and Open Food Facts.
///
/// Routing strategy:
/// - **Generic/whole foods** (chicken breast, rice, broccoli): USDA first — lab-verified,
///   complete nutrient data, clean descriptions. Falls back to OFF if USDA returns nothing.
/// - **Branded products** (Warburtons bread, Tesco yoghurt): Open Food Facts first — 3M+
///   products with strong UK/EU coverage. Supplements with USDA if OFF data is incomplete.
/// - **Rate limited**: If USDA returns 429, routes all queries through OFF automatically.
///
/// API key is read from `Info.plist` key `USDA_API_KEY`, falling back to `"DEMO_KEY"`
/// which is rate-limited but functional for development.
@MainActor
final class USDAFoodService {

    // MARK: - Singleton

    static let shared = USDAFoodService()

    // MARK: - Configuration

    private let apiKey: String
    private let usdaBaseURL = "https://api.nal.usda.gov/fdc"
    private let offBaseURL = "https://world.openfoodfacts.org/cgi/search.pl"
    private let session: URLSession

    /// Tracks whether USDA is currently rate-limited to avoid repeated 429s.
    /// Resets after 60 seconds.
    private var usdaRateLimitedUntil: Date?

    private init() {
        if let key = Bundle.main.object(forInfoDictionaryKey: "USDA_API_KEY") as? String, !key.isEmpty {
            self.apiKey = key
        } else {
            self.apiKey = "DEMO_KEY"
        }

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 15
        self.session = URLSession(configuration: config)
    }

    // MARK: - Hybrid Search

    /// Searches for foods using a hybrid strategy:
    /// - Branded queries → Open Food Facts first, USDA supplement
    /// - Generic queries → USDA first, Open Food Facts supplement
    /// - USDA rate limited → Open Food Facts only
    func search(query: String, pageSize: Int = 5) async throws -> [USDAFoodResult] {
        let isBranded = Self.looksLikeBrandedProduct(query)

        // If USDA is temporarily rate-limited, go straight to OFF
        if let rateLimitExpiry = usdaRateLimitedUntil, Date() < rateLimitExpiry {
            AppLogger.nutrition.debug("USDA rate-limit cooldown active, using Open Food Facts")
            return try await searchOpenFoodFacts(query: query, pageSize: pageSize)
        }

        if isBranded {
            return await searchBrandedHybrid(query: query, pageSize: pageSize)
        } else {
            return await searchGenericHybrid(query: query, pageSize: pageSize)
        }
    }

    /// Generic food strategy: USDA first (lab-verified whole foods), OFF if USDA is empty or limited.
    private func searchGenericHybrid(query: String, pageSize: Int) async -> [USDAFoodResult] {
        // Try USDA first
        do {
            let usdaResults = try await searchUSDA(query: query, pageSize: pageSize)
            if !usdaResults.isEmpty {
                // Check if top result has complete macros — if not, supplement with OFF
                if let top = usdaResults.first, top.hasCompleteMacros {
                    AppLogger.nutrition.debug("USDA returned \(usdaResults.count) results for '\(query)'")
                    return usdaResults
                }
            }
        } catch USDAError.rateLimited {
            usdaRateLimitedUntil = Date().addingTimeInterval(60)
            AppLogger.nutrition.info("USDA rate limited, cooling down for 60s")
        } catch {
            AppLogger.nutrition.debug("USDA search failed for '\(query)': \(error.localizedDescription)")
        }

        // Supplement or replace with OFF
        do {
            let offResults = try await searchOpenFoodFacts(query: query, pageSize: pageSize)
            if !offResults.isEmpty {
                AppLogger.nutrition.debug("Open Food Facts returned \(offResults.count) results for '\(query)'")
                return offResults.filter { $0.hasCompleteMacros }
            }
        } catch {
            AppLogger.nutrition.debug("Open Food Facts search also failed for '\(query)': \(error.localizedDescription)")
        }

        return []
    }

    /// Branded product strategy: OFF first (better branded coverage), USDA supplement if OFF is incomplete.
    private func searchBrandedHybrid(query: String, pageSize: Int) async -> [USDAFoodResult] {
        // Try OFF first for branded products
        do {
            let offResults = try await searchOpenFoodFacts(query: query, pageSize: pageSize)
            let completeResults = offResults.filter { $0.hasCompleteMacros }
            if !completeResults.isEmpty {
                AppLogger.nutrition.debug("Open Food Facts returned \(completeResults.count) branded results for '\(query)'")
                return completeResults
            }
        } catch {
            AppLogger.nutrition.debug("Open Food Facts search failed for '\(query)': \(error.localizedDescription)")
        }

        // Fall back to USDA
        do {
            let usdaResults = try await searchUSDA(query: query, pageSize: pageSize)
            if !usdaResults.isEmpty {
                AppLogger.nutrition.debug("USDA fallback returned \(usdaResults.count) results for branded query '\(query)'")
                return usdaResults
            }
        } catch USDAError.rateLimited {
            usdaRateLimitedUntil = Date().addingTimeInterval(60)
            AppLogger.nutrition.info("USDA rate limited during branded fallback")
        } catch {
            AppLogger.nutrition.debug("USDA fallback also failed for '\(query)': \(error.localizedDescription)")
        }

        return []
    }

    // MARK: - Brand Detection

    /// Common brand names and patterns that suggest a branded product query.
    private static let brandIndicators: Set<String> = [
        // UK supermarkets
        "tesco", "sainsbury", "sainsburys", "asda", "morrisons", "waitrose",
        "aldi", "lidl", "marks", "m&s", "ocado", "co-op", "coop",
        // Common UK/global brands
        "warburtons", "hovis", "kingsmill", "mcvities", "mcvitie",
        "cadbury", "nestle", "heinz", "kelloggs", "kellogg",
        "müller", "muller", "alpro", "oatly", "quorn", "linda mccartney",
        "innocent", "naked", "tropicana", "ribena", "lucozade",
        "birds eye", "birdseye", "richmond", "cathedral city",
        "lurpak", "anchor", "flora", "benecol",
        "walkers", "pringles", "doritos", "kettle",
        // US brands
        "kraft", "general mills", "nabisco", "oscar mayer", "tyson",
        "dannon", "chobani", "fage", "stonyfield",
        // Patterns
        "brand", "organic", "free range", "free-range",
    ]

    /// Heuristic: does the query look like it refers to a specific branded product?
    static func looksLikeBrandedProduct(_ query: String) -> Bool {
        let lowered = query.lowercased()

        // Check for known brand names
        for brand in brandIndicators {
            if lowered.contains(brand) {
                return true
            }
        }

        // Check for trademark-style patterns (capitalized multi-word with possessive)
        if lowered.contains("'s ") || lowered.contains("'s ") {
            return true
        }

        return false
    }

    // MARK: - USDA Direct Search

    /// Searches USDA FoodData Central directly.
    private func searchUSDA(query: String, pageSize: Int) async throws -> [USDAFoodResult] {
        guard var components = URLComponents(string: "\(usdaBaseURL)/v1/foods/search") else {
            throw USDAError.invalidURL
        }

        components.queryItems = [
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "pageSize", value: "\(pageSize)"),
            URLQueryItem(name: "dataType", value: "Foundation,SR Legacy,Survey (FNDDS)")
        ]

        guard let url = components.url else {
            throw USDAError.invalidURL
        }

        let (data, response) = try await session.data(from: url)

        if let httpResponse = response as? HTTPURLResponse {
            switch httpResponse.statusCode {
            case 200:
                break
            case 429:
                throw USDAError.rateLimited
            default:
                throw USDAError.httpError(statusCode: httpResponse.statusCode)
            }
        }

        let searchResponse = try JSONDecoder().decode(USDASearchResponse.self, from: data)
        return searchResponse.foods
    }

    // MARK: - USDA Detail

    /// Fetches detailed nutrition data for a specific USDA food by FDC ID.
    func fetchDetail(fdcId: Int) async throws -> USDAFoodDetail {
        guard var components = URLComponents(string: "\(usdaBaseURL)/v1/food/\(fdcId)") else {
            throw USDAError.invalidURL
        }

        components.queryItems = [
            URLQueryItem(name: "api_key", value: apiKey)
        ]

        guard let url = components.url else {
            throw USDAError.invalidURL
        }

        let (data, response) = try await session.data(from: url)

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            throw USDAError.httpError(statusCode: httpResponse.statusCode)
        }

        return try JSONDecoder().decode(USDAFoodDetail.self, from: data)
    }

    // MARK: - Open Food Facts Search

    /// Searches Open Food Facts for foods matching the query.
    private func searchOpenFoodFacts(query: String, pageSize: Int) async throws -> [USDAFoodResult] {
        guard var components = URLComponents(string: offBaseURL) else {
            throw USDAError.invalidURL
        }

        components.queryItems = [
            URLQueryItem(name: "search_terms", value: query),
            URLQueryItem(name: "search_simple", value: "1"),
            URLQueryItem(name: "action", value: "process"),
            URLQueryItem(name: "json", value: "1"),
            URLQueryItem(name: "page_size", value: "\(pageSize)"),
            URLQueryItem(name: "fields", value: "code,product_name,brands,nutriments")
        ]

        guard let url = components.url else {
            throw USDAError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("TableTogether/1.0 (iOS app; contact: app@example.com)", forHTTPHeaderField: "User-Agent")

        let (data, _) = try await session.data(for: request)

        let offResponse = try JSONDecoder().decode(OFFSearchResponse.self, from: data)

        // Convert Open Food Facts results to our unified USDAFoodResult format
        return offResponse.products.compactMap { product -> USDAFoodResult? in
            guard let name = product.productName, !name.isEmpty else { return nil }

            let nutrients = product.nutriments
            var foodNutrients: [USDANutrient] = []

            if let energy = nutrients?.energyKcal100g {
                foodNutrients.append(USDANutrient(nutrientId: 1008, nutrientName: "Energy", value: energy, unitName: "KCAL"))
            }
            if let protein = nutrients?.proteins100g {
                foodNutrients.append(USDANutrient(nutrientId: 1003, nutrientName: "Protein", value: protein, unitName: "G"))
            }
            if let carbs = nutrients?.carbohydrates100g {
                foodNutrients.append(USDANutrient(nutrientId: 1005, nutrientName: "Carbohydrate, by difference", value: carbs, unitName: "G"))
            }
            if let fat = nutrients?.fat100g {
                foodNutrients.append(USDANutrient(nutrientId: 1004, nutrientName: "Total lipid (fat)", value: fat, unitName: "G"))
            }
            if let fiber = nutrients?.fiber100g {
                foodNutrients.append(USDANutrient(nutrientId: 1079, nutrientName: "Fiber, total dietary", value: fiber, unitName: "G"))
            }
            if let sugars = nutrients?.sugars100g {
                foodNutrients.append(USDANutrient(nutrientId: 2000, nutrientName: "Sugars, total", value: sugars, unitName: "G"))
            }
            if let sodium = nutrients?.sodium100g {
                // Open Food Facts stores sodium in grams, USDA uses mg
                foodNutrients.append(USDANutrient(nutrientId: 1093, nutrientName: "Sodium, Na", value: sodium * 1000, unitName: "MG"))
            }

            return USDAFoodResult(
                fdcId: Int(product.code ?? "0") ?? 0,
                description: name,
                dataType: "Branded",
                brandOwner: product.brands,
                foodNutrients: foodNutrients,
                foodMeasures: []
            )
        }
    }
}

// MARK: - USDA Response Types

struct USDASearchResponse: Codable {
    let foods: [USDAFoodResult]
}

struct USDAFoodResult: Codable {
    let fdcId: Int
    let description: String
    let dataType: String?
    let brandOwner: String?
    let foodNutrients: [USDANutrient]
    let foodMeasures: [USDAMeasure]?

    /// Extract a specific nutrient value by ID
    func nutrientValue(id: Int) -> Double? {
        foodNutrients.first(where: { $0.nutrientId == id })?.value
    }

    /// Calories per 100g (Nutrient 1008)
    var caloriesPer100g: Double { nutrientValue(id: 1008) ?? 0 }

    /// Protein per 100g (Nutrient 1003)
    var proteinPer100g: Double { nutrientValue(id: 1003) ?? 0 }

    /// Carbs per 100g (Nutrient 1005)
    var carbsPer100g: Double { nutrientValue(id: 1005) ?? 0 }

    /// Fat per 100g (Nutrient 1004)
    var fatPer100g: Double { nutrientValue(id: 1004) ?? 0 }

    /// Fiber per 100g (Nutrient 1079)
    var fiberPer100g: Double? { nutrientValue(id: 1079) }

    /// Sugar per 100g (Nutrient 2000)
    var sugarPer100g: Double? { nutrientValue(id: 2000) }

    /// Sodium in mg per 100g (Nutrient 1093)
    var sodiumMgPer100g: Double? { nutrientValue(id: 1093) }

    /// Whether this result has all four core macros (calories, protein, carbs, fat) with non-zero values.
    var hasCompleteMacros: Bool {
        caloriesPer100g > 0 || proteinPer100g > 0 || carbsPer100g > 0 || fatPer100g > 0
    }

    /// Clean display name (removes "RAW", extra commas, etc.)
    var cleanDisplayName: String {
        var name = description

        // Remove trailing ", RAW" or ", raw" and similar USDA suffixes
        let suffixesToRemove = [", raw", ", upc: ", ", nfs"]
        for suffix in suffixesToRemove {
            if let range = name.range(of: suffix, options: .caseInsensitive) {
                name = String(name[name.startIndex..<range.lowerBound])
            }
        }

        // Title-case the result
        return name.capitalized
                    .replacingOccurrences(of: "  ", with: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct USDANutrient: Codable {
    let nutrientId: Int
    let nutrientName: String?
    let value: Double
    let unitName: String?
}

struct USDAMeasure: Codable {
    let disseminationText: String?
    let gramWeight: Double?

    /// Convert to CommonPortion
    var asCommonPortion: CommonPortion? {
        guard let name = disseminationText, let weight = gramWeight, weight > 0 else { return nil }
        return CommonPortion(name: name, gramWeight: weight)
    }
}

struct USDAFoodDetail: Codable {
    let fdcId: Int
    let description: String
    let dataType: String?
    let brandOwner: String?
    let foodNutrients: [USDADetailNutrient]?
    let foodPortions: [USDAFoodPortion]?
}

struct USDADetailNutrient: Codable {
    let nutrient: USDANutrientInfo?
    let amount: Double?
}

struct USDANutrientInfo: Codable {
    let id: Int
    let name: String?
    let unitName: String?
}

struct USDAFoodPortion: Codable {
    let portionDescription: String?
    let gramWeight: Double?
    let amount: Double?
    let measureUnit: USDAPortionUnit?
}

struct USDAPortionUnit: Codable {
    let name: String?
    let abbreviation: String?
}

// MARK: - Open Food Facts Response Types

struct OFFSearchResponse: Codable {
    let products: [OFFProduct]
}

struct OFFProduct: Codable {
    let code: String?
    let productName: String?
    let brands: String?
    let nutriments: OFFNutriments?

    enum CodingKeys: String, CodingKey {
        case code
        case productName = "product_name"
        case brands
        case nutriments
    }
}

struct OFFNutriments: Codable {
    let energyKcal100g: Double?
    let proteins100g: Double?
    let carbohydrates100g: Double?
    let fat100g: Double?
    let fiber100g: Double?
    let sugars100g: Double?
    let sodium100g: Double?

    enum CodingKeys: String, CodingKey {
        case energyKcal100g = "energy-kcal_100g"
        case proteins100g = "proteins_100g"
        case carbohydrates100g = "carbohydrates_100g"
        case fat100g = "fat_100g"
        case fiber100g = "fiber_100g"
        case sugars100g = "sugars_100g"
        case sodium100g = "sodium_100g"
    }
}

// MARK: - Errors

enum USDAError: Error, LocalizedError {
    case invalidURL
    case httpError(statusCode: Int)
    case rateLimited
    case noResults

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API URL"
        case .httpError(let code):
            return "API returned status \(code)"
        case .rateLimited:
            return "API rate limit reached"
        case .noResults:
            return "No foods found"
        }
    }
}
