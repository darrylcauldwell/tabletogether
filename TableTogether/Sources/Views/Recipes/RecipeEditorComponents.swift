import SwiftUI
import SwiftData

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
                    .font(.caption)
                    .foregroundColor(.appTextSecondary)

                Toggle("Optional", isOn: $ingredient.isOptional)
                    #if os(iOS)
                    .toggleStyle(.switch)
                    .scaleEffect(0.8)
                    #endif
                    .labelsHidden()

                if ingredient.isOptional {
                    Text("Optional")
                        .font(.caption)
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
                .font(.caption)
                .foregroundColor(.appTextPrimary)

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
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
                    .font(.caption2)
                Text(archetype.displayName)
                    .font(.caption)
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
