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

/// The cell a meal is being picked for. A plain value — presenting the picker
/// must not touch the model layer; the slot materializes only when a choice
/// lands (#Change2 regression fix: creating the slot inside the dialog action
/// re-rendered the planner mid-presentation and broke the sheet on Catalyst).
struct MealPickerTarget: Identifiable {
    let day: DayOfWeek
    let mealType: MealType
    var id: String { "\(day.rawValue)-\(mealType.rawValue)" }
}

struct WeekListView: View {
    let weekPlan: WeekPlan?
    let weekStartDate: Date
    /// Reveals the current week's already-gone days (set by stepping the week
    /// navigation backwards from the default remaining-days view).
    let showsPastDays: Bool
    let onSlotTapped: (MealSlot) -> Void
    let onRecipeDropped: (String, MealSlot) -> Void
    /// Applies the picked meal to (day, mealType) — the owner materializes the
    /// plan and slot on demand and saves.
    let onMealChosen: (DayOfWeek, MealType, MealChoice) -> Void
    /// Clears a planned meal added in error, returning the cell to empty.
    let onRemoveMeal: (MealSlot) -> Void

    /// The current week defaults to today onward; past/future weeks (and the
    /// revealed state) show the full grid.
    private var visibleDays: [DayOfWeek] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let weekStart = calendar.startOfDay(for: weekStartDate)
        guard !showsPastDays,
              let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart),
              today >= weekStart, today < weekEnd else {
            return Array(DayOfWeek.allCases)
        }
        return DayOfWeek.remainingInCurrentWeek
    }

    // Sheet state lives at the WeekListView level — outside the LazyVStack —
    // so that row recycling and confirmationDialog dismiss-timing on iOS
    // can't cause the picker to oscillate open/close. See issue #62.
    @State private var pickerTarget: MealPickerTarget?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(visibleDays.enumerated()), id: \.element) { index, day in
                    DayRowView(
                        day: day,
                        weekStartDate: weekStartDate,
                        slots: slotsForDay(day),
                        pickerTarget: $pickerTarget,
                        onSlotTapped: onSlotTapped,
                        onRecipeDropped: onRecipeDropped,
                        onRemoveMeal: onRemoveMeal
                    )
                    if index < visibleDays.count - 1 {
                        Divider()
                            .padding(.horizontal)
                    }
                }
            }
        }
        .sheet(item: $pickerTarget) { target in
            RecipePickerSheet { choice in
                onMealChosen(target.day, target.mealType, choice)
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
    @Binding var pickerTarget: MealPickerTarget?
    let onSlotTapped: (MealSlot) -> Void
    let onRecipeDropped: (String, MealSlot) -> Void
    let onRemoveMeal: (MealSlot) -> Void

    @State private var showingAddMealMenu = false

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
                    .font(AppTypography.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary.opacity(0.7))
                    .italic()
                    .padding(.horizontal)
            } else {
                VStack(spacing: 6) {
                    ForEach(populatedSlots, id: \.objectID) { slot in
                        MealSlotListRow(
                            slot: slot,
                            onRecipeDropped: { recipeId in onRecipeDropped(recipeId, slot) },
                            onRemove: { onRemoveMeal(slot) }
                        )
                    }
                }
                .padding(.horizontal)
            }

            addMealButton
        }
        .padding(.vertical, 16)
        .background(isToday ? Theme.Colors.primary.opacity(0.04) : Color.clear)
    }

    // MARK: - Subviews

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(day.shortName.uppercased())
                .font(AppTypography.caption)
                .fontWeight(.semibold)
                .tracking(0.5)
                .foregroundStyle(isToday ? Theme.Colors.primary : Theme.Colors.textSecondary)

            Text(dayNumber)
                .font(AppTypography.title2)
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
                    .font(AppTypography.subheadline)
                Text("Add meal")
                    .font(AppTypography.subheadline)
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
                    // A plain value — the slot materializes only when a meal
                    // choice lands, never at presentation time (#Change2).
                    pickerTarget = MealPickerTarget(day: day, mealType: mealType)
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
    let onRemove: () -> Void

    @State private var isTargeted: Bool = false
    @State private var showingEditor: Bool = false
    /// Horizontal drag offset for swipe-to-reveal delete. This view lives in a
    /// LazyVStack, not a List, so .swipeActions is unavailable — a drag gesture
    /// reveals a trailing Delete button instead.
    @State private var swipeOffset: CGFloat = 0
    private let deleteWidth: CGFloat = 88

    /// Display names for the slot, from the reconciled plate (components unioned
    /// with un-migrated legacy recipes).
    private var resolvedNames: [String] {
        slot.plateItems.map(\.displayName)
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

    private var rowContent: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(slot.mealType.displayName)
                .font(AppTypography.caption)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.Colors.primary)
                .frame(width: 72, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(primaryLine)
                    .font(AppTypography.body)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if let secondaryLine {
                    Text(secondaryLine)
                        .font(AppTypography.caption)
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
            if swipeOffset != 0 {
                withAnimation(.easeOut(duration: 0.2)) { swipeOffset = 0 }
            } else {
                showingEditor = true
            }
        }
    }

    private func removeMeal() {
        withAnimation(.easeOut(duration: 0.2)) { swipeOffset = 0 }
        onRemove()
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            // Revealed delete action behind the row.
            Button(role: .destructive, action: removeMeal) {
                Label("Delete", systemImage: "trash")
                    .font(AppTypography.caption)
                    .foregroundStyle(.white)
                    .frame(width: deleteWidth)
                    .frame(maxHeight: .infinity)
                    .background(Color.red)
            }
            .buttonStyle(.plain)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .opacity(swipeOffset < 0 ? 1 : 0)

            rowContent
                .background(Theme.Colors.background)
                .offset(x: swipeOffset)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 12)
                        .onChanged { value in
                            // Horizontal-only, left-swipe reveal.
                            if value.translation.width < 0 && abs(value.translation.width) > abs(value.translation.height) {
                                swipeOffset = max(value.translation.width, -deleteWidth)
                            }
                        }
                        .onEnded { value in
                            withAnimation(.easeOut(duration: 0.2)) {
                                swipeOffset = value.translation.width < -deleteWidth / 2 ? -deleteWidth : 0
                            }
                        }
                )
        }
        .contextMenu {
            Button(role: .destructive, action: onRemove) {
                Label("Remove Meal", systemImage: "trash")
            }
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
