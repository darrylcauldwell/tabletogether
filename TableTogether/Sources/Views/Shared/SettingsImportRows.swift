import SwiftUI
import CoreData
import CloudKit
// MARK: - Demo Data Toggle Row

struct DemoDataToggleRow: View {
    var demoDataManager: DemoDataManager
    @Binding var showingConfirmation: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label {
                    Text("Demo Data")
                } icon: {
                    Image(systemName: "theatermasks.fill")
                        .foregroundStyle(Theme.Colors.secondary)
                }

                Spacer()

                if demoDataManager.isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Toggle("", isOn: Binding(
                        get: { demoDataManager.isDemoDataEnabled },
                        set: { newValue in
                            if newValue {
                                // Turning on - no confirmation needed
                                Task {
                                    await demoDataManager.toggleDemoData()
                                }
                            } else {
                                // Turning off - show confirmation
                                showingConfirmation = true
                            }
                        }
                    ))
                    .labelsHidden()
                }
            }

            Text("Show sample data for testing")
                .font(AppTypography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)

            if let error = demoDataManager.errorMessage {
                Text(error)
                    .font(AppTypography.caption)
                    .foregroundStyle(.red)
            }
        }
        .disabled(demoDataManager.isLoading)
    }
}

// MARK: - Paprika Import Row
//
// Self-contained: owns its own file picker state and attaches the
// fileImporter directly to the row. Avoids stacking multiple fileImporter
// modifiers on SettingsView.body, which ran into SwiftUI's presentation-
// modifier stacking limits on Mac Catalyst (10+ modifiers on one view made
// tapping the import button do nothing). Fix for #59 follow-up regression.

struct PaprikaImportRow: View {
    var importer: PaprikaImporter
    let context: NSManagedObjectContext
    let household: Household?

    @State private var showingFilePicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if importer.isImporting {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text(importer.progress)
                        .font(AppTypography.subheadline)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            } else if let result = importer.result {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Import complete", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(AppTypography.subheadline)

                    Text("\(result.imported) imported, \(result.skipped) skipped")
                        .font(AppTypography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)

                    if !result.errors.isEmpty {
                        Text(result.errors.joined(separator: ". "))
                            .font(AppTypography.caption)
                            .foregroundStyle(.orange)
                    }
                }
            } else {
                Button {
                    showingFilePicker = true
                } label: {
                    Label("Import from Paprika 3", systemImage: "square.and.arrow.down")
                }
            }

            if let error = importer.errorMessage {
                Text(error)
                    .font(AppTypography.caption)
                    .foregroundStyle(.red)
            }
        }
        .disabled(importer.isImporting)
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.paprikaRecipes, .data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    Task {
                        await importer.importRecipes(
                            from: url,
                            context: context,
                            household: household
                        )
                    }
                }
            case .failure(let error):
                importer.errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - JSON Recipe Import Row
//
// Self-contained — see the note on PaprikaImportRow for why each row
// owns its own fileImporter instead of delegating to the parent view.

struct JSONRecipeImportRow: View {
    var importer: JSONRecipeImporter
    let context: NSManagedObjectContext
    let household: Household?

    @State private var showingFilePicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if importer.isImporting {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text(importer.progress)
                        .font(AppTypography.subheadline)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            } else if let result = importer.result {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Import complete", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(AppTypography.subheadline)

                    Text("\(result.imported) imported, \(result.skipped) skipped")
                        .font(AppTypography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)

                    if !result.errors.isEmpty {
                        Text(result.errors.joined(separator: ". "))
                            .font(AppTypography.caption)
                            .foregroundStyle(.orange)
                    }
                }
            } else {
                Button {
                    showingFilePicker = true
                } label: {
                    Label("Import Recipe JSON", systemImage: "doc.badge.plus")
                }
            }

            if let error = importer.errorMessage {
                Text(error)
                    .font(AppTypography.caption)
                    .foregroundStyle(.red)
            }
        }
        .disabled(importer.isImporting)
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    Task {
                        await importer.importRecipes(
                            from: url,
                            context: context,
                            household: household
                        )
                    }
                }
            case .failure(let error):
                importer.errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - JSON Food Item Import Row
//
// Self-contained — see the note on PaprikaImportRow.

struct JSONFoodItemImportRow: View {
    var importer: FoodItemImporter
    let context: NSManagedObjectContext
    let household: Household?

    @State private var showingFilePicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if importer.isImporting {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text(importer.progress)
                        .font(AppTypography.subheadline)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            } else if let result = importer.result {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Import complete", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(AppTypography.subheadline)

                    Text("\(result.imported) imported, \(result.skipped) skipped")
                        .font(AppTypography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)

                    if !result.errors.isEmpty {
                        Text(result.errors.joined(separator: ". "))
                            .font(AppTypography.caption)
                            .foregroundStyle(.orange)
                    }
                }
            } else {
                Button {
                    showingFilePicker = true
                } label: {
                    Label("Import Food Item JSON", systemImage: "doc.badge.plus")
                }
            }

            if let error = importer.errorMessage {
                Text(error)
                    .font(AppTypography.caption)
                    .foregroundStyle(.red)
            }
        }
        .disabled(importer.isImporting)
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    Task {
                        await importer.importFoodItems(
                            from: url,
                            context: context,
                            household: household
                        )
                    }
                }
            case .failure(let error):
                importer.errorMessage = error.localizedDescription
            }
        }
    }
}
