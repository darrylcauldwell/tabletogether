import SwiftUI
import CoreData

// MARK: - FoodItemMergePicker
//
// Sheet presented from FoodItemDetailView when the user taps "Merge into
// another food item…". Mirrors IngredientMergePicker; FoodItem has a
// shorter incoming-FK list (just MealSlotComponent.foodItem) so the
// confirmation message is correspondingly simpler (#59 Phase 8).

struct FoodItemMergePicker: View {
    let source: FoodItem
    let onMerged: (FoodItem) -> Void

    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @FetchRequest(
        sortDescriptors: [SortDescriptor(\.displayName)],
        animation: .default
    )
    private var allFoodItems: FetchedResults<FoodItem>

    @State private var searchText: String = ""
    @State private var selectedCanonical: FoodItem?
    @State private var preview: FoodItemMergeService.MergePreview?
    @State private var showingConfirmation = false
    @State private var errorMessage: String?

    private let mergeService = FoodItemMergeService()

    private var candidates: [FoodItem] {
        var result = allFoodItems.filter { $0 !== source && $0.household == source.household }
        if !searchText.isEmpty {
            let q = searchText.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            result = result.filter { item in
                item.normalizedName.contains(q) ||
                item.userAliasesList.contains(where: { $0.contains(q) })
            }
        }
        return result.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Choose the canonical food item. **\(source.displayName)** will be deleted and added as an alias on whichever item you pick.")
                        .font(AppTypography.subheadline)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }

                Section {
                    if candidates.isEmpty {
                        Text("No other food items to merge into.")
                            .foregroundStyle(Theme.Colors.textSecondary)
                    } else {
                        ForEach(candidates, id: \.objectID) { candidate in
                            Button {
                                selectedCanonical = candidate
                                preview = mergeService.preview(source: source, into: candidate)
                                showingConfirmation = true
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(candidate.displayName)
                                        .foregroundStyle(.primary)
                                    HStack(spacing: 6) {
                                        if let brand = candidate.brandOwner, !brand.isEmpty {
                                            Text(brand)
                                                .font(AppTypography.caption)
                                                .foregroundStyle(Theme.Colors.textSecondary)
                                        } else {
                                            Text(candidate.dataType)
                                                .font(AppTypography.caption)
                                                .foregroundStyle(Theme.Colors.textSecondary)
                                        }
                                        if !candidate.userAliasesList.isEmpty {
                                            Text("• \(candidate.userAliasesList.count) alias\(candidate.userAliasesList.count == 1 ? "" : "es")")
                                                .font(AppTypography.caption)
                                                .foregroundStyle(Theme.Colors.textSecondary)
                                        }
                                    }
                                }
                            }
                        }
                    }
                } header: {
                    Text("\(candidates.count) candidate\(candidates.count == 1 ? "" : "s")")
                }
            }
            .searchable(text: $searchText, prompt: "Search food items")
            .navigationTitle("Merge Into…")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert(
                "Confirm Merge",
                isPresented: $showingConfirmation,
                presenting: preview
            ) { _ in
                Button("Merge", role: .destructive) {
                    runMerge()
                }
                Button("Cancel", role: .cancel) {
                    selectedCanonical = nil
                    preview = nil
                }
            } message: { preview in
                Text(confirmationMessage(for: preview))
            }
            .alert(
                "Merge Failed",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                ),
                presenting: errorMessage
            ) { _ in
                Button("OK") { errorMessage = nil }
            } message: { msg in
                Text(msg)
            }
        }
    }

    private func confirmationMessage(for preview: FoodItemMergeService.MergePreview) -> String {
        var lines: [String] = []
        lines.append("'\(preview.sourceName)' will be deleted and added as an alias on '\(preview.canonicalName)'.")
        if preview.mealSlotComponentCount > 0 {
            lines.append("\(preview.mealSlotComponentCount) meal slot\(preview.mealSlotComponentCount == 1 ? "" : "s") will be re-linked.")
        }
        if !preview.aliasesToTransfer.isEmpty {
            lines.append("\(preview.aliasesToTransfer.count) alias\(preview.aliasesToTransfer.count == 1 ? "" : "es") will be transferred.")
        }
        lines.append("This cannot be undone.")
        return lines.joined(separator: "\n\n")
    }

    private func runMerge() {
        guard let canonical = selectedCanonical else { return }
        do {
            try mergeService.merge(source: source, into: canonical)
            onMerged(canonical)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
