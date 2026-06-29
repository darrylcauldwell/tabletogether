import SwiftUI
import CoreData

// MARK: - Editable Ingredient Item

extension RecipeEditorView {
    struct EditableIngredientItem: Identifiable, Equatable {
        let id: UUID
        var name: String
        var quantity: Double
        var unit: MeasurementUnit
        var preparationNote: String
        var isOptional: Bool

        init(
            id: UUID = UUID(),
            name: String = "",
            quantity: Double = 1,
            unit: MeasurementUnit = .piece,
            preparationNote: String = "",
            isOptional: Bool = false
        ) {
            self.id = id
            self.name = name
            self.quantity = quantity
            self.unit = unit
            self.preparationNote = preparationNote
            self.isOptional = isOptional
        }

        init(from recipeIngredient: RecipeIngredient) {
            self.id = recipeIngredient.id
            self.name = recipeIngredient.displayName
            self.quantity = recipeIngredient.quantity
            self.unit = recipeIngredient.unit
            self.preparationNote = recipeIngredient.preparationNote ?? ""
            self.isOptional = recipeIngredient.isOptional
        }
    }
}

// MARK: - Ingredient Parsing

enum IngredientParser {
    static func parse(_ text: String) -> RecipeEditorView.EditableIngredientItem {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Shared tokenizer: normalizes unicode fractions, converts imperial weights to
        // metric, and disambiguates the single-letter T/t (tablespoon vs teaspoon).
        let (quantity, unit, remainder) = ParserUtilities.parseLeadingQuantityAndUnit(trimmed)
        var name = remainder

        var preparationNote = ""
        if let commaIndex = name.firstIndex(of: ",") {
            preparationNote = String(name[name.index(after: commaIndex)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            name = String(name[..<commaIndex])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return RecipeEditorView.EditableIngredientItem(
            name: name, quantity: quantity, unit: unit, preparationNote: preparationNote
        )
    }

    static func parseFraction(_ string: String) -> Double {
        var total: Double = 0
        for component in string.components(separatedBy: " ") {
            if component.contains("/") {
                let parts = component.components(separatedBy: "/")
                if parts.count == 2,
                   let num = Double(parts[0]),
                   let den = Double(parts[1]),
                   den != 0 {
                    total += num / den
                }
            } else if let num = Double(component) {
                total += num
            }
        }
        return total > 0 ? total : 1
    }
}

// MARK: - Ingredient Editor Row

struct IngredientEditorRow: View {
    @Binding var ingredient: RecipeEditorView.EditableIngredientItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                // Quantity
                TextField("Qty", value: $ingredient.quantity, format: .number)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                    #endif
                    .frame(width: 50)

                // Unit picker
                Picker("Unit", selection: $ingredient.unit) {
                    ForEach(MeasurementUnit.allCases) { unit in
                        Text(unit.displayName).tag(unit)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 80)

                // Name
                TextField("Ingredient name", text: $ingredient.name)
            }

            HStack {
                TextField("Preparation note (e.g., diced)", text: $ingredient.preparationNote)
                    .font(AppTypography.caption)
                    .foregroundColor(.appTextSecondary)

                Toggle("Optional", isOn: $ingredient.isOptional)
                    #if os(iOS)
                    .toggleStyle(.switch)
                    .scaleEffect(0.8)
                    #endif
                    .labelsHidden()

                if ingredient.isOptional {
                    Text("Optional")
                        .font(AppTypography.caption)
                        .foregroundColor(.appTextSecondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Tag Chip

struct TagChip: View {
    let tag: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(tag)
                .font(AppTypography.caption)
                .foregroundColor(.appTextPrimary)

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(AppTypography.caption)
                    .foregroundColor(.appTextSecondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.systemGray5)
        .clipShape(Capsule())
    }
}

// MARK: - Archetype Toggle Chip

struct ArchetypeToggleChip: View {
    let archetype: ArchetypeType
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: archetype.icon)
                    .font(AppTypography.caption2)
                Text(archetype.displayName)
                    .font(AppTypography.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(isSelected ? Color.archetypeColor(for: archetype).opacity(0.2) : Color.systemGray6)
            .foregroundColor(isSelected ? Color.archetypeColor(for: archetype) : .appTextSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.archetypeColor(for: archetype) : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}
