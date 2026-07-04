import CoreData

/// Container for a week's meal slots.
/// Each week plan starts on Monday and contains all meal slots for that week.
@objc(WeekPlan)
public class WeekPlan: NSManagedObject {

    @NSManaged public var id: UUID
    @NSManaged public var weekStartDate: Date
    @NSManaged public var householdNote: String?
    @NSManaged public var createdAt: Date
    @NSManaged public var modifiedAt: Date

    // MARK: - Relationships

    @NSManaged public var slots: NSSet?
    @NSManaged public var groceryItems: NSSet?
    @NSManaged public var household: Household?

    // MARK: - Typed Accessors

    var slotsArray: [MealSlot] {
        (slots?.allObjects as? [MealSlot]) ?? []
    }

    var groceryItemsArray: [GroceryItem] {
        (groceryItems?.allObjects as? [GroceryItem]) ?? []
    }

    // MARK: - Computed Properties

    var weekEndDate: Date {
        Calendar.current.date(byAdding: .day, value: 6, to: weekStartDate) ?? weekStartDate
    }

    var weekRangeDisplay: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        let start = formatter.string(from: weekStartDate)
        let yearFormatter = DateFormatter()
        yearFormatter.dateFormat = "d, yyyy"
        let end = yearFormatter.string(from: weekEndDate)
        return "\(start) - \(end)"
    }

    var shortWeekDisplay: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return "Week of \(formatter.string(from: weekStartDate))"
    }

    // NOTE: with lazy slots (#Change2/#Change3), slotsArray.count no longer
    // means "cells in the week" — any future progress metric must use the
    // virtual grid (DayOfWeek.allCases × MealType.defaultPlannedMeals) as its
    // denominator, never the materialized slot count.
    var plannedSlots: [MealSlot] { slotsArray.filter { $0.isPlanned } }

    var isCurrentWeek: Bool {
        Calendar.current.isDate(Date(), equalTo: weekStartDate, toGranularity: .weekOfYear)
    }

    var uniqueRecipes: [Recipe] {
        Array(Set(slotsArray.flatMap { $0.plateRecipes }))
    }

    // MARK: - Methods

    /// Calendar used for `normalizeToMonday` and the deterministic-ID path.
    ///
    /// **Pinned to ISO 8601 (firstWeekday=Monday, minimumDaysInFirstWeek=4)
    /// with the device's CURRENT timezone** — not UTC.
    ///
    /// Why ISO 8601: guarantees fixed week semantics regardless of device
    /// locale. `Calendar.current` varies by region (US has firstWeekday=1,
    /// UK has firstWeekday=2, etc.), which caused the original divergence
    /// bug and multiple duplicate WeekPlan records in CloudKit.
    ///
    /// Why current timezone and NOT UTC: the user thinks about weeks in
    /// *local* time. "This week" for a user in BST means Mon Apr 6 00:00 BST
    /// through Sun Apr 12 23:59 BST. Stored as a Date, that Monday is
    /// `2026-04-05T23:00:00Z` — which in pure UTC is still Sunday evening of
    /// the *previous* ISO week. If we did the week computation in UTC, we'd
    /// place that Date into week 14 (Mar 30 - Apr 5) instead of week 15
    /// (Apr 6 - Apr 12) — shifting the whole plan one week earlier. That
    /// was the bug in build 9.
    ///
    /// Using the current timezone keeps the week-of-year calculation
    /// aligned with how the user sees their calendar. Two devices in the
    /// same physical location (same timezone) produce identical results.
    /// Devices in different timezones can still diverge for dates near
    /// Sun/Mon midnight, but household devices are virtually always
    /// co-located so this is an acceptable edge case.
    private static func makeNormalizingCalendar() -> Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .current
        return calendar
    }

    static func normalizeToMonday(_ date: Date) -> Date {
        let calendar = makeNormalizingCalendar()
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        var mondayComponents = DateComponents()
        mondayComponents.yearForWeekOfYear = components.yearForWeekOfYear
        mondayComponents.weekOfYear = components.weekOfYear
        mondayComponents.weekday = 2 // ISO weekday 2 = Monday
        mondayComponents.hour = 0
        mondayComponents.minute = 0
        mondayComponents.second = 0
        return calendar.date(from: mondayComponents) ?? date
    }

    func slots(for day: DayOfWeek) -> [MealSlot] {
        slotsArray.filter { $0.dayOfWeek == day }
            .sorted { $0.mealType.rawValue < $1.mealType.rawValue }
    }

    func slot(for day: DayOfWeek, mealType: MealType) -> MealSlot? {
        slotsArray.first { $0.dayOfWeek == day && $0.mealType == mealType }
    }

    // MARK: - Lazy Structure (#Change2)

    /// Fetches the plan covering `weekStartDate`, creating an empty (slotless)
    /// plan if none exists. Slots materialize individually when meals are
    /// planned into them — empty cells are UI affordances, not data.
    static func fetchOrCreate(for weekStartDate: Date, household: Household?, in context: NSManagedObjectContext) -> WeekPlan {
        let normalized = normalizeToMonday(weekStartDate)
        let request = NSFetchRequest<WeekPlan>(entityName: "WeekPlan")
        request.predicate = NSPredicate(format: "weekStartDate == %@", normalized as NSDate)
        request.fetchLimit = 1
        if let existing = (try? context.fetch(request))?.first {
            return existing
        }
        let plan = WeekPlan(context: context, weekStartDate: normalized)
        plan.household = household
        return plan
    }

    /// Returns the slot for (day, mealType), creating it on demand with its
    /// deterministic id — concurrent creation of the same cell on two devices
    /// converges to one duplicate group that the dedup engine collapses.
    func fetchOrCreateSlot(day: DayOfWeek, mealType: MealType, in context: NSManagedObjectContext) -> MealSlot {
        if let existing = slot(for: day, mealType: mealType) {
            return existing
        }
        let slotID = MealSlot.deterministicID(weekStartDate: weekStartDate, dayOfWeek: day, mealType: mealType)
        let newSlot = MealSlot(context: context, id: slotID, dayOfWeek: day, mealType: mealType)
        newSlot.weekPlan = self
        addToSlots(newSlot)
        modifiedAt = Date()
        return newSlot
    }

    func copyFrom(_ otherPlan: WeekPlan, by user: User) {
        guard let context = managedObjectContext else { return }
        // Only content-bearing slots are copied; destination slots materialize
        // on demand instead of silently dropping when absent (#Change2). Skip
        // flags are week-specific and not carried over.
        for otherSlot in otherPlan.slotsArray where otherSlot.isPlanned {
            let matchingSlot = fetchOrCreateSlot(day: otherSlot.dayOfWeek, mealType: otherSlot.mealType, in: context)
            if !otherSlot.recipesArray.isEmpty {
                matchingSlot.recipes = otherSlot.recipes
                matchingSlot.customMealName = nil
                matchingSlot.isSkipped = false
                matchingSlot.modifiedAt = Date()
                matchingSlot.modifiedBy = user
            } else if let customName = otherSlot.customMealName {
                matchingSlot.setCustomMeal(customName, by: user)
            }
            matchingSlot.servingsPlanned = otherSlot.servingsPlanned
            matchingSlot.archetype = otherSlot.archetype
            copyComponents(from: otherSlot, to: matchingSlot)
        }
        modifiedAt = Date()
    }

    /// Carries the source slot's plate components onto the destination, diffing by
    /// (kind, entity) rather than delete-then-recreate — so a repeated copy of the
    /// same week doesn't churn CloudKit records (MealSlotComponent is dedup-
    /// excluded, so delete-then-recreate with deterministic ids risks resurrection
    /// / bloat). Updates matching components in place, adds missing ones, removes
    /// only those no longer in the source.
    private func copyComponents(from source: MealSlot, to destination: MealSlot) {
        guard let context = managedObjectContext else { return }

        var destByEntity: [String: MealSlotComponent] = [:]
        for component in destination.storedComponents {
            if let entityID = component.entityID {
                destByEntity["\(component.kind):\(entityID.uuidString)"] = component
            }
        }

        var keptKeys = Set<String>()
        for component in source.storedComponents {
            guard let entityID = component.entityID else { continue }
            let key = "\(component.kind):\(entityID.uuidString)"
            keptKeys.insert(key)
            if let existing = destByEntity[key] {
                existing.portionScale = component.portionScale
                existing.quantity = component.quantity
                existing.unit = component.unit
                existing.portionLabel = component.portionLabel
                existing.modifiedAt = Date()
            } else {
                component.copy(to: destination, in: context)
            }
        }

        // Remove destination components the source no longer has.
        for (key, component) in destByEntity where !keptKeys.contains(key) {
            context.delete(component)
        }
    }

    func clearAll(by user: User) {
        for slot in slotsArray {
            slot.clear(by: user)
        }
        modifiedAt = Date()
    }

    func date(for day: DayOfWeek) -> Date {
        let daysToAdd = day.rawValue - 1
        return Calendar.current.date(byAdding: .day, value: daysToAdd, to: weekStartDate) ?? weekStartDate
    }

    // MARK: - Grocery List & Pantry

    var groceryItemsByCategory: [IngredientCategory: [GroceryItem]] {
        Dictionary(grouping: groceryItemsArray) { $0.category }
    }

    var uncheckedGroceryItems: [GroceryItem] { groceryItemsArray.filter { !$0.isChecked } }
    var checkedGroceryItems: [GroceryItem] { groceryItemsArray.filter { $0.isChecked } }

    var groceryProgress: Double {
        let items = groceryItemsArray
        guard !items.isEmpty else { return 0.0 }
        return Double(items.filter { $0.isChecked }.count) / Double(items.count)
    }

    var pantryCheckItems: [GroceryItem] { groceryItemsArray.filter { !$0.isManuallyAdded } }
    var inPantryItems: [GroceryItem] { groceryItemsArray.filter { $0.isInPantry } }
    var shoppingListItems: [GroceryItem] { groceryItemsArray.filter { $0.pantryChecked && !$0.isInPantry } }
    var unpurchasedShoppingItems: [GroceryItem] { groceryItemsArray.filter { $0.pantryChecked && !$0.isInPantry && !$0.isChecked } }

    var shoppingProgress: Double {
        let items = shoppingListItems
        guard !items.isEmpty else { return 0.0 }
        return Double(items.filter { $0.isChecked }.count) / Double(items.count)
    }

    var pantryCheckProgress: Double {
        let items = pantryCheckItems
        guard !items.isEmpty else { return 0.0 }
        return Double(items.filter { $0.isInPantry }.count) / Double(items.count)
    }

    // MARK: - Grocery List Generation

    func generateGroceryList(context: NSManagedObjectContext) {
        // Key derived items by (ingredient identity, unit). The same ingredient
        // measured in two units (e.g. grams in one recipe, tbsp in another) must
        // stay as two separate line items — there's no unit-conversion table to
        // combine them honestly. Ingredients with no linked Ingredient master fall
        // back to their free-text name so they aren't silently dropped.
        struct Key: Hashable {
            let identity: String
            let unit: MeasurementUnit
        }
        func identity(forIngredient ingredient: Ingredient?, name: String?) -> String? {
            if let ingredient { return ingredient.id.uuidString }
            let trimmed = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : "name:" + trimmed.lowercased()
        }

        var needed: [Key: (ingredient: Ingredient?, name: String?, quantity: Double, unit: MeasurementUnit, slots: [MealSlot])] = [:]
        for slot in plannedSlots {
            for item in slot.plateItems where item.kind == .recipe {
                guard let recipe = item.recipe else { continue }
                for ri in recipe.recipeIngredientsArray {
                    guard let id = identity(forIngredient: ri.ingredient, name: ri.customName) else { continue }
                    let key = Key(identity: id, unit: ri.unit)
                    let scaled = ri.scaledQuantity(originalServings: Int(recipe.servings), newServings: Int(slot.servingsPlanned)) * item.portionScale
                    if var entry = needed[key] {
                        entry.quantity += scaled
                        entry.slots.append(slot)
                        needed[key] = entry
                    } else {
                        needed[key] = (ri.ingredient, ri.customName, scaled, ri.unit, [slot])
                    }
                }
            }
        }

        // Index existing derived items by the same composite key.
        var existingByKey: [Key: GroceryItem] = [:]
        var duplicates: [GroceryItem] = []
        for item in groceryItemsArray where !item.isManuallyAdded {
            guard let id = identity(forIngredient: item.ingredient, name: item.customName) else { continue }
            let key = Key(identity: id, unit: item.unit)
            if existingByKey[key] == nil {
                existingByKey[key] = item
            } else {
                duplicates.append(item)
            }
        }

        // Update existing (preserving checked/pantry state) or create new.
        var keepKeys = Set<Key>()
        for (key, info) in needed {
            keepKeys.insert(key)
            if let existing = existingByKey[key] {
                existing.quantity = info.quantity
                existing.unit = info.unit
                existing.sourceSlots = NSSet(array: info.slots)
            } else if let ingredient = info.ingredient {
                let newItem = GroceryItem(context: context, ingredient: ingredient, quantity: info.quantity, unit: info.unit)
                newItem.sourceSlots = NSSet(array: info.slots)
                newItem.weekPlan = self
                addToGroceryItems(newItem)
            } else {
                // Unlinked ingredient — create a recipe-derived item from its free-text
                // name. The customName initializer marks items manually-added; clear
                // that so this still reconciles as a derived item on the next regenerate.
                let newItem = GroceryItem(context: context, customName: info.name ?? "Unknown Item", quantity: info.quantity, unit: info.unit, category: .other)
                newItem.isManuallyAdded = false
                newItem.pantryChecked = false
                newItem.sourceSlots = NSSet(array: info.slots)
                newItem.weekPlan = self
                addToGroceryItems(newItem)
            }
        }

        // Remove obsolete derived items.
        for (key, item) in existingByKey where !keepKeys.contains(key) {
            duplicates.append(item)
        }
        for item in duplicates {
            item.weekPlan = nil
            removeFromGroceryItems(item)
            context.delete(item)
        }

        modifiedAt = Date()
    }

    func cleanupOrphanedGroceryItems(context: NSManagedObjectContext) {
        let request = NSFetchRequest<GroceryItem>(entityName: "GroceryItem")
        request.predicate = NSPredicate(format: "weekPlan == nil AND isManuallyAdded == NO")
        if let orphans = try? context.fetch(request) {
            for item in orphans {
                context.delete(item)
            }
        }
    }

    // MARK: - NSSet Accessors

    @objc(addSlotsObject:)
    @NSManaged func addToSlots(_ value: MealSlot)

    @objc(removeSlotsObject:)
    @NSManaged func removeFromSlots(_ value: MealSlot)

    @objc(addGroceryItemsObject:)
    @NSManaged func addToGroceryItems(_ value: GroceryItem)

    @objc(removeGroceryItemsObject:)
    @NSManaged func removeFromGroceryItems(_ value: GroceryItem)

    // MARK: - Convenience Initializer

    /// Canonical ISO 8601 week key (e.g. "2026-W15") for a given Date.
    /// Independent of device timezone + calendar arithmetic quirks — two
    /// devices in the same local week produce the same string.
    ///
    /// This is the string that gets hashed into the deterministic UUID. It
    /// replaces the previous Date-based approach which was fragile across
    /// DST boundaries and device locale settings.
    static func isoWeekKey(for date: Date) -> String {
        let calendar = makeNormalizingCalendar()
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        let year = components.yearForWeekOfYear ?? 0
        let week = components.weekOfYear ?? 0
        return String(format: "%04d-W%02d", year, week)
    }

    /// Deterministic ID for a week plan, derived from the canonical ISO week
    /// key (e.g. "weekplan:2026-W15") rather than a Date. Guarantees two
    /// devices generate the same UUID for the same week — no Date or
    /// timezone arithmetic in the ID path.
    static func deterministicID(for weekStartDate: Date) -> UUID {
        return UUID.deterministic(from: "weekplan:\(isoWeekKey(for: weekStartDate))")
    }

    @discardableResult
    convenience init(
        context: NSManagedObjectContext,
        id: UUID? = nil,
        weekStartDate: Date,
        householdNote: String? = nil
    ) {
        let entity = NSEntityDescription.entity(forEntityName: "WeekPlan", in: context)!
        self.init(entity: entity, insertInto: context)
        self.id = id ?? Self.deterministicID(for: weekStartDate)
        self.weekStartDate = Self.normalizeToMonday(weekStartDate)
        self.householdNote = householdNote
        self.createdAt = Date()
        self.modifiedAt = Date()
    }
}
