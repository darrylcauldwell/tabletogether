import SwiftUI
import CoreData
import HealthKit
// MARK: - Recent Meals Section

struct RecentMealItem: Identifiable {
    let id = UUID()
    let recipe: Recipe?
    let name: String?

    var displayName: String {
        recipe?.title ?? name ?? "Meal"
    }
}

struct RecentMealsSection: View {
    let recentMeals: [RecentMealItem]
    @Binding var selectedRecipe: Recipe?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent")
                .font(AppTypography.subheadline)
                .foregroundStyle(Color.slateGray)
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(recentMeals) { item in
                        RecentMealChip(
                            name: item.displayName,
                            isSelected: selectedRecipe?.id == item.recipe?.id && item.recipe != nil
                        ) {
                            if let recipe = item.recipe {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedRecipe = recipe
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

struct RecentMealChip: View {
    let name: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(AppTypography.caption)

                Text(name)
                    .font(AppTypography.subheadline)
                    .lineLimit(1)
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
    }
}

// MARK: - Recipe Selection List

struct RecipeSelectionList: View {
    let recipes: [Recipe]
    @Binding var selectedRecipe: Recipe?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recipes")
                .font(AppTypography.subheadline)
                .foregroundStyle(Color.slateGray)

            if recipes.isEmpty {
                Text("No recipes found")
                    .font(AppTypography.subheadline)
                    .foregroundStyle(Color.slateGray)
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: 8) {
                    ForEach(recipes) { recipe in
                        RecipeSelectionRow(
                            recipe: recipe,
                            isSelected: selectedRecipe?.id == recipe.id
                        ) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedRecipe = recipe
                            }
                        }
                    }
                }
            }
        }
    }
}

struct RecipeSelectionRow: View {
    let recipe: Recipe
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // Selection indicator
                ZStack {
                    Circle()
                        .stroke(isSelected ? Color.sageGreen : Color.slateGray.opacity(0.5), lineWidth: 2)
                        .frame(width: 22, height: 22)

                    if isSelected {
                        Circle()
                            .fill(Color.sageGreen)
                            .frame(width: 14, height: 14)
                    }
                }

                // Recipe info
                VStack(alignment: .leading, spacing: 2) {
                    Text(recipe.title)
                        .font(AppTypography.subheadline)
                        .foregroundStyle(Color.charcoal)
                        .lineLimit(1)

                    if let macros = recipe.macrosPerServing, let calories = macros.calories {
                        Text("\(Int(calories)) cal per serving")
                            .font(AppTypography.caption)
                            .foregroundStyle(Color.slateGray)
                    }
                }

                Spacer()

                // Time estimate
                if let totalTime = recipe.totalTimeMinutes {
                    Text("\(totalTime) min")
                        .font(AppTypography.caption)
                        .foregroundStyle(Color.slateGray)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.sageGreen.opacity(0.1) : Color.offWhite)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Double Servings Adjuster
// Note: Uses Double for half-serving increments, separate from ServingsAdjuster in Components.swift

struct DoubleServingsAdjuster: View {
    @Binding var servings: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Servings consumed")
                .font(AppTypography.subheadline)
                .foregroundStyle(Color.slateGray)

            HStack(spacing: 16) {
                Button {
                    if servings > 0.5 {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            servings -= 0.5
                        }
                    }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(AppTypography.fixed(32))
                        .foregroundStyle(Color.sageGreen)
                }
                .disabled(servings <= 0.5)

                Text(servingsText)
                    .font(AppTypography.title2)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.charcoal)
                    .frame(minWidth: 60)

                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        servings += 0.5
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(AppTypography.fixed(32))
                        .foregroundStyle(Color.sageGreen)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.offWhite)
        )
    }

    private var servingsText: String {
        if servings == 1.0 {
            return "1 serving"
        } else if servings == floor(servings) {
            return "\(Int(servings)) servings"
        } else {
            return String(format: "%.1f servings", servings)
        }
    }
}

#Preview {
    QuickLogSheet()
        .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
}
