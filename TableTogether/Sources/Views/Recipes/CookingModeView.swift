import SwiftUI
import CoreData

/// Full-screen cooking mode for step-by-step recipe guidance
struct CookingModeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    var recipe: Recipe
    let servings: Int

    @State private var currentStepIndex: Int = 0
    @State private var completedSteps: Set<Int> = []
    @State private var checkedIngredients: Set<UUID> = []
    @State private var showingIngredients: Bool = false
    @State private var timerSeconds: Int = 0
    @State private var timerRunning: Bool = false
    @State private var showingTimerPicker: Bool = false
    @State private var timerTask: Task<Void, Never>?

    private var instructions: [String] {
        recipe.instructionsList
    }

    private var currentStep: String {
        guard currentStepIndex < instructions.count else { return "" }
        return instructions[currentStepIndex]
    }

    private var progress: Double {
        guard !instructions.isEmpty else { return 0 }
        return Double(completedSteps.count) / Double(instructions.count)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Progress bar
                    progressBar

                    // Main content
                    if showingIngredients {
                        ingredientsList
                    } else {
                        stepContent
                    }

                    // Bottom controls
                    bottomControls
                }
            }
            .navigationTitle(recipe.title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            #if os(iOS)
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Exit") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        showingIngredients.toggle()
                    } label: {
                        Image(systemName: showingIngredients ? "list.number" : "checklist")
                            .foregroundColor(.white)
                    }
                }
            }
            .sheet(isPresented: $showingTimerPicker) {
                TimerPickerSheet(seconds: $timerSeconds) {
                    timerRunning = true
                }
            }
            .onChange(of: timerRunning) { _, isRunning in
                if isRunning {
                    startTimer()
                } else {
                    stopTimer()
                }
            }
            .onDisappear {
                stopTimer()
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        VStack(spacing: 8) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 4)

                    Rectangle()
                        .fill(Color.green)
                        .frame(width: geometry.size.width * progress, height: 4)
                }
            }
            .frame(height: 4)

            HStack {
                Text("Step \(currentStepIndex + 1) of \(instructions.count)")
                    .font(AppTypography.caption)
                    .foregroundColor(.gray)

                Spacer()

                Text("\(completedSteps.count) completed")
                    .font(AppTypography.caption)
                    .foregroundColor(.gray)
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    // MARK: - Step Content

    private var stepContent: some View {
        VStack(spacing: 24) {
            Spacer()

            // Step indicator
            Text("STEP \(currentStepIndex + 1)")
                .font(AppTypography.headline)
                .fontWeight(.bold)
                .foregroundColor(.green)
                .tracking(2)

            // Step text
            ScrollView {
                Text(currentStep)
                    .font(AppTypography.title2)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            .frame(maxHeight: 300)

            // Timer display (if active)
            if timerSeconds > 0 || timerRunning {
                timerDisplay
            }

            Spacer()

            // Step navigation
            stepNavigation
        }
        .padding()
    }

    // MARK: - Timer Display

    private var timerDisplay: some View {
        VStack(spacing: 8) {
            Text(formatTime(timerSeconds))
                .font(AppTypography.fixed(64, weight: .thin, design: .monospaced))
                .foregroundColor(timerSeconds <= 10 && timerRunning ? .red : .white)

            HStack(spacing: 16) {
                Button {
                    timerRunning.toggle()
                } label: {
                    Image(systemName: timerRunning ? "pause.fill" : "play.fill")
                        .font(AppTypography.title2)
                        .foregroundColor(.white)
                        .frame(width: 50, height: 50)
                        .background(Color.gray.opacity(0.3))
                        .clipShape(Circle())
                }

                Button {
                    timerSeconds = 0
                    timerRunning = false
                } label: {
                    Image(systemName: "stop.fill")
                        .font(AppTypography.title2)
                        .foregroundColor(.white)
                        .frame(width: 50, height: 50)
                        .background(Color.gray.opacity(0.3))
                        .clipShape(Circle())
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Step Navigation

    private var stepNavigation: some View {
        HStack(spacing: 20) {
            // Previous button
            Button {
                withAnimation {
                    if currentStepIndex > 0 {
                        currentStepIndex -= 1
                    }
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(AppTypography.title)
                    .foregroundColor(currentStepIndex > 0 ? .white : .gray)
                    .frame(width: 60, height: 60)
                    .background(Color.gray.opacity(0.3))
                    .clipShape(Circle())
            }
            .disabled(currentStepIndex == 0)

            // Complete/Mark done button
            Button {
                withAnimation {
                    if completedSteps.contains(currentStepIndex) {
                        completedSteps.remove(currentStepIndex)
                    } else {
                        completedSteps.insert(currentStepIndex)
                        // Auto-advance to next step
                        if currentStepIndex < instructions.count - 1 {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                withAnimation {
                                    currentStepIndex += 1
                                }
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: completedSteps.contains(currentStepIndex) ? "checkmark.circle.fill" : "checkmark.circle")
                    .font(AppTypography.fixed(40))
                    .foregroundColor(completedSteps.contains(currentStepIndex) ? .green : .white)
                    .frame(width: 80, height: 80)
                    .background(completedSteps.contains(currentStepIndex) ? Color.green.opacity(0.2) : Color.gray.opacity(0.3))
                    .clipShape(Circle())
            }

            // Next button
            Button {
                withAnimation {
                    if currentStepIndex < instructions.count - 1 {
                        currentStepIndex += 1
                    }
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(AppTypography.title)
                    .foregroundColor(currentStepIndex < instructions.count - 1 ? .white : .gray)
                    .frame(width: 60, height: 60)
                    .background(Color.gray.opacity(0.3))
                    .clipShape(Circle())
            }
            .disabled(currentStepIndex == instructions.count - 1)
        }
    }

    // MARK: - Ingredients List

    private var ingredientsList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Ingredients")
                    .font(AppTypography.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal)

                Text("Tap to check off as you use them")
                    .font(AppTypography.caption)
                    .foregroundColor(.gray)
                    .padding(.horizontal)

                ForEach(recipe.sortedIngredients) { ingredient in
                    ingredientRow(ingredient)
                }
            }
            .padding(.vertical)
        }
    }

    private func ingredientRow(_ ingredient: RecipeIngredient) -> some View {
        let isChecked = checkedIngredients.contains(ingredient.id)

        return Button {
            withAnimation {
                if isChecked {
                    checkedIngredients.remove(ingredient.id)
                } else {
                    checkedIngredients.insert(ingredient.id)
                }
            }
        } label: {
            HStack(spacing: 16) {
                Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                    .font(AppTypography.title2)
                    .foregroundColor(isChecked ? .green : .gray)

                VStack(alignment: .leading, spacing: 4) {
                    Text(ingredient.displayName)
                        .font(AppTypography.body)
                        .foregroundColor(isChecked ? .gray : .white)
                        .strikethrough(isChecked)

                    Text(ingredient.formattedScaledQuantity(for: servings, baseServings: Int(recipe.servings)))
                        .font(AppTypography.caption)
                        .foregroundColor(.gray)
                }

                Spacer()

                if let note = ingredient.preparationNote, !note.isEmpty {
                    Text(note)
                        .font(AppTypography.caption)
                        .foregroundColor(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.2))
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            .background(isChecked ? Color.green.opacity(0.1) : Color.gray.opacity(0.15))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Bottom Controls

    private var bottomControls: some View {
        HStack(spacing: 24) {
            // Timer button
            Button {
                showingTimerPicker = true
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "timer")
                        .font(AppTypography.title2)
                    Text("Timer")
                        .font(AppTypography.caption)
                }
                .foregroundColor(.white)
            }

            Spacer()

            // Done cooking button
            if completedSteps.count == instructions.count {
                Button {
                    recipe.markAsCooked()
                    viewContext.saveWithLogging(context: "mark recipe cooked")
                    dismiss()
                } label: {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Done Cooking")
                    }
                    .font(AppTypography.headline)
                    .foregroundColor(.black)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.green)
                    .clipShape(Capsule())
                }
            }

            Spacer()

            // Servings indicator
            VStack(spacing: 4) {
                Text("\(servings)")
                    .font(AppTypography.title2)
                    .fontWeight(.semibold)
                Text("servings")
                    .font(AppTypography.caption)
            }
            .foregroundColor(.gray)
        }
        .padding()
        .background(Color.black.opacity(0.8))
    }

    // MARK: - Helpers

    private func formatTime(_ totalSeconds: Int) -> String {
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    // MARK: - Timer Management

    private func startTimer() {
        // Cancel any existing timer first
        timerTask?.cancel()

        // Create a new async timer task
        timerTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { break }
                guard timerSeconds > 0 else {
                    timerRunning = false
                    break
                }
                timerSeconds -= 1
                if timerSeconds == 0 {
                    timerRunning = false
                    // Could add haptic/sound notification here
                }
            }
        }
    }

    private func stopTimer() {
        timerTask?.cancel()
        timerTask = nil
    }
}

