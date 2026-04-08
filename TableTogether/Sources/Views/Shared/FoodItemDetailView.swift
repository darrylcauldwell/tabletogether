import SwiftUI
import CoreData

// MARK: - FoodItemDetailView
//
// Edit a single FoodItem master record. Reachable from FoodItemLibraryView
// (#59 Phase 7). Mirrors IngredientDetailView in structure.
//
// USDA-sourced fields (fdcId, usdaDescription, dataType) are read-only —
// they're objective metadata from Apple's USDA cache. Display name, aliases,
// brand owner (for user-created items), and nutrition values are editable.
//
// The "Merge into another food item…" action is wired in #59 Phase 8.

struct FoodItemDetailView: View {
    @ObservedObject var foodItem: FoodItem
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @State private var draftDisplayName: String = ""
    @State private var draftAliases: [String] = []
    @State private var draftBrandOwner: String = ""
    @State private var draftCalories: String = ""
    @State private var draftProtein: String = ""
    @State private var draftCarbs: String = ""
    @State private var draftFat: String = ""
    @State private var draftFiber: String = ""
    @State private var draftSugar: String = ""
    @State private var draftSodium: String = ""

    @State private var newAliasText: String = ""
    @State private var hasLoaded: Bool = false

    private var mealSlotComponents: [MealSlotComponent] {
        let raw = foodItem.mealSlotComponents?.allObjects as? [MealSlotComponent] ?? []
        return raw.sorted { lhs, rhs in
            let l = lhs.slot?.createdAt ?? .distantPast
            let r = rhs.slot?.createdAt ?? .distantPast
            return l < r
        }
    }

    private func mealSlotLabel(_ component: MealSlotComponent) -> String {
        guard let slot = component.slot else { return "(unknown)" }
        return "\(slot.dayOfWeek.displayName) — \(slot.mealType.displayName)"
    }

    var body: some View {
        Form {
            Section("Display Name") {
                TextField("Display name", text: $draftDisplayName)
                    #if os(iOS)
                    .textInputAutocapitalization(.words)
                    #endif
            }

            Section {
                ForEach(draftAliases, id: \.self) { alias in
                    HStack {
                        Text(alias)
                        Spacer()
                        Button {
                            draftAliases.removeAll { $0 == alias }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                    }
                }
                HStack {
                    TextField("Add alias", text: $newAliasText)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        #endif
                        .onSubmit { addAliasFromInput() }
                    Button {
                        addAliasFromInput()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(Theme.Colors.primary)
                    }
                    .buttonStyle(.plain)
                    .disabled(newAliasText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                Text("Aliases")
            } footer: {
                Text("Future meal log entries that match a name in this list will resolve to this food item. Stored normalised — case and whitespace are ignored.")
            }

            if foodItem.dataType == "Branded" || foodItem.brandOwner?.isEmpty == false {
                Section("Brand") {
                    TextField("Brand", text: $draftBrandOwner)
                        #if os(iOS)
                        .textInputAutocapitalization(.words)
                        #endif
                }
            }

            Section {
                macroField("Calories per 100g", text: $draftCalories)
                macroField("Protein per 100g", text: $draftProtein)
                macroField("Carbs per 100g", text: $draftCarbs)
                macroField("Fat per 100g", text: $draftFat)
                macroField("Fiber per 100g", text: $draftFiber)
                macroField("Sugar per 100g", text: $draftSugar)
                macroField("Sodium mg per 100g", text: $draftSodium)
            } header: {
                Text("Nutrition")
            } footer: {
                Text("Used for meal-log nutrition rollup. USDA-sourced values can be overridden when needed.")
            }

            // Read-only USDA metadata
            if foodItem.fdcId != 0 || !foodItem.usdaDescription.isEmpty {
                Section("USDA Metadata") {
                    if foodItem.fdcId != 0 {
                        HStack {
                            Text("FDC ID")
                            Spacer()
                            Text("\(foodItem.fdcId)")
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .monospacedDigit()
                        }
                    }
                    if !foodItem.dataType.isEmpty {
                        HStack {
                            Text("Source")
                            Spacer()
                            Text(foodItem.dataType)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                    }
                    if !foodItem.usdaDescription.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Description")
                                .font(.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                            Text(foodItem.usdaDescription)
                                .font(.callout)
                        }
                    }
                }
            }

            if !mealSlotComponents.isEmpty {
                Section("Used in \(mealSlotComponents.count) meal slot\(mealSlotComponents.count == 1 ? "" : "s")") {
                    ForEach(mealSlotComponents, id: \.objectID) { component in
                        Text(mealSlotLabel(component))
                            .font(.callout)
                    }
                }
            }

            Section {
                Button {
                    // Phase 8 — disabled until merge service ships
                } label: {
                    HStack {
                        Image(systemName: "arrow.triangle.merge")
                        Text("Merge into another food item…")
                        Spacer()
                        Text("Coming soon")
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
                .disabled(true)
            }
        }
        .navigationTitle(foodItem.displayName)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    save()
                    dismiss()
                }
                .disabled(draftDisplayName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .onAppear {
            guard !hasLoaded else { return }
            loadDraftFromFoodItem()
            hasLoaded = true
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func macroField(_ label: String, text: Binding<String>) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("optional", text: text)
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 80)
        }
    }

    private func addAliasFromInput() {
        let normalised = newAliasText
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalised.isEmpty else { return }
        guard normalised != draftDisplayName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) else {
            newAliasText = ""
            return
        }
        guard !draftAliases.contains(normalised) else {
            newAliasText = ""
            return
        }
        draftAliases.append(normalised)
        newAliasText = ""
    }

    private func loadDraftFromFoodItem() {
        draftDisplayName = foodItem.displayName
        draftAliases = foodItem.userAliasesList
        draftBrandOwner = foodItem.brandOwner ?? ""
        draftCalories = String(format: "%g", foodItem.caloriesPer100g)
        draftProtein = String(format: "%g", foodItem.proteinPer100g)
        draftCarbs = String(format: "%g", foodItem.carbsPer100g)
        draftFat = String(format: "%g", foodItem.fatPer100g)
        draftFiber = foodItem.fiberPer100g.map { String(format: "%g", $0.doubleValue) } ?? ""
        draftSugar = foodItem.sugarPer100g.map { String(format: "%g", $0.doubleValue) } ?? ""
        draftSodium = foodItem.sodiumMgPer100g.map { String(format: "%g", $0.doubleValue) } ?? ""
    }

    private func save() {
        let trimmedName = draftDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName != foodItem.displayName {
            foodItem.displayName = trimmedName
            foodItem.normalizedName = trimmedName.lowercased()
        }
        foodItem.userAliases = draftAliases
        let trimmedBrand = draftBrandOwner.trimmingCharacters(in: .whitespacesAndNewlines)
        foodItem.brandOwner = trimmedBrand.isEmpty ? nil : trimmedBrand

        if let value = parseDouble(draftCalories) { foodItem.caloriesPer100g = value }
        if let value = parseDouble(draftProtein)  { foodItem.proteinPer100g  = value }
        if let value = parseDouble(draftCarbs)    { foodItem.carbsPer100g    = value }
        if let value = parseDouble(draftFat)      { foodItem.fatPer100g      = value }
        foodItem.fiberPer100g    = parseDouble(draftFiber).map  { NSNumber(value: $0) }
        foodItem.sugarPer100g    = parseDouble(draftSugar).map  { NSNumber(value: $0) }
        foodItem.sodiumMgPer100g = parseDouble(draftSodium).map { NSNumber(value: $0) }

        viewContext.saveWithLogging(context: "edit FoodItem \(trimmedName)")
    }

    private func parseDouble(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return Double(trimmed)
    }
}
