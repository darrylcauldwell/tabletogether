import SwiftUI

// MARK: - Archetype Badge

struct ArchetypeBadge: View {
    let archetype: ArchetypeType
    var compact: Bool = false

    @ScaledMetric(relativeTo: .caption) private var horizontalPadding: CGFloat = 8
    @ScaledMetric(relativeTo: .caption) private var compactHorizontalPadding: CGFloat = 6
    @ScaledMetric(relativeTo: .caption) private var verticalPadding: CGFloat = 4

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: archetype.icon)
                .font(compact ? .caption2 : .caption)
            if !compact {
                Text(archetype.displayName)
                    .font(.caption)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, compact ? compactHorizontalPadding : horizontalPadding)
        .padding(.vertical, verticalPadding)
        .background(archetype.color.opacity(0.2))
        .foregroundStyle(archetype.color)
        .clipShape(Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(archetype.displayName) meal type")
    }
}

// MARK: - Macro Chip

struct MacroChip: View {
    let label: String
    let value: String
    let color: Color

    @ScaledMetric(relativeTo: .subheadline) private var horizontalPadding: CGFloat = 12
    @ScaledMetric(relativeTo: .subheadline) private var verticalPadding: CGFloat = 8

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(Theme.Colors.textPrimary)
            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .background(color.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}

// MARK: - Macro Summary Row

struct MacroSummaryRow: View {
    let summary: MacroSummary?
    var compact: Bool = false

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var isAccessibilitySize: Bool {
        dynamicTypeSize.isAccessibilitySize
    }

    private var accessibilityLabel: String {
        guard let summary = summary, summary.hasData else {
            return "Nutrition data unavailable"
        }
        var parts: [String] = []
        if summary.calories != nil {
            parts.append("Calories: \(summary.formattedCalories)")
        }
        if summary.protein != nil {
            parts.append("Protein: \(summary.formattedProtein)")
        }
        if !compact {
            if summary.carbs != nil {
                parts.append("Carbs: \(summary.formattedCarbs)")
            }
            if summary.fat != nil {
                parts.append("Fat: \(summary.formattedFat)")
            }
        }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        if let summary = summary, summary.hasData {
            // Use FlowLayout for accessibility sizes to allow wrapping
            Group {
                if isAccessibilitySize {
                    FlowLayout(spacing: compact ? 8 : 12) {
                        macroChips(summary: summary)
                    }
                } else {
                    HStack(spacing: compact ? 8 : 12) {
                        macroChips(summary: summary)
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
        } else {
            Text("Nutrition data unavailable")
                .font(.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }

    @ViewBuilder
    private func macroChips(summary: MacroSummary) -> some View {
        if summary.calories != nil {
            MacroChip(label: "Cal", value: summary.formattedCalories, color: .caloriesSoft)
        }
        if summary.protein != nil {
            MacroChip(label: "Protein", value: summary.formattedProtein, color: .proteinSoft)
        }
        if !compact {
            if summary.carbs != nil {
                MacroChip(label: "Carbs", value: summary.formattedCarbs, color: .carbsSoft)
            }
            if summary.fat != nil {
                MacroChip(label: "Fat", value: summary.formattedFat, color: .fatSoft)
            }
        }
    }
}

// MARK: - User Avatar

struct UserAvatar: View {
    let user: User
    var size: CGFloat = 32

    @ScaledMetric(relativeTo: .body) private var scaledSize: CGFloat = 32

    /// Computed initials from user's display name
    private var initials: String {
        let components = user.displayName.trimmingCharacters(in: .whitespaces).split(separator: " ")
        if components.isEmpty {
            return "?"
        } else if components.count == 1 {
            return String(components[0].prefix(1)).uppercased()
        } else {
            let first = String(components[0].prefix(1))
            let last = String(components[components.count - 1].prefix(1))
            return (first + last).uppercased()
        }
    }

    private var effectiveSize: CGFloat {
        // Use the larger of the provided size or the scaled size
        max(size, scaledSize)
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(hex: user.avatarColorHex))
                .frame(width: effectiveSize, height: effectiveSize)

            if user.avatarEmoji.isEmpty {
                Text(initials)
                    .font(.system(size: effectiveSize * 0.4, weight: .medium, design: .rounded))
                    .foregroundColor(.white)
            } else {
                Text(user.avatarEmoji)
                    .font(.system(size: effectiveSize * 0.6))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(user.displayName)
        .accessibilityAddTraits(.isImage)
    }
}

// MARK: - User Avatar Row

struct UserAvatarRow: View {
    let users: [User]
    var size: CGFloat = 24

    var body: some View {
        HStack(spacing: -8) {
            ForEach(users) { user in
                UserAvatar(user: user, size: size)
                    .overlay(Circle().stroke(Color.systemBackground, lineWidth: 2))
            }
        }
    }
}

// MARK: - Empty Slot Placeholder

struct EmptySlotPlaceholder: View {
    var mealType: MealType
    var onTap: () -> Void

    @ScaledMetric(relativeTo: .caption) private var minHeight: CGFloat = 80
    @ScaledMetric(relativeTo: .caption) private var spacing: CGFloat = 8

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: spacing) {
                Image(systemName: "plus.circle.dashed")
                    .font(.title2)
                    .foregroundStyle(Theme.Colors.textSecondary)
                Text("Add \(mealType.displayName)")
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity, minHeight: max(minHeight, 44)) // Ensure minimum touch target
            .background(Color.tertiarySystemBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5]))
                    .foregroundStyle(Color.separator)
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Add \(mealType.displayName)")
        .accessibilityHint("Double tap to add a meal")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Section Header

struct SectionHeader: View {
    let title: String
    var subtitle: String? = nil
    var action: (() -> Void)? = nil
    var actionLabel: String = "See All"

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            Spacer()
            if let action = action {
                Button(actionLabel, action: action)
                    .font(.subheadline)
                    .accessibilityLabel("\(actionLabel) for \(title)")
            }
        }
        .padding(.horizontal)
    }
}

// MARK: - Loading Indicator

struct LoadingView: View {
    var message: String = "Loading..."

    @ScaledMetric(relativeTo: .body) private var progressScale: CGFloat = 1.2

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(progressScale)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

// MARK: - Confirmation Dialog Helper

struct ConfirmationDialog: View {
    let title: String
    let message: String
    let confirmLabel: String
    let confirmRole: ButtonRole?
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .headline) private var outerSpacing: CGFloat = 20
    @ScaledMetric(relativeTo: .subheadline) private var innerSpacing: CGFloat = 8
    @ScaledMetric(relativeTo: .headline) private var buttonSpacing: CGFloat = 12

    private var isAccessibilitySize: Bool {
        dynamicTypeSize.isAccessibilitySize
    }

    var body: some View {
        VStack(spacing: outerSpacing) {
            VStack(spacing: innerSpacing) {
                Text(title)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }

            // Stack buttons vertically for accessibility sizes
            Group {
                if isAccessibilitySize {
                    VStack(spacing: buttonSpacing) {
                        Button(confirmLabel, role: confirmRole, action: onConfirm)
                            .buttonStyle(.borderedProminent)
                            .frame(maxWidth: .infinity)

                        Button("Cancel", action: onCancel)
                            .buttonStyle(.bordered)
                            .frame(maxWidth: .infinity)
                    }
                } else {
                    HStack(spacing: buttonSpacing) {
                        Button("Cancel", action: onCancel)
                            .buttonStyle(.bordered)

                        Button(confirmLabel, role: confirmRole, action: onConfirm)
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
        .padding()
        .cardStyle()
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Servings Adjuster

struct ServingsAdjuster: View {
    @Binding var servings: Int
    var minServings: Int = 1
    var maxServings: Int = 20

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .title3) private var buttonSpacing: CGFloat = 12
    @ScaledMetric(relativeTo: .title3) private var minTextWidth: CGFloat = 30

    private var isAccessibilitySize: Bool {
        dynamicTypeSize.isAccessibilitySize
    }

    var body: some View {
        // Use vertical layout for accessibility sizes
        Group {
            if isAccessibilitySize {
                VStack(spacing: buttonSpacing) {
                    servingsContent
                }
            } else {
                HStack(spacing: buttonSpacing) {
                    servingsContent
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(servings) \(servings == 1 ? "serving" : "servings")")
        .accessibilityValue("\(servings)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                if servings < maxServings { servings += 1 }
            case .decrement:
                if servings > minServings { servings -= 1 }
            @unknown default:
                break
            }
        }
    }

    @ViewBuilder
    private var servingsContent: some View {
        Button {
            if servings > minServings {
                servings -= 1
            }
        } label: {
            Image(systemName: "minus.circle.fill")
                .font(.title2)
                .foregroundStyle(servings > minServings ? Theme.Colors.primary : Theme.Colors.textSecondary)
                .frame(minWidth: 44, minHeight: 44) // Minimum touch target
        }
        .disabled(servings <= minServings)

        HStack(spacing: 4) {
            Text("\(servings)")
                .font(.title3)
                .fontWeight(.semibold)
                .frame(minWidth: minTextWidth)

            Text(servings == 1 ? "serving" : "servings")
                .font(.subheadline)
                .foregroundStyle(Theme.Colors.textSecondary)
        }

        Button {
            if servings < maxServings {
                servings += 1
            }
        } label: {
            Image(systemName: "plus.circle.fill")
                .font(.title2)
                .foregroundStyle(servings < maxServings ? Theme.Colors.primary : Theme.Colors.textSecondary)
                .frame(minWidth: 44, minHeight: 44) // Minimum touch target
        }
        .disabled(servings >= maxServings)
    }
}

// MARK: - Sync Status Indicator

/// A small indicator showing the current sync status
struct SyncStatusIndicator: View {
    let status: SyncStatus

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: status.iconName)
                .font(.caption)
                .foregroundStyle(iconColor)
                .symbolEffect(.pulse, options: .repeating, isActive: status == .syncing)

            if status != .synced {
                Text(status.displayName)
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Sync status: \(status.displayName)")
    }

    private var iconColor: Color {
        switch status {
        case .synced:
            return .green.opacity(0.8)
        case .syncing:
            return Theme.Colors.primary
        case .offline:
            return Theme.Colors.textSecondary
        case .error:
            return .orange
        }
    }
}

// MARK: - Sync Error Banner

/// A dismissible banner showing sync errors with an optional retry action
struct SyncErrorBanner: View {
    let error: PrivateDataManager.SyncError
    var onDismiss: () -> Void
    var onRetry: (() -> Void)?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .subheadline) private var padding: CGFloat = 16
    @ScaledMetric(relativeTo: .subheadline) private var spacing: CGFloat = 12

    private var isAccessibilitySize: Bool {
        dynamicTypeSize.isAccessibilitySize
    }

    var body: some View {
        Group {
            if isAccessibilitySize {
                VStack(alignment: .leading, spacing: spacing) {
                    HStack(spacing: spacing) {
                        Image(systemName: "exclamationmark.icloud")
                            .font(.body)
                            .foregroundStyle(.orange)
                            .accessibilityHidden(true)

                        Text(error.message)
                            .font(.subheadline)
                            .foregroundStyle(Theme.Colors.textPrimary)

                        Spacer()
                    }

                    HStack(spacing: spacing) {
                        if error.isRetryable, let onRetry = onRetry {
                            Button {
                                onRetry()
                            } label: {
                                Text("Retry")
                                    .font(.subheadline.weight(.medium))
                            }
                            .buttonStyle(.bordered)
                        }

                        Button {
                            onDismiss()
                        } label: {
                            Text("Dismiss")
                                .font(.subheadline.weight(.medium))
                        }
                        .buttonStyle(.bordered)
                    }
                }
            } else {
                HStack(spacing: spacing) {
                    Image(systemName: "exclamationmark.icloud")
                        .font(.body)
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)

                    Text(error.message)
                        .font(.subheadline)
                        .foregroundStyle(Theme.Colors.textPrimary)

                    Spacer()

                    if error.isRetryable, let onRetry = onRetry {
                        Button {
                            onRetry()
                        } label: {
                            Text("Retry")
                                .font(.subheadline.weight(.medium))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .frame(minWidth: 44, minHeight: 44) // Minimum touch target
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss")
                }
            }
        }
        .padding(padding)
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Sync error: \(error.message)")
        .accessibilityHint(error.isRetryable ? "Swipe up or down to access retry and dismiss actions" : "Swipe up or down to dismiss")
    }
}

// MARK: - Network Status Banner

/// A banner showing when the device is offline
struct OfflineBanner: View {
    @ObservedObject var networkMonitor: NetworkMonitor

    @ScaledMetric(relativeTo: .subheadline) private var padding: CGFloat = 16
    @ScaledMetric(relativeTo: .subheadline) private var spacing: CGFloat = 8

    var body: some View {
        if !networkMonitor.isConnected {
            HStack(spacing: spacing) {
                Image(systemName: "wifi.slash")
                    .font(.subheadline)
                    .accessibilityHidden(true)
                Text("You're offline. Changes will sync when reconnected.")
                    .font(.subheadline)
                Spacer()
            }
            .foregroundStyle(Theme.Colors.textSecondary)
            .padding(padding)
            .background(Color.secondary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Offline. Changes will sync when reconnected.")
            .accessibilityAddTraits(.isStaticText)
        }
    }
}

// MARK: - Flow Layout

/// A layout that arranges views in a horizontal flow, wrapping to the next line as needed
struct FlowLayout: Layout {
    var spacing: CGFloat

    init(spacing: CGFloat = 8) {
        self.spacing = spacing
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? 0, subviews: subviews, spacing: spacing)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            let point = CGPoint(
                x: bounds.minX + result.positions[index].x,
                y: bounds.minY + result.positions[index].y
            )
            subview.place(at: point, anchor: .topLeading, proposal: .unspecified)
        }
    }

    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []

        init(in width: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var rowHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)

                if x + size.width > width && x > 0 {
                    // Move to next row
                    x = 0
                    y += rowHeight + spacing
                    rowHeight = 0
                }

                positions.append(CGPoint(x: x, y: y))
                rowHeight = max(rowHeight, size.height)
                x += size.width + spacing
                self.size.width = max(self.size.width, x)
            }

            self.size.height = y + rowHeight
        }
    }
}
