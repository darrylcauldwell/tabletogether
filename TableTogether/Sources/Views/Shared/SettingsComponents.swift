import SwiftUI
import CoreData
import CloudKit
// MARK: - Sync Status Row

struct SyncStatusRow: View {
    private let persistenceController = PersistenceController.shared

    var body: some View {
        HStack {
            Text("iCloud Sync")
            Spacer()

            Image(systemName: "checkmark.icloud")
                .foregroundStyle(.green)

            Text(persistenceController.isSharing ? "Sharing with \(persistenceController.participantCount) people" : "Active")
                .font(AppTypography.subheadline)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }
}

// MARK: - Placeholder Views

struct DefaultArchetypesView: View {
    var body: some View {
        List {
            ForEach(ArchetypeType.allCases, id: \.self) { archetype in
                HStack {
                    Image(systemName: archetype.icon)
                        .foregroundStyle(archetype.color)
                        .frame(width: 30)
                    VStack(alignment: .leading) {
                        Text(archetype.displayName)
                        Text(archetype.description)
                            .font(AppTypography.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
            }
        }
        .navigationTitle("Meal Archetypes")
    }
}

struct IngredientDatabaseView: View {
    @FetchRequest(sortDescriptors: [SortDescriptor(\.name)]) private var ingredients: FetchedResults<Ingredient>

    var body: some View {
        List {
            ForEach(ingredients) { ingredient in
                HStack {
                    Circle()
                        .fill(ingredient.category.color)
                        .frame(width: 8, height: 8)
                    Text(ingredient.name)
                    Spacer()
                    if let cal = ingredient.caloriesPer100g {
                        Text("\(Int(cal)) cal/100g")
                            .font(AppTypography.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
            }
        }
        .navigationTitle("Ingredients")
    }
}

// MARK: - Nutrition Disclaimer View

struct NutritionDisclaimerView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Group {
                    Text("Nutrition Estimates")
                        .font(AppTypography.headline)
                        .foregroundStyle(Theme.Colors.textPrimary)

                    Text("Nutrition data in TableTogether is estimated using public food databases, including USDA FoodData Central and Open Food Facts. Estimates are generated through on-device language processing and database lookups.")
                        .font(AppTypography.subheadline)
                        .foregroundStyle(Theme.Colors.textSecondary)

                    Text("Estimates may vary from actual values due to preparation methods, portion sizes, regional product variations, and database coverage. All values should be considered approximate.")
                        .font(AppTypography.subheadline)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }

                Group {
                    Text("Not Medical Advice")
                        .font(AppTypography.headline)
                        .foregroundStyle(Theme.Colors.textPrimary)

                    Text("TableTogether is not a medical device and does not diagnose, treat, cure, or prevent any medical condition. The nutrition information provided is for general informational purposes only.")
                        .font(AppTypography.subheadline)
                        .foregroundStyle(Theme.Colors.textSecondary)

                    Text("Always consult a qualified healthcare professional before making changes to your diet, especially if you have a medical condition or specific dietary requirements.")
                        .font(AppTypography.subheadline)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }

                Group {
                    Text("Your Privacy")
                        .font(AppTypography.headline)
                        .foregroundStyle(Theme.Colors.textPrimary)

                    Text("Meal logs, nutrition targets, and personal insights are stored privately and never shared with other household members. If connected to Apple Health, nutrition data is written to HealthKit on your device.")
                        .font(AppTypography.subheadline)
                        .foregroundStyle(Theme.Colors.textSecondary)

                    Text("Food search queries sent to USDA and Open Food Facts are anonymous and not linked to your identity.")
                        .font(AppTypography.subheadline)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }

                Group {
                    Text("Data Sources")
                        .font(AppTypography.headline)
                        .foregroundStyle(Theme.Colors.textPrimary)

                    VStack(alignment: .leading, spacing: 8) {
                        dataSourceRow(
                            name: "USDA FoodData Central",
                            detail: "U.S. Department of Agriculture, public domain"
                        )
                        dataSourceRow(
                            name: "Open Food Facts",
                            detail: "Community database, Open Database License (ODbL)"
                        )
                        dataSourceRow(
                            name: "Apple Intelligence",
                            detail: "On-device processing, iOS 26+"
                        )
                    }
                }
            }
            .padding()
        }
        .background(Theme.Colors.background)
        .navigationTitle("Nutrition Disclaimer")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func dataSourceRow(name: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name)
                .font(AppTypography.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(Theme.Colors.textPrimary)
            Text(detail)
                .font(AppTypography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }
}
