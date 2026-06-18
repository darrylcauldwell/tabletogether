import SwiftUI
import CoreData

// MARK: - Planned Meal Row

/// Row for an auto-populated planned meal that hasn't been confirmed yet
struct PlannedMealRow: View {
    let log: PrivateMealLog
    let recipeLookup: RecipeMacroLookup
    let onConfirm: () -> Void
    let onSkip: () -> Void

    private var mealName: String {
        if let recipeID = log.recipeID,
           let name = recipeLookup.recipeName(for: recipeID) {
            return name
        } else if let quickName = log.quickLogName {
            return quickName
        }
        return "Planned meal"
    }

    private var mealTypeIcon: String {
        switch log.mealType {
        case .breakfast: return "sunrise"
        case .lunch: return "sun.max"
        case .dinner: return "moon.stars"
        case .snack: return "leaf"
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: mealTypeIcon)
                    .font(AppTypography.fixed(14))
                    .foregroundStyle(Theme.Colors.primary.opacity(0.6))
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(mealName)
                        .font(AppTypography.subheadline)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(1)

                    Text("From plan")
                        .font(AppTypography.caption2)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }

                Spacer()
            }

            HStack(spacing: 12) {
                Button(action: onConfirm) {
                    Text("Confirm")
                        .font(AppTypography.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .foregroundStyle(.white)
                        .background(Theme.Colors.primary)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Button(action: onSkip) {
                    Text("Skip")
                        .font(AppTypography.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .background(Color.systemGray6)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Spacer()
            }
            .padding(.leading, 36)
        }
        .padding(.vertical, 4)
        .background(Theme.Colors.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Skipped Meal Log Row

/// Row for a meal that was skipped - shown greyed out with strikethrough
struct SkippedMealLogRow: View {
    let log: PrivateMealLog
    let recipeLookup: RecipeMacroLookup

    private var mealName: String {
        if let recipeID = log.recipeID,
           let name = recipeLookup.recipeName(for: recipeID) {
            return name
        } else if let quickName = log.quickLogName {
            return quickName
        }
        return "Meal"
    }

    private var mealTypeIcon: String {
        switch log.mealType {
        case .breakfast: return "sunrise"
        case .lunch: return "sun.max"
        case .dinner: return "moon.stars"
        case .snack: return "leaf"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: mealTypeIcon)
                .font(AppTypography.fixed(14))
                .foregroundStyle(Theme.Colors.textSecondary.opacity(0.5))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(mealName)
                    .font(AppTypography.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .strikethrough()
                    .lineLimit(1)

                Text("Skipped")
                    .font(AppTypography.caption2)
                    .foregroundStyle(Theme.Colors.textSecondary.opacity(0.7))
            }

            Spacer()
        }
        .opacity(0.6)
        .padding(.vertical, 2)
    }
}

// MARK: - Meal Log Editor Sheet

/// Sheet for editing an existing meal log entry
struct MealLogEditorSheet: View {
    let log: PrivateMealLog
    var privateDataManager: PrivateDataManager?

    @Environment(\.dismiss) private var dismiss

    @State private var mealType: MealType
    @State private var servingsConsumed: Double
    @State private var quickLogName: String
    @State private var quickLogCalories: String
    @State private var quickLogProtein: String
    @State private var quickLogCarbs: String
    @State private var quickLogFat: String
    @State private var status: MealLogStatus

    init(log: PrivateMealLog, privateDataManager: PrivateDataManager?) {
        self.log = log
        self.privateDataManager = privateDataManager
        _mealType = State(initialValue: log.mealType)
        _servingsConsumed = State(initialValue: log.servingsConsumed)
        _quickLogName = State(initialValue: log.quickLogName ?? "")
        _quickLogCalories = State(initialValue: log.quickLogCalories.map { String($0) } ?? "")
        _quickLogProtein = State(initialValue: log.quickLogProtein.map { String($0) } ?? "")
        _quickLogCarbs = State(initialValue: log.quickLogCarbs.map { String($0) } ?? "")
        _quickLogFat = State(initialValue: log.quickLogFat.map { String($0) } ?? "")
        _status = State(initialValue: log.status)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Meal Type") {
                    Picker("Meal", selection: $mealType) {
                        ForEach(MealType.allCases, id: \.self) { type in
                            Text(type.rawValue.capitalized).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Status") {
                    Picker("Status", selection: $status) {
                        Text("Eaten").tag(MealLogStatus.consumed)
                        Text("Skipped").tag(MealLogStatus.skipped)
                    }
                    .pickerStyle(.segmented)
                }

                if log.isQuickLog {
                    Section("Meal Name") {
                        TextField("Meal name", text: $quickLogName)
                    }

                    Section("Nutrition") {
                        HStack {
                            Text("Calories")
                            Spacer()
                            TextField("cal", text: $quickLogCalories)
                                .multilineTextAlignment(.trailing)
                                #if os(iOS)
                                .keyboardType(.numberPad)
                                #endif
                                .frame(width: 80)
                        }
                        HStack {
                            Text("Protein (g)")
                            Spacer()
                            TextField("g", text: $quickLogProtein)
                                .multilineTextAlignment(.trailing)
                                #if os(iOS)
                                .keyboardType(.numberPad)
                                #endif
                                .frame(width: 80)
                        }
                        HStack {
                            Text("Carbs (g)")
                            Spacer()
                            TextField("g", text: $quickLogCarbs)
                                .multilineTextAlignment(.trailing)
                                #if os(iOS)
                                .keyboardType(.numberPad)
                                #endif
                                .frame(width: 80)
                        }
                        HStack {
                            Text("Fat (g)")
                            Spacer()
                            TextField("g", text: $quickLogFat)
                                .multilineTextAlignment(.trailing)
                                #if os(iOS)
                                .keyboardType(.numberPad)
                                #endif
                                .frame(width: 80)
                        }
                    }
                } else {
                    Section("Servings") {
                        HStack {
                            Text("Servings eaten")
                            Spacer()
                            #if os(iOS)
                            Stepper(
                                value: $servingsConsumed,
                                in: 0.25...10,
                                step: 0.25
                            ) {
                                Text(String(format: "%.2g", servingsConsumed))
                                    .foregroundStyle(.secondary)
                            }
                            #else
                            HStack(spacing: 12) {
                                Button { if servingsConsumed > 0.25 { servingsConsumed -= 0.25 } } label: {
                                    Image(systemName: "minus.circle.fill")
                                }
                                .buttonStyle(.plain)
                                Text(String(format: "%.2g", servingsConsumed))
                                Button { if servingsConsumed < 10 { servingsConsumed += 0.25 } } label: {
                                    Image(systemName: "plus.circle.fill")
                                }
                                .buttonStyle(.plain)
                            }
                            #endif
                        }
                    }
                }
            }
            .navigationTitle("Edit Entry")
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
                    Button("Save") {
                        saveChanges()
                        dismiss()
                    }
                }
            }
        }
    }

    private func saveChanges() {
        var updated = log
        updated.mealType = mealType
        updated.servingsConsumed = servingsConsumed
        updated.status = status

        if log.isQuickLog {
            updated.quickLogName = quickLogName.isEmpty ? nil : quickLogName
            updated.quickLogCalories = Int(quickLogCalories)
            updated.quickLogProtein = Int(quickLogProtein)
            updated.quickLogCarbs = Int(quickLogCarbs)
            updated.quickLogFat = Int(quickLogFat)
        }

        Task {
            await privateDataManager?.saveMealLog(updated)
        }
    }
}
