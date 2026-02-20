import Foundation
import SwiftData
import SwiftUI

/// Manages the demo data lifecycle for testing and demonstration purposes.
/// Demo data can be toggled on/off in Settings and uses predictable UUIDs for clean identification.
@MainActor
final class DemoDataManager: ObservableObject {

    // MARK: - Published State

    /// Toggle state persisted in UserDefaults
    @AppStorage("isDemoDataEnabled") var isDemoDataEnabled: Bool = false

    /// Whether an operation is currently in progress
    @Published private(set) var isLoading: Bool = false

    /// Error message if the last operation failed
    @Published var errorMessage: String?

    // MARK: - Dependencies

    private var modelContext: ModelContext?
    private var privateDataManager: PrivateDataManager?

    // MARK: - Initialization

    init() {}

    /// Configures the manager with required dependencies
    func configure(modelContext: ModelContext, privateDataManager: PrivateDataManager?) {
        self.modelContext = modelContext
        self.privateDataManager = privateDataManager
    }

    // MARK: - Public API

    /// Main entry point for toggling demo data
    func toggleDemoData() async {
        guard let modelContext = modelContext else {
            errorMessage = "Model context not configured"
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            if isDemoDataEnabled {
                try await removeDemoData(from: modelContext)
                isDemoDataEnabled = false
            } else {
                try await insertDemoData(into: modelContext)
                isDemoDataEnabled = true
            }
        } catch {
            errorMessage = error.localizedDescription
            AppLogger.swiftData.error("Demo data operation failed", error: error)
        }

        isLoading = false
    }

    /// Enables demo data if not already enabled
    func enableDemoData() async {
        guard !isDemoDataEnabled else { return }
        await toggleDemoData()
    }

    /// Disables demo data if currently enabled
    func disableDemoData() async {
        guard isDemoDataEnabled else { return }
        await toggleDemoData()
    }

    // MARK: - Insertion

    /// Inserts all demo data into the database
    /// Insertion order respects relationships: Ingredients -> Users -> Recipes -> WeekPlan -> MealSlots -> GroceryItems
    private func insertDemoData(into context: ModelContext) async throws {
        // Fetch household for linking
        let householdDescriptor = FetchDescriptor<Household>()
        let household = (try? context.fetch(householdDescriptor))?.first

        // 1. Insert Ingredients
        var ingredientMap: [Int: Ingredient] = [:]
        for (index, demoIngredient) in DemoDataCatalog.ingredients.enumerated() {
            let ingredient = Ingredient(
                id: demoIngredient.id,
                name: demoIngredient.name,
                category: demoIngredient.category,
                defaultUnit: demoIngredient.defaultUnit,
                caloriesPer100g: demoIngredient.caloriesPer100g,
                proteinPer100g: demoIngredient.proteinPer100g,
                carbsPer100g: demoIngredient.carbsPer100g,
                fatPer100g: demoIngredient.fatPer100g,
                isUserCreated: false
            )
            ingredient.household = household
            context.insert(ingredient)
            ingredientMap[index] = ingredient
        }

        // 2. Insert Users
        var userMap: [Int: User] = [:]
        for (index, demoUser) in DemoDataCatalog.users.enumerated() {
            let user = User(
                id: demoUser.id,
                displayName: demoUser.displayName,
                avatarEmoji: demoUser.avatarEmoji,
                avatarColorHex: demoUser.avatarColorHex
            )
            user.household = household
            context.insert(user)
            userMap[index] = user
        }

        // 3. Insert Recipes with RecipeIngredients
        var recipeMap: [Int: Recipe] = [:]
        for (index, demoRecipe) in DemoDataCatalog.recipes.enumerated() {
            let recipe = Recipe(
                id: demoRecipe.id,
                title: demoRecipe.title,
                summary: demoRecipe.summary,
                servings: demoRecipe.servings,
                prepTimeMinutes: demoRecipe.prepTimeMinutes,
                cookTimeMinutes: demoRecipe.cookTimeMinutes,
                instructions: demoRecipe.instructions,
                tags: demoRecipe.tags,
                suggestedArchetypes: demoRecipe.suggestedArchetypes,
                createdBy: userMap[0] // Chef Chaos creates all recipes
            )
            recipe.household = household
            context.insert(recipe)
            recipeMap[index] = recipe

            // Add recipe ingredients
            for (order, ingredientRef) in demoRecipe.ingredients.enumerated() {
                if let ingredient = ingredientMap[ingredientRef.ingredientIndex] {
                    let recipeIngredient = RecipeIngredient(
                        id: UUID(uuidString: "DE000000-0005-\(String(format: "%04d", index))-\(String(format: "%04d", order))-000000000001")!,
                        ingredient: ingredient,
                        quantity: ingredientRef.quantity,
                        unit: ingredientRef.unit,
                        preparationNote: ingredientRef.preparationNote,
                        order: order
                    )
                    recipe.addIngredient(recipeIngredient)
                    context.insert(recipeIngredient)
                }
            }
        }

        // 4. Create WeekPlan for current week
        // Remove any auto-created empty plan for this week first to avoid duplicates
        let monday = currentWeekMonday()
        let existingDescriptor = FetchDescriptor<WeekPlan>()
        let existingPlans = (try? context.fetch(existingDescriptor)) ?? []
        for plan in existingPlans where Calendar.current.isDate(plan.weekStartDate, inSameDayAs: monday) {
            if !DemoDataCatalog.isDemoData(plan.id) {
                // Delete the auto-created plan's slots first
                for slot in plan.slots {
                    context.delete(slot)
                }
                for item in plan.groceryItems {
                    context.delete(item)
                }
                context.delete(plan)
            }
        }

        let weekPlan = WeekPlan(
            id: DemoDataCatalog.weekPlanID,
            weekStartDate: monday,
            status: .active
        )
        weekPlan.household = household
        context.insert(weekPlan)

        // 5. Create MealSlots
        var slotMap: [String: MealSlot] = [:] // Key: "day-mealType"
        for slotConfig in DemoDataCatalog.mealSlots {
            let slotID = UUID(uuidString: "DE000000-0004-\(String(format: "%04d", slotConfig.day.rawValue))-\(String(format: "%04d", slotConfig.mealType.sortOrder))-000000000001")!

            let slot = MealSlot(
                id: slotID,
                dayOfWeek: slotConfig.day,
                mealType: slotConfig.mealType,
                servingsPlanned: slotConfig.servings,
                recipes: slotConfig.recipeIndex.flatMap { recipeMap[$0] }.map { [$0] } ?? [],
                customMealName: slotConfig.customMealName,
                notes: slotConfig.notes,
                isSkipped: slotConfig.isSkipped
            )
            slot.weekPlan = weekPlan
            weekPlan.slots.append(slot)
            context.insert(slot)

            slotMap["\(slotConfig.day.rawValue)-\(slotConfig.mealType.rawValue)"] = slot
        }

        // 6. Generate grocery list from week plan
        weekPlan.generateGroceryList()

        // 7. Add manual grocery items
        for manualItem in DemoDataCatalog.manualGroceryItems {
            let groceryItem = GroceryItem(
                id: manualItem.id,
                customName: manualItem.name,
                quantity: manualItem.quantity,
                unit: manualItem.unit,
                category: manualItem.category,
                weekPlan: weekPlan
            )
            weekPlan.groceryItems.append(groceryItem)
            context.insert(groceryItem)
        }

        // Save SwiftData changes
        try context.save()

        // 8. Insert private data (meal logs and personal settings)
        await insertPrivateData(recipeMap: recipeMap)
    }

    /// Inserts demo personal data via PrivateDataManager.
    /// Generates meal logs from the actual meal plan slots so they always match.
    private func insertPrivateData(recipeMap: [Int: Recipe]) async {
        guard let privateDataManager = privateDataManager else { return }

        // Insert personal settings with demo goals
        let demoSettings = DemoDataCatalog.personalSettings
        var settings = PersonalSettings()
        settings.dailyCalorieTarget = demoSettings.dailyCalorieTarget
        settings.dailyProteinTarget = demoSettings.dailyProteinTarget
        settings.dailyCarbTarget = demoSettings.dailyCarbTarget
        settings.dailyFatTarget = demoSettings.dailyFatTarget
        settings.showMacroInsights = true
        await privateDataManager.saveSettings(settings)

        // Build a lookup from DayOfWeek to that day's meal slot configs
        var slotsByDay: [DayOfWeek: [DemoDataCatalog.MealSlotConfig]] = [:]
        for slot in DemoDataCatalog.mealSlots {
            slotsByDay[slot.day, default: []].append(slot)
        }

        // Generate meal logs from the plan for past days (consumed)
        // and today (planned, awaiting confirmation)
        let calendar = Calendar.current
        var logCounter = 0

        for dayOffset in -6...0 {
            let logDate = calendar.date(byAdding: .day, value: dayOffset, to: Date()) ?? Date()
            let dayOfWeek = dayOfWeekFor(date: logDate)

            guard let daySlots = slotsByDay[dayOfWeek] else { continue }

            for slotConfig in daySlots {
                // Skip slots that were marked as skipped in the plan
                guard !slotConfig.isSkipped else { continue }

                logCounter += 1
                let logID = UUID(uuidString: "DE000000-0007-0000-0000-\(String(format: "%012d", logCounter))")!

                let mealLog: PrivateMealLog
                if let customName = slotConfig.customMealName {
                    // Custom meal from the plan
                    mealLog = PrivateMealLog(
                        id: logID,
                        date: logDate,
                        mealType: slotConfig.mealType,
                        quickLogName: customName
                    )
                } else if let recipeIndex = slotConfig.recipeIndex, let recipe = recipeMap[recipeIndex] {
                    // Recipe-based meal from the plan
                    mealLog = PrivateMealLog(
                        id: logID,
                        date: logDate,
                        mealType: slotConfig.mealType,
                        recipeID: recipe.id,
                        servingsConsumed: 1.0
                    )
                } else {
                    continue
                }

                // Today's entries are "planned" (awaiting confirmation)
                // Past entries are "consumed"
                if dayOffset == 0 {
                    var planned = mealLog
                    planned.status = .planned
                    await privateDataManager.saveMealLog(planned)
                } else {
                    var consumed = mealLog
                    consumed.status = .consumed
                    await privateDataManager.saveMealLog(consumed)
                }
            }
        }
    }

    /// Maps a calendar date to the app's DayOfWeek enum
    private func dayOfWeekFor(date: Date) -> DayOfWeek {
        let weekday = Calendar.current.component(.weekday, from: date)
        // Calendar.weekday: 1=Sunday, 2=Monday, ... 7=Saturday
        // DayOfWeek: 1=Monday, 2=Tuesday, ... 7=Sunday
        switch weekday {
        case 1: return .sunday
        case 2: return .monday
        case 3: return .tuesday
        case 4: return .wednesday
        case 5: return .thursday
        case 6: return .friday
        case 7: return .saturday
        default: return .monday
        }
    }

    // MARK: - Removal

    /// Removes all demo data from the database
    /// Removal order is reverse of insertion to respect relationships
    private func removeDemoData(from context: ModelContext) async throws {
        // 1. Delete GroceryItems with demo UUIDs
        let groceryDescriptor = FetchDescriptor<GroceryItem>()
        let allGroceryItems = try context.fetch(groceryDescriptor)
        for item in allGroceryItems where DemoDataCatalog.isDemoData(item.id) {
            context.delete(item)
        }

        // 2. Delete MealSlots with demo UUIDs
        let slotDescriptor = FetchDescriptor<MealSlot>()
        let allSlots = try context.fetch(slotDescriptor)
        for slot in allSlots where DemoDataCatalog.isDemoData(slot.id) {
            context.delete(slot)
        }

        // 3. Delete WeekPlans with demo UUIDs
        let weekPlanDescriptor = FetchDescriptor<WeekPlan>()
        let allWeekPlans = try context.fetch(weekPlanDescriptor)
        for plan in allWeekPlans where DemoDataCatalog.isDemoData(plan.id) {
            context.delete(plan)
        }

        // 4. Delete RecipeIngredients with demo UUIDs
        let recipeIngredientDescriptor = FetchDescriptor<RecipeIngredient>()
        let allRecipeIngredients = try context.fetch(recipeIngredientDescriptor)
        for ri in allRecipeIngredients where DemoDataCatalog.isDemoData(ri.id) {
            context.delete(ri)
        }

        // 5. Delete Recipes with demo UUIDs
        let recipeDescriptor = FetchDescriptor<Recipe>()
        let allRecipes = try context.fetch(recipeDescriptor)
        for recipe in allRecipes where DemoDataCatalog.isDemoData(recipe.id) {
            context.delete(recipe)
        }

        // 6. Delete Ingredients with demo UUIDs
        let ingredientDescriptor = FetchDescriptor<Ingredient>()
        let allIngredients = try context.fetch(ingredientDescriptor)
        for ingredient in allIngredients where DemoDataCatalog.isDemoData(ingredient.id) {
            context.delete(ingredient)
        }

        // 7. Delete Users with demo UUIDs
        let userDescriptor = FetchDescriptor<User>()
        let allUsers = try context.fetch(userDescriptor)
        for user in allUsers where DemoDataCatalog.isDemoData(user.id) {
            context.delete(user)
        }

        // Save SwiftData changes
        try context.save()

        // 8. Remove private data
        await removePrivateData()
    }

    /// Removes demo private data via PrivateDataManager
    private func removePrivateData() async {
        guard let privateDataManager = privateDataManager else { return }

        // Delete demo meal logs
        for demoLog in DemoDataCatalog.mealLogs {
            // Find and delete the log by matching ID
            if let existingLog = privateDataManager.mealLogs.first(where: { $0.id == demoLog.id }) {
                await privateDataManager.deleteMealLog(existingLog)
            }
        }

        // Reset personal settings (clear goals)
        await privateDataManager.clearGoals()
    }

    // MARK: - Helpers

    /// Returns the Monday of the current week
    private func currentWeekMonday() -> Date {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        components.weekday = 2 // Monday
        return calendar.date(from: components) ?? Date()
    }
}

// MARK: - Environment Key

private struct DemoDataManagerKey: EnvironmentKey {
    static let defaultValue: DemoDataManager? = nil
}

extension EnvironmentValues {
    var demoDataManager: DemoDataManager? {
        get { self[DemoDataManagerKey.self] }
        set { self[DemoDataManagerKey.self] = newValue }
    }
}
