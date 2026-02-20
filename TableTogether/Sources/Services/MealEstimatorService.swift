import Foundation

// MARK: - Estimated Component

/// A single food component identified from a meal description.
struct EstimatedComponent: Identifiable {
    let id = UUID()
    let name: String
    let quantity: String
    let macros: MacroSummary
}

// MARK: - Meal Estimate

/// Result of estimating a meal from a natural language description.
struct MealEstimate {
    let originalDescription: String
    let components: [EstimatedComponent]
    let totalMacros: MacroSummary
}

// MARK: - Meal Estimator Service

/// Estimates macro nutrients from a natural language meal description.
/// All computation is local and synchronous — nothing leaves the device.
@MainActor
final class MealEstimatorService: ObservableObject {

    // MARK: - Public API

    /// Estimate the components and macros of a meal described in plain text.
    func estimate(description: String) -> MealEstimate? {
        let input = description.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return nil }

        var components: [EstimatedComponent] = []

        // 1. Try composite meal patterns first
        components = matchCompositePatterns(input)

        // 2. If no composite pattern matched, scan for individual food keywords
        if components.isEmpty {
            components = scanForFoods(input)
        }

        // 3. If still nothing recognised, return nil (let the user fill in manually)
        guard !components.isEmpty else { return nil }

        let total = components.reduce(MacroSummary.zero) { $0.adding($1.macros) }

        return MealEstimate(
            originalDescription: description,
            components: components,
            totalMacros: total
        )
    }

    // MARK: - Composite Pattern Matching

    private func matchCompositePatterns(_ input: String) -> [EstimatedComponent] {

        // "beans on toast"
        if input.contains("beans on toast") {
            return [
                component("Baked beans", quantity: "1 small tin", food: .bakedBeans),
                component("Toast", quantity: "2 slices", food: .whiteBread),
                component("Butter", quantity: "1 knob", food: .butter)
            ]
        }

        // "egg on toast" / "eggs on toast"
        if matches(input, pattern: "eggs? on toast") {
            var items: [EstimatedComponent] = [
                component("Eggs", quantity: "2", food: .egg, scale: 2),
                component("Toast", quantity: "2 slices", food: .whiteBread),
                component("Butter", quantity: "1 knob", food: .butter)
            ]
            items.append(contentsOf: identifyExtras(input, excluding: ["egg", "eggs", "toast"]))
            return items
        }

        // "___ on toast" (generic)
        if let match = firstMatch(input, pattern: "(.+?)\\s+on\\s+toast") {
            let topping = match
            var items: [EstimatedComponent] = [
                component("Toast", quantity: "2 slices", food: .whiteBread),
                component("Butter", quantity: "1 knob", food: .butter)
            ]
            items.insert(contentsOf: scanForFoods(topping), at: 0)
            if items.count == 2 {
                // Topping not recognised — add generic
                items.insert(EstimatedComponent(name: topping.capitalized, quantity: "1 portion", macros: MacroSummary(calories: 150, protein: 8, carbs: 5, fat: 8)), at: 0)
            }
            items.append(contentsOf: identifyExtras(input, excluding: ["toast", topping]))
            return items
        }

        // "___ sandwich"
        if let match = firstMatch(input, pattern: "(.+?)\\s+sandwich") {
            let filling = match
            var items: [EstimatedComponent] = [
                component("White bread", quantity: "2 slices", food: .whiteBread),
                component("Butter", quantity: "1 knob", food: .butter)
            ]
            let fillingComponents = scanForFoods(filling)
            if fillingComponents.isEmpty {
                items.insert(EstimatedComponent(name: filling.capitalized, quantity: "1 portion", macros: MacroSummary(calories: 150, protein: 10, carbs: 5, fat: 8)), at: 0)
            } else {
                items.insert(contentsOf: fillingComponents, at: 0)
            }
            items.append(contentsOf: identifyExtras(input, excluding: ["sandwich", filling]))
            return items
        }

        // "___ burger"
        if let match = firstMatch(input, pattern: "(.+?)\\s+burger") {
            let pattyType = match
            var items: [EstimatedComponent] = [
                component("Burger bun", quantity: "1", food: .burgerBun),
                component("Lettuce", quantity: "handful", food: .lettuce),
                component("Tomato", quantity: "1 slice", food: .tomato, scale: 0.25)
            ]
            let pattyComponents = scanForFoods(pattyType)
            if pattyComponents.isEmpty {
                items.insert(component("Beef patty", quantity: "1", food: .beefPatty), at: 0)
            } else {
                items.insert(contentsOf: pattyComponents, at: 0)
            }
            items.append(contentsOf: identifyExtras(input, excluding: ["burger", pattyType]))
            return items
        }

        // "___ wrap"
        if let match = firstMatch(input, pattern: "(.+?)\\s+wrap") {
            let filling = match
            var items: [EstimatedComponent] = [
                component("Tortilla wrap", quantity: "1", food: .wrap)
            ]
            let fillingComponents = scanForFoods(filling)
            if fillingComponents.isEmpty {
                items.insert(EstimatedComponent(name: filling.capitalized, quantity: "1 portion", macros: MacroSummary(calories: 150, protein: 10, carbs: 5, fat: 8)), at: 0)
            } else {
                items.insert(contentsOf: fillingComponents, at: 0)
            }
            items.append(contentsOf: identifyExtras(input, excluding: ["wrap", filling]))
            return items
        }

        // "___ omelette"
        if let match = firstMatch(input, pattern: "(.+?)\\s+omelette") {
            let filling = match
            var items: [EstimatedComponent] = [
                component("Eggs", quantity: "3", food: .egg, scale: 3),
                component("Butter", quantity: "1 knob", food: .butter)
            ]
            let fillingComponents = scanForFoods(filling)
            items.append(contentsOf: fillingComponents)
            items.append(contentsOf: identifyExtras(input, excluding: ["omelette", filling]))
            return items
        }

        // "plain omelette" / just "omelette"
        if input.contains("omelette") {
            return [
                component("Eggs", quantity: "3", food: .egg, scale: 3),
                component("Butter", quantity: "1 knob", food: .butter)
            ]
        }

        // "___ stir fry" / "___ stirfry"
        if let match = firstMatch(input, pattern: "(.+?)\\s+stir\\s*fry") {
            let protein = match
            var items: [EstimatedComponent] = []
            let proteinComponents = scanForFoods(protein)
            if proteinComponents.isEmpty {
                items.append(component("Chicken breast", quantity: "1", food: .chickenBreast))
            } else {
                items.append(contentsOf: proteinComponents)
            }
            items.append(component("Stir fry veg", quantity: "1 portion", food: .mixedVeg))
            items.append(component("Noodles", quantity: "1 portion", food: .noodles))
            items.append(component("Soy sauce", quantity: "1 tbsp", food: .soySauce))
            items.append(contentsOf: identifyExtras(input, excluding: ["stir", "fry", "stirfry", protein]))
            return items
        }

        // "bowl of ___"
        if let match = firstMatch(input, pattern: "bowl\\s+of\\s+(.+)") {
            let contents = match
            let found = scanForFoods(contents)
            if !found.isEmpty { return found }
            // Try generic bowl
            return [EstimatedComponent(name: contents.capitalized, quantity: "1 bowl", macros: MacroSummary(calories: 250, protein: 8, carbs: 35, fat: 8))]
        }

        // "cup of ___"
        if let match = firstMatch(input, pattern: "cup\\s+of\\s+(.+)") {
            let contents = match
            let found = scanForFoods(contents)
            if !found.isEmpty { return found }
            return [EstimatedComponent(name: contents.capitalized, quantity: "1 cup", macros: MacroSummary(calories: 30, protein: 1, carbs: 4, fat: 1))]
        }

        return []
    }

    // MARK: - Individual Food Scanning

    private func scanForFoods(_ input: String) -> [EstimatedComponent] {
        var found: [EstimatedComponent] = []
        var usedRanges: [Range<String.Index>] = []

        // Sort database entries by alias length (longest first) to avoid partial matches
        let sortedEntries = Self.foodDatabase.sorted { a, b in
            let aMax = a.aliases.map(\.count).max() ?? 0
            let bMax = b.aliases.map(\.count).max() ?? 0
            return aMax > bMax
        }

        for entry in sortedEntries {
            for alias in entry.aliases {
                if let range = input.range(of: alias) {
                    // Check this range doesn't overlap with an already-matched range
                    let overlaps = usedRanges.contains { $0.overlaps(range) }
                    if !overlaps {
                        usedRanges.append(range)
                        found.append(component(entry.name, quantity: entry.defaultQuantity, food: entry))
                        break
                    }
                }
            }
        }

        // Check for "with chips/fries", "with rice", "with salad", "and chips" etc.
        found.append(contentsOf: identifySidePatterns(input))

        return found
    }

    /// Identifies side dish patterns like "with chips", "and rice", "with salad"
    private func identifySidePatterns(_ input: String) -> [EstimatedComponent] {
        var sides: [EstimatedComponent] = []

        let sidePatterns: [(pattern: String, component: EstimatedComponent)] = [
            ("with chips", component("Chips", quantity: "1 portion", food: .chips)),
            ("and chips", component("Chips", quantity: "1 portion", food: .chips)),
            ("with fries", component("Chips", quantity: "1 portion", food: .chips)),
            ("and fries", component("Chips", quantity: "1 portion", food: .chips)),
            ("with rice", component("Rice", quantity: "1 portion", food: .rice)),
            ("and rice", component("Rice", quantity: "1 portion", food: .rice)),
            ("with salad", component("Side salad", quantity: "1 portion", food: .mixedSalad)),
            ("and salad", component("Side salad", quantity: "1 portion", food: .mixedSalad)),
            ("with noodles", component("Noodles", quantity: "1 portion", food: .noodles)),
            ("and noodles", component("Noodles", quantity: "1 portion", food: .noodles)),
            ("with couscous", component("Couscous", quantity: "1 portion", food: .couscous)),
            ("and couscous", component("Couscous", quantity: "1 portion", food: .couscous)),
        ]

        for side in sidePatterns {
            if input.contains(side.pattern) {
                sides.append(side.component)
            }
        }

        return sides
    }

    /// Identifies extras in the input that haven't already been handled
    private func identifyExtras(_ input: String, excluding: [String]) -> [EstimatedComponent] {
        var extras: [EstimatedComponent] = []

        // Check for common side patterns
        extras.append(contentsOf: identifySidePatterns(input))

        return extras
    }

    // MARK: - Helpers

    private func component(_ name: String, quantity: String, food: FoodEntry, scale: Double = 1.0) -> EstimatedComponent {
        EstimatedComponent(
            name: name,
            quantity: quantity,
            macros: food.macros.scaled(by: scale)
        )
    }

    private func matches(_ input: String, pattern: String) -> Bool {
        input.range(of: pattern, options: .regularExpression) != nil
    }

    private func firstMatch(_ input: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: input, range: NSRange(input.startIndex..., in: input)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: input)
        else { return nil }
        return String(input[range]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Food Database

    struct FoodEntry {
        let name: String
        let aliases: [String]
        let defaultQuantity: String
        let macros: MacroSummary

        // Convenience accessors for specific foods used in meal patterns
        static var whiteBread: FoodEntry { MealEstimatorService.foodDatabase.first { $0.name == "White bread" }! }
        static var butter: FoodEntry { MealEstimatorService.foodDatabase.first { $0.name == "Butter" }! }
        static var egg: FoodEntry { MealEstimatorService.foodDatabase.first { $0.name == "Egg" }! }
        static var chickenBreast: FoodEntry { MealEstimatorService.foodDatabase.first { $0.name == "Chicken breast" }! }
        static var mixedVeg: FoodEntry { MealEstimatorService.foodDatabase.first { $0.name == "Mixed vegetables" }! }
        static var noodles: FoodEntry { MealEstimatorService.foodDatabase.first { $0.name == "Noodles" }! }
        static var soySauce: FoodEntry { MealEstimatorService.foodDatabase.first { $0.name == "Soy sauce" }! }
        static var mixedSalad: FoodEntry { MealEstimatorService.foodDatabase.first { $0.name == "Mixed salad" }! }
        static var chips: FoodEntry { MealEstimatorService.foodDatabase.first { $0.name == "Chips" }! }
        static var rice: FoodEntry { MealEstimatorService.foodDatabase.first { $0.name == "Rice (cooked)" }! }
        static var couscous: FoodEntry { MealEstimatorService.foodDatabase.first { $0.name == "Couscous" }! }
        static var wrap: FoodEntry { MealEstimatorService.foodDatabase.first { $0.name == "Tortilla wrap" }! }
        static var burgerBun: FoodEntry { MealEstimatorService.foodDatabase.first { $0.name == "Burger bun" }! }
        static var beefPatty: FoodEntry { MealEstimatorService.foodDatabase.first { $0.name == "Beef patty" }! }
        static var bakedBeans: FoodEntry { MealEstimatorService.foodDatabase.first { $0.name == "Baked beans" }! }
        static var lettuce: FoodEntry { MealEstimatorService.foodDatabase.first { $0.name == "Lettuce" }! }
        static var tomato: FoodEntry { MealEstimatorService.foodDatabase.first { $0.name == "Tomato" }! }
    }

    // Per-serving macros for common foods
    // Values are approximate and based on typical UK portion sizes

    static let foodDatabase: [FoodEntry] = [

        // MARK: Bread & Bakery

        FoodEntry(name: "White bread", aliases: ["white bread", "bread"], defaultQuantity: "2 slices",
                  macros: MacroSummary(calories: 190, protein: 6, carbs: 36, fat: 2)),
        FoodEntry(name: "Brown bread", aliases: ["brown bread", "wholemeal bread", "whole wheat bread"], defaultQuantity: "2 slices",
                  macros: MacroSummary(calories: 180, protein: 8, carbs: 32, fat: 2)),
        FoodEntry(name: "Toast", aliases: ["toast"], defaultQuantity: "2 slices",
                  macros: MacroSummary(calories: 190, protein: 6, carbs: 36, fat: 2)),
        FoodEntry(name: "Roll", aliases: ["bread roll", "roll", "bap"], defaultQuantity: "1",
                  macros: MacroSummary(calories: 150, protein: 5, carbs: 28, fat: 2)),
        FoodEntry(name: "Tortilla wrap", aliases: ["tortilla wrap", "tortilla", "flour tortilla"], defaultQuantity: "1",
                  macros: MacroSummary(calories: 180, protein: 5, carbs: 30, fat: 4)),
        FoodEntry(name: "Pitta bread", aliases: ["pitta bread", "pitta", "pita bread", "pita"], defaultQuantity: "1",
                  macros: MacroSummary(calories: 160, protein: 6, carbs: 33, fat: 1)),
        FoodEntry(name: "Naan bread", aliases: ["naan bread", "naan", "nan bread"], defaultQuantity: "1",
                  macros: MacroSummary(calories: 260, protein: 8, carbs: 45, fat: 5)),
        FoodEntry(name: "Bagel", aliases: ["bagel"], defaultQuantity: "1",
                  macros: MacroSummary(calories: 250, protein: 10, carbs: 48, fat: 2)),
        FoodEntry(name: "Crumpet", aliases: ["crumpet", "crumpets"], defaultQuantity: "2",
                  macros: MacroSummary(calories: 180, protein: 6, carbs: 36, fat: 1)),
        FoodEntry(name: "Croissant", aliases: ["croissant"], defaultQuantity: "1",
                  macros: MacroSummary(calories: 230, protein: 5, carbs: 26, fat: 12)),
        FoodEntry(name: "Burger bun", aliases: ["burger bun", "bun"], defaultQuantity: "1",
                  macros: MacroSummary(calories: 180, protein: 5, carbs: 32, fat: 3)),

        // MARK: Proteins

        FoodEntry(name: "Chicken breast", aliases: ["chicken breast", "chicken"], defaultQuantity: "1 breast",
                  macros: MacroSummary(calories: 165, protein: 31, carbs: 0, fat: 4)),
        FoodEntry(name: "Fish fingers", aliases: ["fish fingers", "fish finger", "fishfinger", "fishfingers"], defaultQuantity: "3",
                  macros: MacroSummary(calories: 210, protein: 9, carbs: 18, fat: 10)),
        FoodEntry(name: "Salmon fillet", aliases: ["salmon fillet", "salmon"], defaultQuantity: "1 fillet",
                  macros: MacroSummary(calories: 280, protein: 30, carbs: 0, fat: 17)),
        FoodEntry(name: "Tuna (tinned)", aliases: ["tuna", "tinned tuna", "canned tuna"], defaultQuantity: "1 tin",
                  macros: MacroSummary(calories: 120, protein: 28, carbs: 0, fat: 1)),
        FoodEntry(name: "Prawns", aliases: ["prawns", "shrimp"], defaultQuantity: "1 portion",
                  macros: MacroSummary(calories: 100, protein: 22, carbs: 0, fat: 1)),
        FoodEntry(name: "Egg", aliases: ["egg", "eggs"], defaultQuantity: "1",
                  macros: MacroSummary(calories: 78, protein: 6, carbs: 1, fat: 5)),
        FoodEntry(name: "Bacon", aliases: ["bacon", "back bacon", "streaky bacon"], defaultQuantity: "2 rashers",
                  macros: MacroSummary(calories: 120, protein: 10, carbs: 0, fat: 9)),
        FoodEntry(name: "Sausage", aliases: ["sausage", "sausages", "pork sausage", "pork sausages"], defaultQuantity: "2",
                  macros: MacroSummary(calories: 250, protein: 14, carbs: 4, fat: 20)),
        FoodEntry(name: "Beef mince", aliases: ["beef mince", "mince", "ground beef"], defaultQuantity: "1 portion",
                  macros: MacroSummary(calories: 250, protein: 26, carbs: 0, fat: 17)),
        FoodEntry(name: "Ham", aliases: ["ham", "sliced ham"], defaultQuantity: "2 slices",
                  macros: MacroSummary(calories: 60, protein: 10, carbs: 1, fat: 2)),
        FoodEntry(name: "Turkey", aliases: ["turkey", "turkey breast", "sliced turkey"], defaultQuantity: "2 slices",
                  macros: MacroSummary(calories: 60, protein: 12, carbs: 1, fat: 1)),
        FoodEntry(name: "Steak", aliases: ["steak", "beef steak", "sirloin"], defaultQuantity: "1",
                  macros: MacroSummary(calories: 300, protein: 35, carbs: 0, fat: 18)),
        FoodEntry(name: "Lamb chop", aliases: ["lamb chop", "lamb chops", "lamb"], defaultQuantity: "2",
                  macros: MacroSummary(calories: 280, protein: 26, carbs: 0, fat: 20)),
        FoodEntry(name: "Beef patty", aliases: ["beef patty", "burger patty"], defaultQuantity: "1",
                  macros: MacroSummary(calories: 250, protein: 20, carbs: 0, fat: 18)),
        FoodEntry(name: "Baked beans", aliases: ["baked beans", "beans"], defaultQuantity: "1 small tin",
                  macros: MacroSummary(calories: 160, protein: 10, carbs: 24, fat: 1)),
        FoodEntry(name: "Tofu", aliases: ["tofu"], defaultQuantity: "1 portion",
                  macros: MacroSummary(calories: 120, protein: 12, carbs: 2, fat: 7)),
        FoodEntry(name: "Cod fillet", aliases: ["cod", "cod fillet", "white fish"], defaultQuantity: "1 fillet",
                  macros: MacroSummary(calories: 130, protein: 28, carbs: 0, fat: 1)),

        // MARK: Dairy

        FoodEntry(name: "Cheddar cheese", aliases: ["cheddar cheese", "cheddar", "cheese"], defaultQuantity: "30g",
                  macros: MacroSummary(calories: 120, protein: 7, carbs: 0, fat: 10)),
        FoodEntry(name: "Butter", aliases: ["butter"], defaultQuantity: "1 knob",
                  macros: MacroSummary(calories: 75, protein: 0, carbs: 0, fat: 8)),
        FoodEntry(name: "Milk (semi-skimmed)", aliases: ["milk", "semi-skimmed milk", "semi skimmed milk"], defaultQuantity: "200ml",
                  macros: MacroSummary(calories: 100, protein: 7, carbs: 10, fat: 4)),
        FoodEntry(name: "Yogurt", aliases: ["yogurt", "yoghurt", "natural yogurt", "greek yogurt", "greek yoghurt"], defaultQuantity: "1 pot",
                  macros: MacroSummary(calories: 120, protein: 10, carbs: 12, fat: 4)),
        FoodEntry(name: "Cream", aliases: ["cream", "double cream", "single cream"], defaultQuantity: "2 tbsp",
                  macros: MacroSummary(calories: 90, protein: 1, carbs: 1, fat: 10)),
        FoodEntry(name: "Cream cheese", aliases: ["cream cheese", "philadelphia"], defaultQuantity: "30g",
                  macros: MacroSummary(calories: 90, protein: 2, carbs: 1, fat: 9)),

        // MARK: Carb Sides

        FoodEntry(name: "Rice (cooked)", aliases: ["rice", "white rice", "cooked rice", "basmati rice"], defaultQuantity: "1 portion",
                  macros: MacroSummary(calories: 250, protein: 5, carbs: 55, fat: 1)),
        FoodEntry(name: "Pasta (cooked)", aliases: ["pasta", "spaghetti", "penne", "fusilli", "macaroni"], defaultQuantity: "1 portion",
                  macros: MacroSummary(calories: 280, protein: 10, carbs: 56, fat: 2)),
        FoodEntry(name: "Chips", aliases: ["chips", "fries", "oven chips", "french fries"], defaultQuantity: "1 portion",
                  macros: MacroSummary(calories: 310, protein: 4, carbs: 42, fat: 15)),
        FoodEntry(name: "Baked potato", aliases: ["baked potato", "jacket potato", "jacket spud"], defaultQuantity: "1 medium",
                  macros: MacroSummary(calories: 200, protein: 5, carbs: 46, fat: 0)),
        FoodEntry(name: "Mashed potato", aliases: ["mashed potato", "mash", "mashed potatoes"], defaultQuantity: "1 portion",
                  macros: MacroSummary(calories: 180, protein: 4, carbs: 28, fat: 6)),
        FoodEntry(name: "Boiled potatoes", aliases: ["boiled potatoes", "new potatoes", "boiled potato"], defaultQuantity: "1 portion",
                  macros: MacroSummary(calories: 140, protein: 3, carbs: 32, fat: 0)),
        FoodEntry(name: "Noodles", aliases: ["noodles", "egg noodles", "rice noodles"], defaultQuantity: "1 portion",
                  macros: MacroSummary(calories: 260, protein: 8, carbs: 50, fat: 3)),
        FoodEntry(name: "Couscous", aliases: ["couscous", "cous cous"], defaultQuantity: "1 portion",
                  macros: MacroSummary(calories: 220, protein: 8, carbs: 42, fat: 1)),

        // MARK: Sauces & Condiments

        FoodEntry(name: "Ketchup", aliases: ["ketchup", "tomato ketchup", "tomato sauce"], defaultQuantity: "1 tbsp",
                  macros: MacroSummary(calories: 15, protein: 0, carbs: 4, fat: 0)),
        FoodEntry(name: "Mayonnaise", aliases: ["mayonnaise", "mayo"], defaultQuantity: "1 tbsp",
                  macros: MacroSummary(calories: 100, protein: 0, carbs: 0, fat: 11)),
        FoodEntry(name: "Mustard", aliases: ["mustard", "english mustard"], defaultQuantity: "1 tsp",
                  macros: MacroSummary(calories: 5, protein: 0, carbs: 0, fat: 0)),
        FoodEntry(name: "Brown sauce", aliases: ["brown sauce", "hp sauce"], defaultQuantity: "1 tbsp",
                  macros: MacroSummary(calories: 15, protein: 0, carbs: 4, fat: 0)),
        FoodEntry(name: "Pesto", aliases: ["pesto", "green pesto", "basil pesto"], defaultQuantity: "1 tbsp",
                  macros: MacroSummary(calories: 80, protein: 2, carbs: 1, fat: 7)),
        FoodEntry(name: "Soy sauce", aliases: ["soy sauce"], defaultQuantity: "1 tbsp",
                  macros: MacroSummary(calories: 10, protein: 1, carbs: 1, fat: 0)),
        FoodEntry(name: "Gravy", aliases: ["gravy"], defaultQuantity: "4 tbsp",
                  macros: MacroSummary(calories: 30, protein: 1, carbs: 4, fat: 1)),
        FoodEntry(name: "Salsa", aliases: ["salsa"], defaultQuantity: "2 tbsp",
                  macros: MacroSummary(calories: 15, protein: 0, carbs: 3, fat: 0)),
        FoodEntry(name: "Sweet chilli sauce", aliases: ["sweet chilli sauce", "sweet chili sauce", "sweet chilli"], defaultQuantity: "1 tbsp",
                  macros: MacroSummary(calories: 30, protein: 0, carbs: 7, fat: 0)),
        FoodEntry(name: "BBQ sauce", aliases: ["bbq sauce", "barbecue sauce"], defaultQuantity: "1 tbsp",
                  macros: MacroSummary(calories: 25, protein: 0, carbs: 6, fat: 0)),
        FoodEntry(name: "Hummus", aliases: ["hummus", "houmous"], defaultQuantity: "2 tbsp",
                  macros: MacroSummary(calories: 70, protein: 3, carbs: 4, fat: 5)),
        FoodEntry(name: "Olive oil", aliases: ["olive oil"], defaultQuantity: "1 tbsp",
                  macros: MacroSummary(calories: 120, protein: 0, carbs: 0, fat: 14)),
        FoodEntry(name: "Curry sauce", aliases: ["curry sauce", "curry"], defaultQuantity: "1 portion",
                  macros: MacroSummary(calories: 120, protein: 2, carbs: 10, fat: 8)),

        // MARK: Vegetables

        FoodEntry(name: "Mixed salad", aliases: ["mixed salad", "salad", "side salad", "green salad"], defaultQuantity: "1 portion",
                  macros: MacroSummary(calories: 20, protein: 1, carbs: 3, fat: 0)),
        FoodEntry(name: "Tomato", aliases: ["tomato", "tomatoes"], defaultQuantity: "1 medium",
                  macros: MacroSummary(calories: 20, protein: 1, carbs: 4, fat: 0)),
        FoodEntry(name: "Onion", aliases: ["onion", "onions"], defaultQuantity: "1 medium",
                  macros: MacroSummary(calories: 40, protein: 1, carbs: 9, fat: 0)),
        FoodEntry(name: "Peppers", aliases: ["pepper", "peppers", "bell pepper", "bell peppers"], defaultQuantity: "1",
                  macros: MacroSummary(calories: 30, protein: 1, carbs: 6, fat: 0)),
        FoodEntry(name: "Mushrooms", aliases: ["mushroom", "mushrooms"], defaultQuantity: "1 portion",
                  macros: MacroSummary(calories: 15, protein: 2, carbs: 1, fat: 0)),
        FoodEntry(name: "Sweetcorn", aliases: ["sweetcorn", "sweet corn", "corn"], defaultQuantity: "1 portion",
                  macros: MacroSummary(calories: 80, protein: 3, carbs: 15, fat: 1)),
        FoodEntry(name: "Peas", aliases: ["peas", "garden peas"], defaultQuantity: "1 portion",
                  macros: MacroSummary(calories: 70, protein: 5, carbs: 10, fat: 1)),
        FoodEntry(name: "Broccoli", aliases: ["broccoli"], defaultQuantity: "1 portion",
                  macros: MacroSummary(calories: 35, protein: 3, carbs: 4, fat: 0)),
        FoodEntry(name: "Carrots", aliases: ["carrot", "carrots"], defaultQuantity: "1 portion",
                  macros: MacroSummary(calories: 40, protein: 1, carbs: 8, fat: 0)),
        FoodEntry(name: "Green beans", aliases: ["green beans", "runner beans"], defaultQuantity: "1 portion",
                  macros: MacroSummary(calories: 25, protein: 2, carbs: 4, fat: 0)),
        FoodEntry(name: "Spinach", aliases: ["spinach"], defaultQuantity: "1 portion",
                  macros: MacroSummary(calories: 20, protein: 3, carbs: 1, fat: 0)),
        FoodEntry(name: "Avocado", aliases: ["avocado", "avo"], defaultQuantity: "1/2",
                  macros: MacroSummary(calories: 160, protein: 2, carbs: 2, fat: 15)),
        FoodEntry(name: "Coleslaw", aliases: ["coleslaw", "cole slaw"], defaultQuantity: "1 portion",
                  macros: MacroSummary(calories: 130, protein: 1, carbs: 8, fat: 10)),
        FoodEntry(name: "Mixed vegetables", aliases: ["mixed veg", "mixed vegetables", "stir fry veg", "stir fry vegetables"], defaultQuantity: "1 portion",
                  macros: MacroSummary(calories: 60, protein: 3, carbs: 8, fat: 1)),
        FoodEntry(name: "Lettuce", aliases: ["lettuce", "iceberg lettuce"], defaultQuantity: "handful",
                  macros: MacroSummary(calories: 5, protein: 0, carbs: 1, fat: 0)),
        FoodEntry(name: "Cucumber", aliases: ["cucumber"], defaultQuantity: "1/4",
                  macros: MacroSummary(calories: 10, protein: 0, carbs: 2, fat: 0)),

        // MARK: Fruit

        FoodEntry(name: "Apple", aliases: ["apple"], defaultQuantity: "1",
                  macros: MacroSummary(calories: 80, protein: 0, carbs: 20, fat: 0)),
        FoodEntry(name: "Banana", aliases: ["banana"], defaultQuantity: "1",
                  macros: MacroSummary(calories: 105, protein: 1, carbs: 27, fat: 0)),
        FoodEntry(name: "Orange", aliases: ["orange", "satsuma", "clementine", "tangerine"], defaultQuantity: "1",
                  macros: MacroSummary(calories: 60, protein: 1, carbs: 15, fat: 0)),
        FoodEntry(name: "Berries", aliases: ["berries", "strawberries", "blueberries", "raspberries"], defaultQuantity: "1 handful",
                  macros: MacroSummary(calories: 40, protein: 1, carbs: 9, fat: 0)),
        FoodEntry(name: "Grapes", aliases: ["grapes"], defaultQuantity: "1 handful",
                  macros: MacroSummary(calories: 60, protein: 1, carbs: 15, fat: 0)),
        FoodEntry(name: "Melon", aliases: ["melon", "watermelon", "honeydew"], defaultQuantity: "1 slice",
                  macros: MacroSummary(calories: 45, protein: 1, carbs: 11, fat: 0)),
        FoodEntry(name: "Pear", aliases: ["pear"], defaultQuantity: "1",
                  macros: MacroSummary(calories: 85, protein: 0, carbs: 22, fat: 0)),

        // MARK: Snacks & Common Meals

        FoodEntry(name: "Biscuit", aliases: ["biscuit", "biscuits", "digestive", "digestives", "cookie", "cookies"], defaultQuantity: "2",
                  macros: MacroSummary(calories: 140, protein: 2, carbs: 20, fat: 6)),
        FoodEntry(name: "Chocolate bar", aliases: ["chocolate bar", "chocolate", "snickers", "mars bar", "kitkat", "kit kat"], defaultQuantity: "1",
                  macros: MacroSummary(calories: 250, protein: 3, carbs: 30, fat: 13)),
        FoodEntry(name: "Crisps", aliases: ["crisps", "crisp", "potato chips", "walkers"], defaultQuantity: "1 bag",
                  macros: MacroSummary(calories: 170, protein: 2, carbs: 18, fat: 10)),
        FoodEntry(name: "Cereal", aliases: ["cereal", "cornflakes", "weetabix", "bran flakes", "cheerios"], defaultQuantity: "1 bowl",
                  macros: MacroSummary(calories: 180, protein: 4, carbs: 38, fat: 1)),
        FoodEntry(name: "Porridge", aliases: ["porridge", "oats", "oatmeal", "porridge oats"], defaultQuantity: "1 bowl",
                  macros: MacroSummary(calories: 200, protein: 7, carbs: 34, fat: 4)),
        FoodEntry(name: "Granola", aliases: ["granola", "granola bar"], defaultQuantity: "1 portion",
                  macros: MacroSummary(calories: 230, protein: 5, carbs: 32, fat: 9)),
        FoodEntry(name: "Soup", aliases: ["soup", "tomato soup", "chicken soup"], defaultQuantity: "1 bowl",
                  macros: MacroSummary(calories: 150, protein: 5, carbs: 18, fat: 6)),
        FoodEntry(name: "Pizza slice", aliases: ["pizza", "pizza slice"], defaultQuantity: "2 slices",
                  macros: MacroSummary(calories: 450, protein: 18, carbs: 50, fat: 18)),
        FoodEntry(name: "Fish and chips", aliases: ["fish and chips", "fish & chips", "fish n chips"], defaultQuantity: "1 portion",
                  macros: MacroSummary(calories: 800, protein: 35, carbs: 70, fat: 40)),
        FoodEntry(name: "Cake (slice)", aliases: ["cake", "sponge cake", "victoria sponge"], defaultQuantity: "1 slice",
                  macros: MacroSummary(calories: 280, protein: 3, carbs: 38, fat: 13)),
        FoodEntry(name: "Scone", aliases: ["scone", "scones"], defaultQuantity: "1",
                  macros: MacroSummary(calories: 250, protein: 5, carbs: 35, fat: 10)),
        FoodEntry(name: "Toast with jam", aliases: ["toast and jam", "jam on toast"], defaultQuantity: "2 slices",
                  macros: MacroSummary(calories: 260, protein: 5, carbs: 50, fat: 3)),
        FoodEntry(name: "Nuts", aliases: ["nuts", "mixed nuts", "peanuts", "almonds", "cashews"], defaultQuantity: "1 handful",
                  macros: MacroSummary(calories: 180, protein: 6, carbs: 6, fat: 16)),
        FoodEntry(name: "Protein bar", aliases: ["protein bar"], defaultQuantity: "1",
                  macros: MacroSummary(calories: 220, protein: 20, carbs: 24, fat: 8)),

        // MARK: Drinks

        FoodEntry(name: "Tea with milk", aliases: ["tea with milk", "cup of tea", "cuppa", "brew", "tea"], defaultQuantity: "1 cup",
                  macros: MacroSummary(calories: 20, protein: 1, carbs: 2, fat: 1)),
        FoodEntry(name: "Coffee with milk", aliases: ["coffee with milk", "cup of coffee", "coffee", "latte", "flat white", "cappuccino"], defaultQuantity: "1 cup",
                  macros: MacroSummary(calories: 60, protein: 3, carbs: 5, fat: 3)),
        FoodEntry(name: "Orange juice", aliases: ["orange juice", "oj", "juice", "apple juice", "fruit juice"], defaultQuantity: "1 glass",
                  macros: MacroSummary(calories: 90, protein: 1, carbs: 22, fat: 0)),
        FoodEntry(name: "Smoothie", aliases: ["smoothie", "fruit smoothie"], defaultQuantity: "1 glass",
                  macros: MacroSummary(calories: 160, protein: 3, carbs: 35, fat: 1)),
        FoodEntry(name: "Hot chocolate", aliases: ["hot chocolate", "hot choc", "cocoa"], defaultQuantity: "1 mug",
                  macros: MacroSummary(calories: 180, protein: 6, carbs: 28, fat: 5)),
        FoodEntry(name: "Milkshake", aliases: ["milkshake", "milk shake"], defaultQuantity: "1 glass",
                  macros: MacroSummary(calories: 300, protein: 8, carbs: 45, fat: 10)),

        // MARK: Ready Meals & Takeaway

        FoodEntry(name: "Chicken tikka masala", aliases: ["chicken tikka masala", "tikka masala"], defaultQuantity: "1 portion",
                  macros: MacroSummary(calories: 450, protein: 30, carbs: 20, fat: 28)),
        FoodEntry(name: "Spaghetti bolognese", aliases: ["spaghetti bolognese", "spag bol", "bolognese"], defaultQuantity: "1 portion",
                  macros: MacroSummary(calories: 500, protein: 28, carbs: 58, fat: 16)),
        FoodEntry(name: "Chilli con carne", aliases: ["chilli con carne", "chili con carne", "chilli", "chili"], defaultQuantity: "1 portion",
                  macros: MacroSummary(calories: 350, protein: 28, carbs: 22, fat: 16)),
        FoodEntry(name: "Lasagne", aliases: ["lasagne", "lasagna"], defaultQuantity: "1 portion",
                  macros: MacroSummary(calories: 500, protein: 25, carbs: 40, fat: 25)),
        FoodEntry(name: "Mac and cheese", aliases: ["mac and cheese", "mac & cheese", "macaroni cheese", "mac n cheese"], defaultQuantity: "1 portion",
                  macros: MacroSummary(calories: 450, protein: 18, carbs: 45, fat: 22)),
        FoodEntry(name: "Shepherd's pie", aliases: ["shepherd's pie", "shepherds pie", "cottage pie"], defaultQuantity: "1 portion",
                  macros: MacroSummary(calories: 400, protein: 22, carbs: 35, fat: 20)),
    ]

}
