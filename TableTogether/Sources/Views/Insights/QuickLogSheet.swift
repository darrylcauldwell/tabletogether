import SwiftUI
import SwiftData
import HealthKit

/// Entry mode for the meal log sheet
enum LogEntryMode: Hashable {
    case fromRecipes
    case describeIt
    case manualEntry
}

/// Sheet for quickly logging a meal
/// Supports selecting from recipes, describing a meal, or manual entry
///
/// Note: Meal logs are stored in CloudKit private database, never shared.
/// If connected to Apple Health, nutrition data is also written to HealthKit.
struct QuickLogSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.privateDataManager) private var privateDataManager
    @Environment(\.dismiss) private var dismiss
    @StateObject private var healthService = HealthKitService.shared
    @StateObject private var estimator = MealEstimatorService()

    @Query private var recipes: [Recipe]
    @Query private var mealSlots: [MealSlot]
    @Query private var users: [User]

    @State private var selectedMealType: MealType = .dinner
    @State private var searchText = ""
    @State private var selectedRecipe: Recipe?
    @State private var servingsConsumed: Double = 1.0
    @State private var entryMode: LogEntryMode = .fromRecipes

    // Manual entry fields
    @State private var manualMealName = ""
    @State private var manualCalories = ""
    @State private var manualProtein = ""
    @State private var manualCarbs = ""
    @State private var manualFat = ""

    // Meal estimation
    @State private var currentEstimate: MealEstimate?

    // Smart log (Describe it) state
    @State private var smartMealDescription = ""
    @State private var resolvedIngredients: [ResolvedIngredient] = []
    @State private var isSmartEstimate = false

    private var currentUser: User? {
        users.first
    }

    /// Today's planned meals where the current user is assigned
    private var todaysPlannedMeals: [(slot: MealSlot, recipe: Recipe)] {
        guard let user = currentUser else { return [] }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        var results: [(slot: MealSlot, recipe: Recipe)] = []
        for slot in mealSlots {
            guard slot.isPlanned,
                  slot.assignedTo.contains(where: { $0.id == user.id }),
                  let weekPlan = slot.weekPlan else { continue }

            let slotDate = weekPlan.date(for: slot.dayOfWeek)
            guard calendar.startOfDay(for: slotDate) == today else { continue }

            for recipe in slot.recipes {
                results.append((slot: slot, recipe: recipe))
            }
        }
        return results
    }

    private var filteredRecipes: [Recipe] {
        if searchText.isEmpty {
            return Array(recipes.prefix(10))
        }
        return recipes.filter { recipe in
            recipe.title.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var recentMeals: [RecentMealItem] {
        // Get unique recent meals from private storage
        guard let manager = privateDataManager else { return [] }

        var seen = Set<String>()
        var items: [RecentMealItem] = []

        for log in manager.mealLogs.prefix(20) {
            let key: String
            if let recipeID = log.recipeID {
                key = recipeID.uuidString
                if !seen.contains(key) {
                    seen.insert(key)
                    // Try to find recipe
                    if let recipe = recipes.first(where: { $0.id == recipeID }) {
                        items.append(RecentMealItem(recipe: recipe, name: nil))
                    }
                }
            } else if let name = log.quickLogName {
                key = name.lowercased()
                if !seen.contains(key) {
                    seen.insert(key)
                    items.append(RecentMealItem(recipe: nil, name: name))
                }
            }

            if items.count >= 5 { break }
        }

        return items
    }

    private var canLog: Bool {
        switch entryMode {
        case .fromRecipes:
            return selectedRecipe != nil
        case .describeIt:
            return !resolvedIngredients.isEmpty
        case .manualEntry:
            return !manualMealName.isEmpty
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Meal type picker
                    MealTypePicker(selectedType: $selectedMealType)
                        .padding(.horizontal)

                    // Mode toggle
                    Picker("Entry mode", selection: $entryMode) {
                        Text("From recipes").tag(LogEntryMode.fromRecipes)
                        Text("Describe it").tag(LogEntryMode.describeIt)
                        Text("Manual entry").tag(LogEntryMode.manualEntry)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    // From Today's Plan section
                    if entryMode == .fromRecipes && !todaysPlannedMeals.isEmpty && searchText.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("From Today's Plan")
                                .font(.subheadline)
                                .foregroundStyle(Color.slateGray)
                                .padding(.horizontal)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(todaysPlannedMeals, id: \.recipe.id) { item in
                                        Button {
                                            withAnimation(.easeInOut(duration: 0.2)) {
                                                selectedRecipe = item.recipe
                                                selectedMealType = item.slot.mealType
                                                let assignedCount = max(item.slot.assignedTo.count, 1)
                                                servingsConsumed = Double(item.slot.servingsPlanned) / Double(assignedCount)
                                            }
                                        } label: {
                                            HStack(spacing: 6) {
                                                Image(systemName: "calendar")
                                                    .font(.caption)
                                                Text(item.recipe.title)
                                                    .font(.subheadline)
                                                    .lineLimit(1)
                                            }
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                            .foregroundStyle(
                                                selectedRecipe?.id == item.recipe.id
                                                    ? Color.offWhite : Color.charcoal
                                            )
                                            .background(
                                                RoundedRectangle(cornerRadius: 20)
                                                    .fill(
                                                        selectedRecipe?.id == item.recipe.id
                                                            ? Color.sageGreen : Color.offWhite
                                                    )
                                            )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                    }

                    switch entryMode {
                    case .manualEntry:
                        // Manual entry fields
                        ManualEntrySection(
                            mealName: $manualMealName,
                            calories: $manualCalories,
                            protein: $manualProtein,
                            carbs: $manualCarbs,
                            fat: $manualFat,
                            estimator: estimator,
                            currentEstimate: $currentEstimate
                        )
                        .padding(.horizontal)

                    case .describeIt:
                        // Smart log — describe what you ate
                        SmartLogSection(
                            mealDescription: $smartMealDescription,
                            resolvedIngredients: $resolvedIngredients,
                            isSmartEstimate: $isSmartEstimate
                        )
                        .padding(.horizontal)

                    case .fromRecipes:
                        // Recipe search
                        VStack(spacing: 16) {
                            // Search field
                            HStack {
                                Image(systemName: "magnifyingglass")
                                    .foregroundStyle(Color.slateGray)

                                TextField("Search recipes", text: $searchText)
                                    .textFieldStyle(.plain)

                                if !searchText.isEmpty {
                                    Button {
                                        searchText = ""
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(Color.slateGray)
                                    }
                                }
                            }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.offWhite)
                            )
                            .padding(.horizontal)

                            // Recent meals row
                            if !recentMeals.isEmpty && searchText.isEmpty {
                                RecentMealsSection(
                                    recentMeals: recentMeals,
                                    selectedRecipe: $selectedRecipe
                                )
                            }

                            // Recipe list
                            RecipeSelectionList(
                                recipes: filteredRecipes,
                                selectedRecipe: $selectedRecipe
                            )
                            .padding(.horizontal)

                            // Servings adjuster (when recipe selected)
                            if selectedRecipe != nil {
                                DoubleServingsAdjuster(servings: $servingsConsumed)
                                    .padding(.horizontal)
                            }
                        }
                    }

                    Spacer(minLength: 40)
                }
                .padding(.vertical)
            }
            .navigationTitle("Log a meal")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Log") {
                        Task {
                            await logMeal()
                        }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!canLog)
                }
            }
        }
    }

    private func logMeal() async {
        guard let manager = privateDataManager else { return }

        let log: PrivateMealLog
        var calories: Int?
        var protein: Int?
        var carbs: Int?
        var fat: Int?
        var mealName: String?

        if entryMode == .describeIt {
            // Sum resolved ingredient macros
            let totalMacros = resolvedIngredients.reduce(MacroSummary.zero) { $0.adding($1.macros) }
            let name = smartMealDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            let displayName = name.isEmpty ? "Described meal" : name
            let logName = "\(displayName) (Quick Estimate)"

            log = PrivateMealLog(
                mealType: selectedMealType,
                quickLogName: logName,
                calories: totalMacros.calories.map { Int($0.rounded()) },
                protein: totalMacros.protein.map { Int($0.rounded()) },
                carbs: totalMacros.carbs.map { Int($0.rounded()) },
                fat: totalMacros.fat.map { Int($0.rounded()) }
            )

            calories = totalMacros.calories.map { Int($0.rounded()) }
            protein = totalMacros.protein.map { Int($0.rounded()) }
            carbs = totalMacros.carbs.map { Int($0.rounded()) }
            fat = totalMacros.fat.map { Int($0.rounded()) }
            mealName = logName
        } else if entryMode == .manualEntry {
            // Use quick log initializer for manual entry
            log = PrivateMealLog(
                mealType: selectedMealType,
                quickLogName: manualMealName,
                calories: Int(manualCalories),
                protein: Int(manualProtein),
                carbs: Int(manualCarbs),
                fat: Int(manualFat)
            )

            // Capture values for HealthKit
            calories = Int(manualCalories)
            protein = Int(manualProtein)
            carbs = Int(manualCarbs)
            fat = Int(manualFat)
            mealName = manualMealName
        } else if entryMode == .fromRecipes, let recipe = selectedRecipe {
            // Use standard initializer for recipe-based log
            log = PrivateMealLog(
                mealType: selectedMealType,
                recipeID: recipe.id,
                servingsConsumed: servingsConsumed
            )

            // Calculate macro values from recipe for HealthKit
            if let macros = recipe.macrosPerServing {
                calories = macros.calories.map { Int($0 * servingsConsumed) }
                protein = macros.protein.map { Int($0 * servingsConsumed) }
                carbs = macros.carbs.map { Int($0 * servingsConsumed) }
                fat = macros.fat.map { Int($0 * servingsConsumed) }
            }
            mealName = recipe.title
        } else {
            return
        }

        // Save to private CloudKit database
        await manager.saveMealLog(log)

        // Also save to HealthKit if authorized
        if healthService.isAuthorized {
            do {
                try await healthService.logMealToHealthKit(
                    calories: calories,
                    protein: protein,
                    carbs: carbs,
                    fat: fat,
                    date: Date(),
                    mealName: mealName
                )
            } catch {
                // HealthKit write failed - not critical, don't show error to user
                print("Failed to log meal to HealthKit: \(error)")
            }
        }
    }
}

// MARK: - Meal Type Picker

struct MealTypePicker: View {
    @Binding var selectedType: MealType

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Meal")
                .font(.subheadline)
                .foregroundStyle(Color.slateGray)

            HStack(spacing: 12) {
                ForEach(MealType.allCases, id: \.self) { type in
                    MealTypeButton(
                        type: type,
                        isSelected: selectedType == type
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedType = type
                        }
                    }
                }
            }
        }
    }
}

struct MealTypeButton: View {
    let type: MealType
    let isSelected: Bool
    let action: () -> Void

    private var icon: String {
        switch type {
        case .breakfast: return "sunrise"
        case .lunch: return "sun.max"
        case .dinner: return "moon.stars"
        case .snack: return "leaf"
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20))

                Text(type.rawValue.capitalized)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .foregroundStyle(isSelected ? Color.offWhite : Color.charcoal)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.sageGreen : Color.offWhite)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Manual Entry Section

struct ManualEntrySection: View {
    @Binding var mealName: String
    @Binding var calories: String
    @Binding var protein: String
    @Binding var carbs: String
    @Binding var fat: String
    var estimator: MealEstimatorService
    @Binding var currentEstimate: MealEstimate?

    var body: some View {
        VStack(spacing: 16) {
            // Meal name with estimate button
            VStack(alignment: .leading, spacing: 6) {
                Text("What did you eat?")
                    .font(.subheadline)
                    .foregroundStyle(Color.slateGray)

                HStack(spacing: 8) {
                    TextField("e.g., Leftover pasta", text: $mealName)
                        .textFieldStyle(.plain)
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.offWhite)
                        )

                    Button {
                        performEstimate()
                    } label: {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.sageGreen)
                            .frame(width: 44, height: 44)
                            .background(Color.sageGreen.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .disabled(mealName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel("Estimate nutrition")
                    .accessibilityHint("Estimates calories and macros from the meal description")
                }
            }

            // Macro fields
            VStack(alignment: .leading, spacing: 6) {
                Text("Nutrition (optional)")
                    .font(.subheadline)
                    .foregroundStyle(Color.slateGray)

                HStack(spacing: 12) {
                    MacroInputField(label: "Cal", value: $calories)
                    MacroInputField(label: "P (g)", value: $protein)
                    MacroInputField(label: "C (g)", value: $carbs)
                    MacroInputField(label: "F (g)", value: $fat)
                }
            }

            // Estimate breakdown
            if let estimate = currentEstimate {
                EstimateBreakdownCard(estimate: estimate)
            }

            Text("Rough estimates are fine")
                .font(.caption)
                .foregroundStyle(Color.slateGray)
        }
    }

    private func performEstimate() {
        guard let estimate = estimator.estimate(description: mealName) else {
            currentEstimate = nil
            return
        }

        // Fill macro fields from estimate
        if let cal = estimate.totalMacros.calories {
            calories = "\(Int(cal.rounded()))"
        }
        if let p = estimate.totalMacros.protein {
            protein = "\(Int(p.rounded()))"
        }
        if let c = estimate.totalMacros.carbs {
            carbs = "\(Int(c.rounded()))"
        }
        if let f = estimate.totalMacros.fat {
            fat = "\(Int(f.rounded()))"
        }

        currentEstimate = estimate
    }
}

struct MacroInputField: View {
    let label: String
    @Binding var value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(Color.slateGray)

            TextField("--", text: $value)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.center)
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.offWhite)
                )
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Estimate Breakdown Card

struct EstimateBreakdownCard: View {
    let estimate: MealEstimate

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Approximate breakdown")
                .font(.caption)
                .foregroundStyle(Color.slateGray)

            VStack(spacing: 4) {
                ForEach(estimate.components) { item in
                    HStack {
                        Text("\(item.quantity) \(item.name.lowercased())")
                            .font(.caption)
                            .foregroundStyle(Color.slateGray)

                        Spacer()

                        if let cal = item.macros.calories {
                            Text("\(Int(cal.rounded())) cal")
                                .font(.caption)
                                .foregroundStyle(Color.slateGray)
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.offWhite)
        )
    }
}

// MARK: - Recent Meals Section

struct RecentMealItem: Identifiable {
    let id = UUID()
    let recipe: Recipe?
    let name: String?

    var displayName: String {
        recipe?.title ?? name ?? "Meal"
    }
}

struct RecentMealsSection: View {
    let recentMeals: [RecentMealItem]
    @Binding var selectedRecipe: Recipe?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent")
                .font(.subheadline)
                .foregroundStyle(Color.slateGray)
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(recentMeals) { item in
                        RecentMealChip(
                            name: item.displayName,
                            isSelected: selectedRecipe?.id == item.recipe?.id && item.recipe != nil
                        ) {
                            if let recipe = item.recipe {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedRecipe = recipe
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

struct RecentMealChip: View {
    let name: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.caption)

                Text(name)
                    .font(.subheadline)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .foregroundStyle(isSelected ? Color.offWhite : Color.charcoal)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(isSelected ? Color.sageGreen : Color.offWhite)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Recipe Selection List

struct RecipeSelectionList: View {
    let recipes: [Recipe]
    @Binding var selectedRecipe: Recipe?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recipes")
                .font(.subheadline)
                .foregroundStyle(Color.slateGray)

            if recipes.isEmpty {
                Text("No recipes found")
                    .font(.subheadline)
                    .foregroundStyle(Color.slateGray)
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: 8) {
                    ForEach(recipes) { recipe in
                        RecipeSelectionRow(
                            recipe: recipe,
                            isSelected: selectedRecipe?.id == recipe.id
                        ) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedRecipe = recipe
                            }
                        }
                    }
                }
            }
        }
    }
}

struct RecipeSelectionRow: View {
    let recipe: Recipe
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // Selection indicator
                ZStack {
                    Circle()
                        .stroke(isSelected ? Color.sageGreen : Color.slateGray.opacity(0.5), lineWidth: 2)
                        .frame(width: 22, height: 22)

                    if isSelected {
                        Circle()
                            .fill(Color.sageGreen)
                            .frame(width: 14, height: 14)
                    }
                }

                // Recipe info
                VStack(alignment: .leading, spacing: 2) {
                    Text(recipe.title)
                        .font(.subheadline)
                        .foregroundStyle(Color.charcoal)
                        .lineLimit(1)

                    if let macros = recipe.macrosPerServing, let calories = macros.calories {
                        Text("\(Int(calories)) cal per serving")
                            .font(.caption)
                            .foregroundStyle(Color.slateGray)
                    }
                }

                Spacer()

                // Time estimate
                if let totalTime = recipe.totalTimeMinutes {
                    Text("\(totalTime) min")
                        .font(.caption)
                        .foregroundStyle(Color.slateGray)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.sageGreen.opacity(0.1) : Color.offWhite)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Double Servings Adjuster
// Note: Uses Double for half-serving increments, separate from ServingsAdjuster in Components.swift

struct DoubleServingsAdjuster: View {
    @Binding var servings: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Servings consumed")
                .font(.subheadline)
                .foregroundStyle(Color.slateGray)

            HStack(spacing: 16) {
                Button {
                    if servings > 0.5 {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            servings -= 0.5
                        }
                    }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(Color.sageGreen)
                }
                .disabled(servings <= 0.5)

                Text(servingsText)
                    .font(.title2)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.charcoal)
                    .frame(minWidth: 60)

                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        servings += 0.5
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(Color.sageGreen)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.offWhite)
        )
    }

    private var servingsText: String {
        if servings == 1.0 {
            return "1 serving"
        } else if servings == floor(servings) {
            return "\(Int(servings)) servings"
        } else {
            return String(format: "%.1f servings", servings)
        }
    }
}

#Preview {
    QuickLogSheet()
        .modelContainer(for: [Recipe.self], inMemory: true)
}
