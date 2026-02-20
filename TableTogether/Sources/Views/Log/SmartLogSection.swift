import SwiftUI
import SwiftData

/// "Describe it" meal logging UI.
/// Shows a text input for meal description, resolves ingredients,
/// displays ingredient chips with alternates, and shows macro totals.
struct SmartLogSection: View {
    @Environment(\.modelContext) private var modelContext

    @Binding var mealDescription: String
    @Binding var resolvedIngredients: [ResolvedIngredient]
    @Binding var isSmartEstimate: Bool

    @Query private var households: [Household]

    @StateObject private var parser = NaturalLanguageMealParser()
    @StateObject private var resolver = IngredientResolverService()

    @State private var isParsing = false
    @State private var showAssumptions = false
    @State private var selectedIngredientId: UUID?

    private var household: Household? {
        households.first
    }

    private var totalMacros: MacroSummary {
        resolvedIngredients.reduce(MacroSummary.zero) { $0.adding($1.macros) }
    }

    var body: some View {
        VStack(spacing: 16) {
            // Meal description input
            descriptionInput

            // Parse button
            parseButton

            // Quick Estimate label
            if isSmartEstimate && !resolvedIngredients.isEmpty {
                quickEstimateLabel
            }

            // Ingredient chips
            if !resolvedIngredients.isEmpty {
                ingredientChips
            }

            // Macro summary bar
            if totalMacros.hasData {
                macroSummaryBar
            }

            // How did we estimate?
            if !resolvedIngredients.isEmpty {
                assumptionsSection
            }
        }
    }

    // MARK: - Description Input

    private var descriptionInput: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("What did you eat?")
                .font(.subheadline)
                .foregroundStyle(Color.slateGray)

            TextField("e.g., grilled chicken with rice and broccoli", text: $mealDescription, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...3)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.offWhite)
                )
        }
    }

    // MARK: - Parse Button

    private var parseButton: some View {
        Button {
            Task {
                await performParsing()
            }
        } label: {
            HStack(spacing: 8) {
                if isParsing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 14))
                }

                Text(resolvedIngredients.isEmpty ? "Estimate nutrition" : "Re-estimate")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .foregroundStyle(Color.offWhite)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(mealDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isParsing
                          ? Color.slateGray.opacity(0.5) : Color.sageGreen)
            )
        }
        .disabled(mealDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isParsing)
        .buttonStyle(.plain)
    }

    // MARK: - Quick Estimate Label

    private var quickEstimateLabel: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.caption)
                .foregroundStyle(Color.sageGreen)

            Text("Quick Estimate")
                .font(.caption)
                .foregroundStyle(Color.slateGray)

            Spacer()
        }
    }

    // MARK: - Ingredient Chips

    private var ingredientChips: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ingredients")
                .font(.subheadline)
                .foregroundStyle(Color.slateGray)

            FlowLayout(spacing: 8) {
                ForEach(resolvedIngredients) { ingredient in
                    SmartIngredientChip(
                        ingredient: ingredient,
                        isSelected: selectedIngredientId == ingredient.id,
                        onTap: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                if selectedIngredientId == ingredient.id {
                                    selectedIngredientId = nil
                                } else {
                                    selectedIngredientId = ingredient.id
                                }
                            }
                        },
                        onSelectAlternate: { alternate in
                            selectAlternate(alternate, for: ingredient)
                        }
                    )
                }
            }
        }
    }

    // MARK: - Macro Summary Bar

    private var macroSummaryBar: some View {
        HStack(spacing: 0) {
            macroItem(label: "Cal", value: totalMacros.formattedCalories)
            Spacer()
            macroItem(label: "Protein", value: totalMacros.formattedProtein)
            Spacer()
            macroItem(label: "Carbs", value: totalMacros.formattedCarbs)
            Spacer()
            macroItem(label: "Fat", value: totalMacros.formattedFat)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.offWhite)
        )
    }

    private func macroItem(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(Color.charcoal)

            Text(label)
                .font(.caption2)
                .foregroundStyle(Color.slateGray)
        }
    }

    // MARK: - Assumptions Section

    private var assumptionsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showAssumptions.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: showAssumptions ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(Color.slateGray)

                    Text("How did we estimate?")
                        .font(.caption)
                        .foregroundStyle(Color.slateGray)

                    Spacer()
                }
            }
            .buttonStyle(.plain)

            if showAssumptions {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(resolvedIngredients) { ingredient in
                        HStack(alignment: .top, spacing: 8) {
                            Circle()
                                .fill(confidenceColor(ingredient.parsed.confidence))
                                .frame(width: 6, height: 6)
                                .padding(.top, 5)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(ingredient.displayName)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundStyle(Color.charcoal)

                                Text(ingredient.assumptionDescription)
                                    .font(.caption2)
                                    .foregroundStyle(Color.slateGray)
                            }
                        }
                    }
                }
                .padding(.top, 8)
                .padding(.leading, 4)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.offWhite)
        )
    }

    private func confidenceColor(_ confidence: ParseConfidence) -> Color {
        switch confidence {
        case .high: return Color.sageGreen
        case .medium: return Color.slateGray
        case .low: return Color.slateGray.opacity(0.5)
        }
    }

    // MARK: - Actions

    private func performParsing() async {
        isParsing = true
        selectedIngredientId = nil

        let result = await parser.parse(description: mealDescription)
        let resolved = await resolver.resolve(
            ingredients: result.ingredients,
            context: modelContext,
            household: household
        )

        withAnimation(.easeInOut(duration: 0.3)) {
            resolvedIngredients = resolved
            isSmartEstimate = result.isAIParsed || !resolved.isEmpty
        }

        isParsing = false
    }

    private func selectAlternate(_ alternate: FoodItemMatch, for ingredient: ResolvedIngredient) {
        guard let index = resolvedIngredients.firstIndex(where: { $0.id == ingredient.id }) else { return }

        // Save the user's correction as an alias on the alternate food item
        alternate.foodItem.addAlias(ingredient.parsed.name.lowercased())
        modelContext.saveWithLogging(context: "food alias")

        // Rebuild the resolved ingredient with the alternate food item
        let grams = GramConversionService.convertToGrams(
            quantity: ingredient.parsed.quantity,
            unit: ingredient.parsed.unit,
            foodName: alternate.foodItem.normalizedName,
            foodItem: alternate.foodItem
        )

        let macros: MacroSummary
        if let g = grams {
            macros = alternate.foodItem.macros(forGrams: g)
        } else if let portion = alternate.foodItem.commonPortions.first {
            let qty = ingredient.parsed.quantity ?? 1.0
            macros = alternate.foodItem.macros(forGrams: qty * portion.gramWeight)
        } else {
            macros = alternate.foodItem.macros(forGrams: 100)
        }

        // Build new alternates list (swap the old best match in)
        var newAlternates = ingredient.alternates.filter { $0.foodItem.id != alternate.foodItem.id }
        if let oldFoodItem = ingredient.foodItem {
            let oldScore = StringSimilarity.combinedScore(
                ingredient.parsed.name.lowercased(),
                oldFoodItem.normalizedName
            )
            newAlternates.insert(FoodItemMatch(foodItem: oldFoodItem, score: oldScore), at: 0)
        }

        let updated = ResolvedIngredient(
            parsed: ingredient.parsed,
            foodItem: alternate.foodItem,
            quantityInGrams: grams,
            macros: macros,
            alternates: Array(newAlternates.prefix(3)),
            source: ingredient.source
        )

        withAnimation(.easeInOut(duration: 0.2)) {
            resolvedIngredients[index] = updated
            selectedIngredientId = nil
        }
    }
}

// MARK: - Smart Ingredient Chip

struct SmartIngredientChip: View {
    let ingredient: ResolvedIngredient
    let isSelected: Bool
    let onTap: () -> Void
    let onSelectAlternate: (FoodItemMatch) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main chip
            Button(action: onTap) {
                HStack(spacing: 6) {
                    Text(ingredient.displayName)
                        .font(.subheadline)
                        .lineLimit(1)

                    if let cal = ingredient.macros.calories {
                        Text("\(Int(cal.rounded())) cal")
                            .font(.caption)
                            .foregroundStyle(isSelected ? Color.offWhite.opacity(0.8) : Color.slateGray)
                    }

                    if !ingredient.alternates.isEmpty {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8))
                            .foregroundStyle(isSelected ? Color.offWhite.opacity(0.8) : Color.slateGray)
                    }
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

            // Alternates dropdown
            if isSelected && !ingredient.alternates.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Refine this estimate")
                        .font(.caption2)
                        .foregroundStyle(Color.slateGray)
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                        .padding(.bottom, 4)

                    ForEach(ingredient.alternates) { alt in
                        Button {
                            onSelectAlternate(alt)
                        } label: {
                            HStack(spacing: 8) {
                                Text(alt.foodItem.displayName)
                                    .font(.caption)
                                    .foregroundStyle(Color.charcoal)
                                    .lineLimit(1)

                                Spacer()

                                Text("\(Int(alt.foodItem.caloriesPer100g.rounded())) cal/100g")
                                    .font(.caption2)
                                    .foregroundStyle(Color.slateGray)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.offWhite)
                        .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
                )
                .padding(.top, 4)
            }
        }
    }
}

