import SwiftUI
import CoreData

// MARK: - WeekListView
//
// List-based week view. One row group per day, showing only the populated
// meal slots. Empty days get a minimal day header and a quiet "Add meal"
// affordance — no placeholder grid, no 28 always-visible buttons.
//
// Replaces WeekGridView + DayByDayView. Scales cleanly from iPhone to iPad
// to Mac Catalyst without size-class branching: a single vertical list
// reads well at any width.
//
// Per CLAUDE.md: "A well-designed household whiteboard... calm, unhurried,
// confidently quiet." The Paprika Week view was the direct inspiration,
// adapted to TableTogether's design system (no red/green semantic colours,
// sage primary for today, soft card style for populated slot rows).

struct WeekListView: View {
    let weekPlan: WeekPlan?
    let weekStartDate: Date
    let onSlotTapped: (MealSlot) -> Void
    let onRecipeDropped: (String, MealSlot) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(DayOfWeek.allCases.enumerated()), id: \.element) { index, day in
                    DayRowView(
                        day: day,
                        weekStartDate: weekStartDate,
                        slots: slotsForDay(day),
                        onSlotTapped: onSlotTapped,
                        onRecipeDropped: onRecipeDropped
                    )
                    if index < DayOfWeek.allCases.count - 1 {
                        Divider()
                            .padding(.horizontal)
                    }
                }
            }
        }
    }

    private func slotsForDay(_ day: DayOfWeek) -> [MealSlot] {
        weekPlan?.slotsArray
            .filter { $0.dayOfWeek == day }
            .sorted { $0.mealType.sortOrder < $1.mealType.sortOrder } ?? []
    }
}

// MARK: - DayRowView
//
// A single day in the week list. Always shows the day header. Shows populated
// meal slots as compact rows. Empty days get a subtle "No meals planned"
// caption. A single "+ Add meal" button at the bottom opens a meal-type
// picker menu.

struct DayRowView: View {
    let day: DayOfWeek
    let weekStartDate: Date
    let slots: [MealSlot]
    let onSlotTapped: (MealSlot) -> Void
    let onRecipeDropped: (String, MealSlot) -> Void

    @State private var showingAddMealMenu = false
    @State private var slotToPresent: MealSlot?

    private var dateForDay: Date {
        Calendar.current.date(byAdding: .day, value: day.rawValue - 1, to: weekStartDate) ?? weekStartDate
    }

    private var isToday: Bool {
        Calendar.current.isDateInToday(dateForDay)
    }

    private var dayNumber: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: dateForDay)
    }

    private var populatedSlots: [MealSlot] {
        slots.filter { $0.isPlanned }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if populatedSlots.isEmpty {
                Text("No meals planned")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary.opacity(0.7))
                    .italic()
                    .padding(.horizontal)
            } else {
                VStack(spacing: 6) {
                    ForEach(populatedSlots, id: \.objectID) { slot in
                        MealSlotListRow(
                            slot: slot,
                            onRecipeDropped: { recipeId in onRecipeDropped(recipeId, slot) }
                        )
                    }
                }
                .padding(.horizontal)
            }

            addMealButton
        }
        .padding(.vertical, 16)
        .background(isToday ? Theme.Colors.primary.opacity(0.04) : Color.clear)
        .sheet(item: $slotToPresent) { slot in
            RecipePickerSheet(slot: slot)
        }
    }

    // MARK: - Subviews

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(day.shortName.uppercased())
                .font(.caption)
                .fontWeight(.semibold)
                .tracking(0.5)
                .foregroundStyle(isToday ? Theme.Colors.primary : Theme.Colors.textSecondary)

            Text(dayNumber)
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundStyle(isToday ? Theme.Colors.primary : .primary)

            Spacer()
        }
        .padding(.horizontal)
    }

    private var addMealButton: some View {
        Button {
            showingAddMealMenu = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus.circle")
                    .font(.subheadline)
                Text("Add meal")
                    .font(.subheadline)
            }
            .foregroundStyle(Theme.Colors.textSecondary)
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
        .confirmationDialog(
            "Add meal to \(day.displayName)",
            isPresented: $showingAddMealMenu,
            titleVisibility: .visible
        ) {
            ForEach(MealType.allCases, id: \.self) { mealType in
                Button(mealTypeButtonLabel(mealType)) {
                    guard let slot = slots.first(where: { $0.mealType == mealType }) else { return }
                    slotToPresent = slot
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func mealTypeButtonLabel(_ mealType: MealType) -> String {
        let alreadyPlanned = slots.first { $0.mealType == mealType }?.isPlanned ?? false
        if alreadyPlanned {
            return "\(mealType.displayName) (replace)"
        }
        return mealType.displayName
    }
}

// MARK: - MealSlotListRow
//
// Compact horizontal row for a populated slot in the list view. Much leaner
// than the existing card-based MealSlotView — shows just the meal type label
// and the meal name(s). Tap opens the slot editor. Drop target for drag and
// drop recipe assignment is preserved.
//
// The richer details (archetype badge, assigned users, recipe thumbnail,
// recent-edit indicator) are intentionally omitted from the list. They
// surface in the MealSlotEditorSheet when the user taps in.

struct MealSlotListRow: View {
    @ObservedObject var slot: MealSlot
    let onRecipeDropped: (String) -> Void

    @State private var isTargeted: Bool = false
    @State private var showingEditor: Bool = false

    /// Display names for the slot, drawn from MealSlotComponents when present
    /// or from the legacy recipes relationship as a fallback.
    private var resolvedNames: [String] {
        let stored = slot.storedComponents
        if !stored.isEmpty {
            return stored.map(\.displayName)
        }
        return slot.recipesArray.map(\.title)
    }

    private var primaryLine: String {
        if let custom = slot.customMealName, !custom.isEmpty, resolvedNames.isEmpty {
            return custom
        }
        return resolvedNames.first ?? slot.customMealName ?? ""
    }

    private var secondaryLine: String? {
        let extras = Array(resolvedNames.dropFirst())
        guard !extras.isEmpty else { return nil }
        if extras.count <= 2 {
            return "+ " + extras.joined(separator: " + ")
        }
        return "+ \(extras.prefix(2).joined(separator: ", ")), +\(extras.count - 2) more"
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(slot.mealType.displayName)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.Colors.primary)
                .frame(width: 72, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(primaryLine)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if let secondaryLine {
                    Text(secondaryLine)
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(isTargeted ? Theme.Colors.primary.opacity(0.12) : Color.clear)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    isTargeted ? Theme.Colors.primary : Color.clear,
                    lineWidth: isTargeted ? 1.5 : 0
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onTapGesture {
            showingEditor = true
        }
        #if os(iOS)
        .dropDestination(for: String.self) { recipeIds, _ in
            guard let recipeId = recipeIds.first else { return false }
            onRecipeDropped(recipeId)
            return true
        } isTargeted: { targeted in
            withAnimation(.easeInOut(duration: 0.15)) {
                isTargeted = targeted
            }
        }
        #endif
        .sheet(isPresented: $showingEditor) {
            MealSlotEditorSheet(slot: slot)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(slot.mealType.displayName): \(slot.displayTitle)")
        .accessibilityHint("Tap to edit")
    }
}
