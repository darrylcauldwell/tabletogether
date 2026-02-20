import SwiftUI

// MARK: - Recipe View (Cooking Mode)
//
// Full-screen cooking experience designed for hands-free use.
// Large typography, high contrast, step-by-step layout.
//
// Features:
// - Step-by-step instructions (one at a time)
// - Ingredients panel (always visible)
// - Optional timer display
// - Focus-based navigation (Siri Remote)
// - Read-only (no editing on tvOS)

struct RecipeView: View {
    let recipe: Recipe
    let mealSlot: MealSlot?

    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedElement: FocusElement?

    @State private var currentStep: Int = 0
    @State private var showingIngredients = true
    @State private var activeTimers: [CookingTimer] = []
    @State private var isTimerRunning = false

    private enum FocusElement: Hashable {
        case previousStep
        case nextStep
        case toggleIngredients
        case startTimer
        case done
    }

    private var totalSteps: Int {
        recipe.instructions.count
    }

    private var currentInstruction: String {
        guard currentStep < recipe.instructions.count else {
            return "You're done! Enjoy your meal."
        }
        return recipe.instructions[currentStep]
    }

    private var isFirstStep: Bool { currentStep == 0 }
    private var isLastStep: Bool { currentStep >= totalSteps - 1 }
    private var isComplete: Bool { currentStep >= totalSteps }

    var body: some View {
        ZStack {
            // Background
            TVTheme.Colors.background.ignoresSafeArea()

            HStack(spacing: 0) {
                // Main cooking area
                cookingArea
                    .frame(maxWidth: .infinity)

                // Ingredients sidebar
                if showingIngredients {
                    ingredientsSidebar
                        .frame(width: 450)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
        }
        .onAppear {
            focusedElement = .nextStep
        }
    }

    // MARK: - Cooking Area

    private var cookingArea: some View {
        VStack(spacing: 0) {
            // Header with recipe info
            recipeHeader
                .padding(.horizontal, TVTheme.Spacing.xxl)
                .padding(.top, TVTheme.Spacing.xl)

            Spacer()

            // Main step display
            stepDisplay
                .padding(.horizontal, TVTheme.Spacing.xxl)

            Spacer()

            // Navigation controls
            navigationControls
                .padding(.horizontal, TVTheme.Spacing.xxl)
                .padding(.bottom, TVTheme.Spacing.xl)
        }
    }

    // MARK: - Recipe Header

    private var recipeHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: TVTheme.Spacing.sm) {
                Text(recipe.title)
                    .font(TVTheme.Typography.largeTitle)
                    .foregroundStyle(TVTheme.Colors.textPrimary)

                HStack(spacing: TVTheme.Spacing.lg) {
                    if let time = recipe.totalTimeMinutes {
                        TVTimeChip(minutes: time)
                    }

                    if mealSlot != nil, let archetype = recipe.suggestedArchetypes.first {
                        TVArchetypeBadge(archetype: archetype)
                    }

                    Text("\(recipe.servings) servings")
                        .font(TVTheme.Typography.callout)
                        .foregroundStyle(TVTheme.Colors.textSecondary)
                }
            }

            Spacer()

            // Progress
            TVStepProgress(currentStep: currentStep + 1, totalSteps: totalSteps)
                .frame(width: 350)
        }
    }

    // MARK: - Step Display

    private var stepDisplay: some View {
        VStack(spacing: TVTheme.Spacing.xl) {
            if isComplete {
                // Completion state
                VStack(spacing: TVTheme.Spacing.lg) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 120))
                        .foregroundStyle(TVTheme.Colors.positive)

                    Text("All done!")
                        .font(TVTheme.Typography.hero)
                        .foregroundStyle(TVTheme.Colors.textPrimary)

                    Text("Enjoy your \(recipe.title)")
                        .font(TVTheme.Typography.title3)
                        .foregroundStyle(TVTheme.Colors.textSecondary)
                }
            } else {
                // Current step
                VStack(spacing: TVTheme.Spacing.lg) {
                    // Step number badge
                    Text("\(currentStep + 1)")
                        .font(TVTheme.Typography.stepNumber)
                        .foregroundStyle(TVTheme.Colors.primary)
                        .frame(width: 80, height: 80)
                        .background(
                            Circle()
                                .fill(TVTheme.Colors.primary.opacity(0.15))
                        )

                    // Instruction text
                    Text(currentInstruction)
                        .font(TVTheme.Typography.bodyLarge)
                        .foregroundStyle(TVTheme.Colors.textPrimary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(8)
                        .frame(maxWidth: 900)
                }
            }

            // Active timers
            if !activeTimers.isEmpty {
                HStack(spacing: TVTheme.Spacing.lg) {
                    ForEach(activeTimers) { timer in
                        TimerDisplay(timer: timer)
                    }
                }
            }
        }
    }

    // MARK: - Navigation Controls

    private var navigationControls: some View {
        HStack(spacing: TVTheme.Spacing.xl) {
            // Previous step
            NavigationButton(
                title: "Previous",
                icon: "chevron.left",
                isEnabled: !isFirstStep
            ) {
                withAnimation(TVTheme.Animation.standard) {
                    currentStep = max(0, currentStep - 1)
                }
            }
            .focused($focusedElement, equals: .previousStep)
            .opacity(isFirstStep ? 0.3 : 1)
            .disabled(isFirstStep)

            Spacer()

            // Toggle ingredients
            NavigationButton(
                title: showingIngredients ? "Hide Ingredients" : "Show Ingredients",
                icon: "list.bullet"
            ) {
                withAnimation(TVTheme.Animation.smooth) {
                    showingIngredients.toggle()
                }
            }
            .focused($focusedElement, equals: .toggleIngredients)

            // Start timer (if applicable)
            if hasTimerInCurrentStep {
                NavigationButton(
                    title: "Start Timer",
                    icon: "timer",
                    accentColor: TVTheme.Colors.secondary
                ) {
                    startTimerForCurrentStep()
                }
                .focused($focusedElement, equals: .startTimer)
            }

            Spacer()

            if isComplete {
                // Done button
                NavigationButton(
                    title: "Done",
                    icon: "checkmark",
                    accentColor: TVTheme.Colors.positive
                ) {
                    dismiss()
                }
                .focused($focusedElement, equals: .done)
            } else {
                // Next step
                NavigationButton(
                    title: isLastStep ? "Finish" : "Next",
                    icon: "chevron.right",
                    accentColor: TVTheme.Colors.primary
                ) {
                    withAnimation(TVTheme.Animation.standard) {
                        currentStep += 1
                    }
                }
                .focused($focusedElement, equals: .nextStep)
            }
        }
    }

    // MARK: - Ingredients Sidebar

    private var ingredientsSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Text("Ingredients")
                .font(TVTheme.Typography.title3)
                .foregroundStyle(TVTheme.Colors.textPrimary)
                .padding(TVTheme.Spacing.lg)

            Divider()
                .background(TVTheme.Colors.glassBorder)

            // Ingredient list
            ScrollView {
                LazyVStack(alignment: .leading, spacing: TVTheme.Spacing.md) {
                    ForEach(recipe.sortedIngredients) { recipeIngredient in
                        IngredientRow(recipeIngredient: recipeIngredient)
                    }
                }
                .padding(TVTheme.Spacing.lg)
            }
        }
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
        )
    }

    // MARK: - Timer Logic

    private var hasTimerInCurrentStep: Bool {
        let instruction = currentInstruction.lowercased()
        return instruction.contains("minute") ||
               instruction.contains("hour") ||
               instruction.contains("timer")
    }

    private func startTimerForCurrentStep() {
        // Simple timer extraction (could be enhanced)
        let instruction = currentInstruction.lowercased()
        var minutes = 0

        if let range = instruction.range(of: #"(\d+)\s*minute"#, options: .regularExpression) {
            let match = instruction[range]
            if let num = Int(match.filter { $0.isNumber }) {
                minutes = num
            }
        }

        if minutes > 0 {
            let timer = CookingTimer(
                id: UUID(),
                label: "Step \(currentStep + 1)",
                targetDate: Date().addingTimeInterval(TimeInterval(minutes * 60))
            )
            activeTimers.append(timer)
        }
    }
}

// MARK: - Navigation Button

private struct NavigationButton: View {
    let title: String
    let icon: String
    var isEnabled: Bool = true
    var accentColor: Color = TVTheme.Colors.textPrimary
    let action: () -> Void

    @Environment(\.isFocused) private var isFocused

    var body: some View {
        Button(action: action) {
            HStack(spacing: TVTheme.Spacing.md) {
                Image(systemName: icon)
                    .font(TVTheme.Typography.headline)

                Text(title)
                    .font(TVTheme.Typography.headline)
            }
            .foregroundStyle(isFocused ? .white : accentColor)
            .padding(.horizontal, TVTheme.Spacing.lg)
            .padding(.vertical, TVTheme.Spacing.md)
            .background(
                Capsule()
                    .fill(isFocused ? accentColor : TVTheme.Colors.glassBackground)
            )
            .overlay(
                Capsule()
                    .strokeBorder(
                        isFocused ? .clear : accentColor.opacity(0.3),
                        lineWidth: 2
                    )
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(isFocused ? TVTheme.FocusScale.button : 1.0)
        .animation(TVTheme.Animation.focusIn, value: isFocused)
        .disabled(!isEnabled)
    }
}

// MARK: - Ingredient Row

private struct IngredientRow: View {
    let recipeIngredient: RecipeIngredient

    var body: some View {
        HStack(spacing: TVTheme.Spacing.md) {
            Circle()
                .fill(TVTheme.Colors.primary.opacity(0.3))
                .frame(width: 12, height: 12)

            VStack(alignment: .leading, spacing: TVTheme.Spacing.xs) {
                Text(recipeIngredient.ingredient?.name ?? "Unknown")
                    .font(TVTheme.Typography.body)
                    .foregroundStyle(TVTheme.Colors.textPrimary)

                Text(recipeIngredient.formattedQuantity)
                    .font(TVTheme.Typography.callout)
                    .foregroundStyle(TVTheme.Colors.textSecondary)
            }

            Spacer()
        }
        .padding(.vertical, TVTheme.Spacing.sm)
    }
}

// MARK: - Timer Display

private struct TimerDisplay: View {
    let timer: CookingTimer

    @State private var timeRemaining: TimeInterval = 0
    private let updateTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var isExpired: Bool { timeRemaining <= 0 }

    private var formattedTime: String {
        if isExpired { return "Done!" }

        let minutes = Int(timeRemaining) / 60
        let seconds = Int(timeRemaining) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var body: some View {
        VStack(spacing: TVTheme.Spacing.sm) {
            Text(timer.label)
                .font(TVTheme.Typography.subheadline)
                .foregroundStyle(TVTheme.Colors.textSecondary)

            Text(formattedTime)
                .font(TVTheme.Typography.timerSmall)
                .foregroundStyle(isExpired ? TVTheme.Colors.positive : TVTheme.Colors.textPrimary)
                .monospacedDigit()
        }
        .padding(TVTheme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: TVTheme.CornerRadius.medium)
                .fill(isExpired ? TVTheme.Colors.positive.opacity(0.2) : TVTheme.Colors.glassBackground)
        )
        .onReceive(updateTimer) { _ in
            timeRemaining = timer.targetDate.timeIntervalSinceNow
        }
        .onAppear {
            timeRemaining = timer.targetDate.timeIntervalSinceNow
        }
    }
}

// MARK: - Cooking Timer Model

struct CookingTimer: Identifiable {
    let id: UUID
    let label: String
    let targetDate: Date
}

#Preview("Recipe View") {
    Text("Recipe View Preview")
}
