import SwiftUI
import SwiftData

// MARK: - SuggestionTrayView

/// Collapsible bottom panel showing recipe suggestions.
/// Contains "Your go-tos" row with familiar recipes and "Try something new" row.
struct SuggestionTrayView: View {
    @Binding var isExpanded: Bool
    let familiarRecipes: [Recipe]
    let newRecipes: [Recipe]

    @State private var selectedTab: SuggestionTab = .goTos

    enum SuggestionTab: String, CaseIterable {
        case goTos = "Your go-tos"
        case tryNew = "Try something new"
        case recent = "Recently used"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with expand/collapse toggle
            TrayHeaderView(isExpanded: $isExpanded)

            if isExpanded {
                VStack(spacing: 12) {
                    // Tab selector
                    TabSelectorView(selectedTab: $selectedTab, hasNewRecipes: !newRecipes.isEmpty)

                    // Content based on selected tab
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            switch selectedTab {
                            case .goTos:
                                if familiarRecipes.isEmpty {
                                    EmptySuggestionsView(message: "Cook more recipes to see your go-tos here")
                                } else {
                                    ForEach(familiarRecipes) { recipe in
                                        DraggableRecipeCard(recipe: recipe)
                                    }
                                }

                            case .tryNew:
                                if newRecipes.isEmpty {
                                    EmptySuggestionsView(message: "Add new recipes to your library to see suggestions here")
                                } else {
                                    ForEach(newRecipes) { recipe in
                                        DraggableRecipeCard(recipe: recipe, isNew: true)
                                    }
                                }

                            case .recent:
                                RecentRecipesContent(familiarRecipes: familiarRecipes)
                            }
                        }
                        .padding(.horizontal)
                    }
                    .frame(height: 100)
                }
                .padding(.vertical, 12)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .background(Color.systemGroupedBackground)
        .animation(.easeInOut(duration: 0.3), value: isExpanded)
    }
}

// MARK: - TrayHeaderView

struct TrayHeaderView: View {
    @Binding var isExpanded: Bool

    var body: some View {
        Button {
            withAnimation {
                isExpanded.toggle()
            }
        } label: {
            HStack {
                Text("Suggestions")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)

                Spacer()

                Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)

                Text(isExpanded ? "Hide" : "Show")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - TabSelectorView

struct TabSelectorView: View {
    @Binding var selectedTab: SuggestionTrayView.SuggestionTab
    let hasNewRecipes: Bool

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SuggestionTrayView.SuggestionTab.allCases, id: \.self) { tab in
                    TabButton(
                        title: tab.rawValue,
                        isSelected: selectedTab == tab,
                        showBadge: tab == .tryNew && hasNewRecipes
                    ) {
                        withAnimation {
                            selectedTab = tab
                        }
                    }
                }
            }
            .padding(.horizontal)
        }
    }
}

// MARK: - TabButton

struct TabButton: View {
    let title: String
    let isSelected: Bool
    let showBadge: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.caption)
                    .fontWeight(isSelected ? .semibold : .regular)

                if showBadge {
                    Image(systemName: "sparkles")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
            }
            .foregroundColor(isSelected ? .white : .primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor : Color.systemGray5)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - EmptySuggestionsView

struct EmptySuggestionsView: View {
    let message: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "lightbulb")
                .font(.title2)
                .foregroundColor(.secondary)

            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 80)
        .padding(.horizontal, 32)
    }
}

// MARK: - RecentRecipesContent

struct RecentRecipesContent: View {
    let familiarRecipes: [Recipe]

    private var recentRecipes: [Recipe] {
        familiarRecipes
            .filter { $0.lastCookedDate != nil }
            .sorted { ($0.lastCookedDate ?? .distantPast) > ($1.lastCookedDate ?? .distantPast) }
            .prefix(6)
            .map { $0 }
    }

    var body: some View {
        if recentRecipes.isEmpty {
            EmptySuggestionsView(message: "Recently cooked recipes will appear here")
        } else {
            ForEach(recentRecipes) { recipe in
                DraggableRecipeCard(recipe: recipe)
            }
        }
    }
}

// Note: SuggestionEngine service class is defined in Services/SuggestionEngine.swift
// Note: SuggestionResult is defined in SuggestionMemory.swift

// MARK: - Preview

private struct SuggestionTrayPreviewWrapper: View {
    @State private var isExpanded = true
    var familiarRecipes: [Recipe] = []
    var newRecipes: [Recipe] = []

    var body: some View {
        VStack {
            Spacer()
            SuggestionTrayView(
                isExpanded: $isExpanded,
                familiarRecipes: familiarRecipes,
                newRecipes: newRecipes
            )
        }
    }
}

#Preview {
    SuggestionTrayPreviewWrapper()
        .modelContainer(for: [Recipe.self, SuggestionMemory.self], inMemory: true)
}

struct SuggestionTrayView_WithContentPreview: PreviewProvider {
    static var previews: some View {
        let sampleRecipes: [Recipe] = (1...6).map { i in
            Recipe(
                title: "Recipe \(i)",
                summary: "A delicious recipe",
                servings: 4,
                prepTimeMinutes: 15,
                cookTimeMinutes: 30,
                instructions: ["Step 1", "Step 2"],
                isFavorite: i == 1,
                timesCooked: i * 2,
                lastCookedDate: Date().addingTimeInterval(TimeInterval(-i * 86400))
            )
        }

        SuggestionTrayPreviewWrapper(
            familiarRecipes: Array(sampleRecipes.prefix(4)),
            newRecipes: Array(sampleRecipes.suffix(2))
        )
        .modelContainer(for: [Recipe.self, SuggestionMemory.self], inMemory: true)
    }
}
