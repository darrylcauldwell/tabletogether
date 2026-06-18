import SwiftUI
import CoreData

// MARK: - IngredientMergePicker
//
// Sheet presented from IngredientDetailView when the user taps "Merge into
// another ingredient…". Lists all other ingredients in the same household,
// shows a preview when one is selected, and confirms before running the
// merge (#59 Phase 8).
//
// On successful merge:
//   - The sheet calls onMerged(canonical) with the canonical ingredient
//   - The presenter (IngredientDetailView) is responsible for dismissing
//     itself, since the source ingredient it was displaying no longer exists

struct IngredientMergePicker: View {
    let source: Ingredient
    let onMerged: (Ingredient) -> Void

    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @FetchRequest(
        sortDescriptors: [SortDescriptor(\.name)],
        animation: .default
    )
    private var allIngredients: FetchedResults<Ingredient>

    @State private var searchText: String = ""
    @State private var selectedCanonical: Ingredient?
    @State private var preview: IngredientMergeService.MergePreview?
    @State private var showingConfirmation = false
    @State private var errorMessage: String?

    private let mergeService = IngredientMergeService()

    private var candidates: [Ingredient] {
        var result = allIngredients.filter { $0 !== source && $0.household == source.household }
        if !searchText.isEmpty {
            let q = searchText.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            result = result.filter { ingredient in
                ingredient.normalizedName.contains(q) ||
                ingredient.userAliasesList.contains(where: { $0.contains(q) })
            }
        }
        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Choose the canonical ingredient. **\(source.name)** will be deleted and added as an alias on whichever ingredient you pick.")
                        .font(AppTypography.subheadline)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }

                Section {
                    if candidates.isEmpty {
                        Text("No other ingredients to merge into.")
                            .foregroundStyle(Theme.Colors.textSecondary)
                    } else {
                        ForEach(candidates, id: \.objectID) { candidate in
                            Button {
                                selectedCanonical = candidate
                                preview = mergeService.preview(source: source, into: candidate)
                                showingConfirmation = true
                            } label: {
                                HStack {
                                    Image(systemName: candidate.category.iconName)
                                        .font(AppTypography.body)
                                        .foregroundStyle(Theme.Colors.primary)
                                        .frame(width: 24)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(candidate.name)
                                            .foregroundStyle(.primary)
                                        if !candidate.userAliasesList.isEmpty {
                                            Text("\(candidate.userAliasesList.count) alias\(candidate.userAliasesList.count == 1 ? "" : "es")")
                                                .font(AppTypography.caption)
                                                .foregroundStyle(Theme.Colors.textSecondary)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(AppTypography.caption)
                                        .foregroundStyle(Theme.Colors.textSecondary)
                                }
                            }
                        }
                    }
                } header: {
                    Text("\(candidates.count) candidate\(candidates.count == 1 ? "" : "s")")
                }
            }
            .searchable(text: $searchText, prompt: "Search ingredients")
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

    private func confirmationMessage(for preview: IngredientMergeService.MergePreview) -> String {
        var lines: [String] = []
        lines.append("'\(preview.sourceName)' will be deleted and added as an alias on '\(preview.canonicalName)'.")
        if preview.totalReassignments > 0 {
            var refParts: [String] = []
            if preview.recipeIngredientCount > 0 {
                refParts.append("\(preview.recipeIngredientCount) recipe ingredient\(preview.recipeIngredientCount == 1 ? "" : "s")")
            }
            if preview.mealSlotComponentCount > 0 {
                refParts.append("\(preview.mealSlotComponentCount) meal slot\(preview.mealSlotComponentCount == 1 ? "" : "s")")
            }
            if preview.groceryItemCount > 0 {
                refParts.append("\(preview.groceryItemCount) grocery item\(preview.groceryItemCount == 1 ? "" : "s")")
            }
            lines.append("\(refParts.joined(separator: ", ")) will be re-linked.")
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
