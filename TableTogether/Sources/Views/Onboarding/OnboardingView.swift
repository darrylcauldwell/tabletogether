import SwiftUI
import SwiftData

/// Onboarding flow for first-time users
struct OnboardingView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var households: [Household]
    @Binding var isOnboardingComplete: Bool

    @State private var currentPage: Int = 0
    @State private var userName: String = ""
    @State private var selectedEmoji: String = ""

    // Bold, vibrant default color - a rich teal that works well with white text
    private let avatarColorHex = "34C759"

    var body: some View {
        VStack(spacing: 0) {
            // Page indicator
            HStack(spacing: 8) {
                ForEach(0..<4, id: \.self) { index in
                    Circle()
                        .fill(currentPage == index ? Color.accentColor : Color.gray.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.top, 20)

            TabView(selection: $currentPage) {
                // Page 1: Welcome
                welcomePage
                    .tag(0)

                // Page 2: Profile Setup
                profileSetupPage
                    .tag(1)

                // Page 3: Features Overview
                featuresPage
                    .tag(2)

                // Page 4: Get Started
                getStartedPage
                    .tag(3)
            }
            #if os(iOS)
            .tabViewStyle(.page(indexDisplayMode: .never))
            #endif
        }
        .background(Color.appBackground)
    }

    // MARK: - Welcome Page

    private var welcomePage: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "fork.knife.circle.fill")
                .font(.system(size: 100))
                .foregroundStyle(.linearGradient(
                    colors: [.green, .blue],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))

            VStack(spacing: 12) {
                Text("Welcome to TableTogether")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)

                Text("Plan meals together, shop smarter, and enjoy cooking with your household.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()

            Button {
                withAnimation {
                    currentPage = 1
                }
            } label: {
                Text("Get Started")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 40)
        }
    }

    // MARK: - Profile Setup Page

    private var profileSetupPage: some View {
        VStack(spacing: 24) {
            Spacer()

            Text("What's your name?")
                .font(.title)
                .fontWeight(.bold)

            Text("So others in your household know who you are.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            // Name Field
            TextField("Your name", text: $userName)
                .font(.title3)
                .multilineTextAlignment(.center)
                .padding()
                .background(Theme.Colors.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 48)

            Spacer()

            Button {
                withAnimation {
                    currentPage = 2
                }
            } label: {
                Text("Continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(userName.isEmpty ? Color.gray : Color.accentColor)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(userName.isEmpty)
            .padding(.horizontal, 32)
            .padding(.bottom, 40)
        }
    }

    // MARK: - Features Page

    private var featuresPage: some View {
        VStack(spacing: 32) {
            Spacer()

            Text("What You Can Do")
                .font(.title)
                .fontWeight(.bold)

            VStack(alignment: .leading, spacing: 24) {
                FeatureRow(
                    icon: "calendar",
                    iconColor: .blue,
                    title: "Plan Your Meals",
                    description: "Drag and drop recipes to plan your week"
                )

                FeatureRow(
                    icon: "cart.fill",
                    iconColor: .green,
                    title: "Smart Grocery Lists",
                    description: "Auto-generated shopping lists from your plan"
                )

                FeatureRow(
                    icon: "person.2.fill",
                    iconColor: .orange,
                    title: "Share with Family",
                    description: "Everyone sees updates in real-time"
                )

                FeatureRow(
                    icon: "chart.line.uptrend.xyaxis",
                    iconColor: .purple,
                    title: "Track Nutrition",
                    description: "Gentle insights on your eating patterns"
                )
            }
            .padding(.horizontal, 32)

            Spacer()

            Button {
                withAnimation {
                    currentPage = 3
                }
            } label: {
                Text("Almost There")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 40)
        }
    }

    // MARK: - Get Started Page

    private var getStartedPage: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.green)

            VStack(spacing: 12) {
                Text("You're All Set!")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Start by adding your first recipe or planning this week's meals.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()

            Button {
                completeOnboarding()
            } label: {
                Text("Start Planning")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 40)
        }
    }

    // MARK: - Actions

    private func completeOnboarding() {
        let household = households.first

        // Create the user
        let user = User(
            displayName: userName.isEmpty ? "Me" : userName,
            avatarEmoji: selectedEmoji,
            avatarColorHex: avatarColorHex
        )
        user.household = household
        modelContext.insert(user)

        // Create default archetypes
        for archetypeType in ArchetypeType.allCases {
            let archetype = MealArchetype(systemType: archetypeType)
            archetype.household = household
            modelContext.insert(archetype)
        }

        modelContext.saveWithLogging(context: "onboarding setup")

        // Mark onboarding as complete
        withAnimation {
            isOnboardingComplete = true
        }
    }
}

// MARK: - Feature Row

struct FeatureRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(iconColor)
                .frame(width: 44, height: 44)
                .background(iconColor.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)

                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    OnboardingView(isOnboardingComplete: .constant(false))
        .modelContainer(for: [User.self, MealArchetype.self], inMemory: true)
}
