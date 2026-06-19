import SwiftUI
import CoreData
import HealthKit
// MARK: - Meal Type Picker

struct MealTypePicker: View {
    @Binding var selectedType: MealType

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Meal")
                .font(AppTypography.subheadline)
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
                    .font(AppTypography.fixed(20))

                Text(type.rawValue.capitalized)
                    .font(AppTypography.caption)
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
                    .font(AppTypography.subheadline)
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
                            .font(AppTypography.fixed(16))
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
                    .font(AppTypography.subheadline)
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
                .font(AppTypography.caption)
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
                .font(AppTypography.caption2)
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
                .font(AppTypography.caption)
                .foregroundStyle(Color.slateGray)

            VStack(spacing: 4) {
                ForEach(estimate.components) { item in
                    HStack {
                        Text("\(item.quantity) \(item.name.lowercased())")
                            .font(AppTypography.caption)
                            .foregroundStyle(Color.slateGray)

                        Spacer()

                        if let cal = item.macros.calories {
                            Text("\(Int(cal.rounded())) cal")
                                .font(AppTypography.caption)
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
