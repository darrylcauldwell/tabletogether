import SwiftUI
import CoreData
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
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(PrivateDataManager.self) private var privateDataManager
    @Environment(\.dismiss) private var dismiss
    @State private var healthService = HealthKitService.shared
    @State private var estimator = MealEstimatorService()

    @FetchRequest(sortDescriptors: [SortDescriptor(\.title)]) private var recipes: FetchedResults<Recipe>
    @FetchRequest(sortDescriptors: [SortDescriptor(\.dayOfWeekRaw), SortDescriptor(\.mealTypeRaw)]) private var mealSlots: FetchedResults<MealSlot>
    @FetchRequest(sortDescriptors: [SortDescriptor(\.displayName)]) private var users: FetchedResults<User>

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
        User.current(in: users)
    }

    /// Today's planned meals for this user. Unassigned meals are household
    /// meals and count for everyone; assignment narrows the list (matches
    /// PrivateDataManager.seedingShare).
    private var todaysPlannedMeals: [(slot: MealSlot, recipe: Recipe)] {
        guard let user = currentUser else { return [] }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        var results: [(slot: MealSlot, recipe: Recipe)] = []
        for slot in mealSlots {
            guard slot.isPlanned,
                  slot.assignedToArray.isEmpty
                    || slot.assignedToArray.contains(where: { $0.id == user.id }),
                  let weekPlan = slot.weekPlan else { continue }

            let slotDate = weekPlan.date(for: slot.dayOfWeek)
            guard calendar.startOfDay(for: slotDate) == today else { continue }

            for recipe in slot.recipesArray {
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
        let manager = privateDataManager

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
                                .font(AppTypography.subheadline)
                                .foregroundStyle(Color.slateGray)
                                .padding(.horizontal)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(todaysPlannedMeals, id: \.recipe.id) { item in
                                        Button {
                                            withAnimation(.easeInOut(duration: 0.2)) {
                                                selectedRecipe = item.recipe
                                                selectedMealType = item.slot.mealType
                                                let assignedCount = max(item.slot.assignedToArray.count, 1)
                                                servingsConsumed = Double(item.slot.servingsPlanned) / Double(assignedCount)
                                            }
                                        } label: {
                                            HStack(spacing: 6) {
                                                Image(systemName: "calendar")
                                                    .font(AppTypography.caption)
                                                Text(item.recipe.title)
                                                    .font(AppTypography.subheadline)
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
        let manager = privateDataManager

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
                AppLogger.app.error("Failed to log meal to HealthKit: \(error)")
            }
        }
    }
}
