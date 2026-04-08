import SwiftUI
import CoreData

// MARK: - IngredientDetailView
//
// Edit a single Ingredient master record. Reachable from IngredientLibraryView
// (#59 Phase 6). Edits commit to the view context on save.
//
// The "Merge into another ingredient…" action is wired in #59 Phase 8.
// For now the button is present but disabled with a "coming soon" hint, so
// the layout is final and Phase 8 just turns it on.

struct IngredientDetailView: View {
    @ObservedObject var ingredient: Ingredient
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @State private var draftName: String = ""
    @State private var draftAliases: [String] = []
    @State private var draftCategory: IngredientCategory = .other
    @State private var draftDefaultUnit: MeasurementUnit = .gram
    @State private var draftCalories: String = ""
    @State private var draftProtein: String = ""
    @State private var draftCarbs: String = ""
    @State private var draftFat: String = ""

    @State private var newAliasText: String = ""
    @State private var hasLoaded: Bool = false

    private var recipesUsingThis: [Recipe] {
        Set(ingredient.recipeIngredientsArray.compactMap { $0.recipe })
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    var body: some View {
        Form {
            Section("Name") {
                TextField("Ingredient name", text: $draftName)
                    #if os(iOS)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled(false)
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
                Text("Future imports that match a name in this list will resolve to this ingredient. Stored normalised — case and whitespace are ignored.")
            }

            Section("Category & Unit") {
                Picker("Category", selection: $draftCategory) {
                    ForEach(IngredientCategory.allCases.sorted(by: { $0.sortOrder < $1.sortOrder }), id: \.self) { cat in
                        Label(cat.displayName, systemImage: cat.iconName).tag(cat)
                    }
                }
                Picker("Default unit", selection: $draftDefaultUnit) {
                    ForEach(MeasurementUnit.allCases) { unit in
                        Text(unit.displayName).tag(unit)
                    }
                }
            }

            Section {
                macroField("Calories per 100g", text: $draftCalories)
                macroField("Protein per 100g", text: $draftProtein)
                macroField("Carbs per 100g", text: $draftCarbs)
                macroField("Fat per 100g", text: $draftFat)
            } header: {
                Text("Nutrition")
            } footer: {
                Text("Optional. When set, the values are used for nutrition rollup across recipes that reference this ingredient.")
            }

            if !recipesUsingThis.isEmpty {
                Section("Used in \(recipesUsingThis.count) recipe\(recipesUsingThis.count == 1 ? "" : "s")") {
                    ForEach(recipesUsingThis, id: \.objectID) { recipe in
                        Text(recipe.title)
                            .lineLimit(1)
                    }
                }
            }

            Section {
                Button {
                    // Phase 8 — disabled until merge service ships
                } label: {
                    HStack {
                        Image(systemName: "arrow.triangle.merge")
                        Text("Merge into another ingredient…")
                        Spacer()
                        Text("Coming soon")
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
                .disabled(true)
            }
        }
        .navigationTitle(ingredient.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    save()
                    dismiss()
                }
                .disabled(draftName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .onAppear {
            guard !hasLoaded else { return }
            loadDraftFromIngredient()
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
        guard normalised != draftName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) else {
            // Don't allow alias to equal canonical name
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

    private func loadDraftFromIngredient() {
        draftName = ingredient.name
        draftAliases = ingredient.userAliasesList
        draftCategory = ingredient.category
        draftDefaultUnit = ingredient.defaultUnit
        draftCalories = ingredient.caloriesPer100g.map { String(format: "%g", $0.doubleValue) } ?? ""
        draftProtein = ingredient.proteinPer100g.map { String(format: "%g", $0.doubleValue) } ?? ""
        draftCarbs = ingredient.carbsPer100g.map { String(format: "%g", $0.doubleValue) } ?? ""
        draftFat = ingredient.fatPer100g.map { String(format: "%g", $0.doubleValue) } ?? ""
    }

    private func save() {
        let trimmedName = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName != ingredient.name {
            ingredient.updateName(trimmedName)
        }
        ingredient.userAliases = draftAliases
        ingredient.category = draftCategory
        ingredient.defaultUnit = draftDefaultUnit
        ingredient.caloriesPer100g = parseDouble(draftCalories).map { NSNumber(value: $0) }
        ingredient.proteinPer100g = parseDouble(draftProtein).map { NSNumber(value: $0) }
        ingredient.carbsPer100g = parseDouble(draftCarbs).map { NSNumber(value: $0) }
        ingredient.fatPer100g = parseDouble(draftFat).map { NSNumber(value: $0) }
        ingredient.modifiedAt = Date()

        viewContext.saveWithLogging(context: "edit Ingredient \(trimmedName)")
    }

    private func parseDouble(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return Double(trimmed)
    }
}
