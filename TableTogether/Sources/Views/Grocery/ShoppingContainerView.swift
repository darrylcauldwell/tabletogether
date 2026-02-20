import SwiftUI

/// Mode selection for the shopping container
enum ShoppingMode: String, CaseIterable {
    case pantryCheck
    case shoppingList
}

/// iPhone container that wraps PantryCheckView and GroceryListView
/// under a single tab with a segmented picker.
struct ShoppingContainerView: View {
    @State private var selectedMode: ShoppingMode = .shoppingList

    var body: some View {
        VStack(spacing: 0) {
            Picker("View", selection: $selectedMode) {
                Text("Pantry").tag(ShoppingMode.pantryCheck)
                Text("Shopping List").tag(ShoppingMode.shoppingList)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)

            switch selectedMode {
            case .pantryCheck:
                PantryCheckView()
            case .shoppingList:
                GroceryListView()
            }
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ShoppingContainerView()
    }
    .modelContainer(for: [WeekPlan.self, GroceryItem.self, Ingredient.self], inMemory: true)
}
