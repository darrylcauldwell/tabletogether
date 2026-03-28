//
//  CookbookScannerSheet.swift
//  TableTogether
//
//  Sheet for scanning cookbook pages with the device camera, extracting text
//  via OCR, and importing the result as a structured recipe.
//

#if os(iOS)
import SwiftUI
import CoreData

struct CookbookScannerSheet: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @FetchRequest(sortDescriptors: []) private var households: FetchedResults<Household>

    @State private var service = CookbookScannerService()
    @State private var showingScanner = true
    @State private var editableTitle = ""
    @State private var editableServings = 4
    @State private var editableIngredients: [EditableIngredient] = []
    @State private var editableInstructions: [String] = []
    @State private var selectedArchetypes: Set<ArchetypeType> = []
    @State private var showingRawText = false

    struct EditableIngredient: Identifiable {
        let id = UUID()
        var original: ParsedIngredient
        var displayText: String
        var isIncluded: Bool = true
    }

    var body: some View {
        NavigationStack {
            Group {
                switch service.state {
                case .idle:
                    promptView
                case .recognizing:
                    recognizingView
                case .parsed:
                    reviewView
                case .error(let message):
                    errorView(message: message)
                }
            }
            .background(Color.appBackground)
            .navigationTitle("Scan Recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .fullScreenCover(isPresented: $showingScanner) {
                DocumentScannerView(
                    onScanComplete: { images in
                        showingScanner = false
                        Task {
                            await service.processScannedImages(images)
                            populateEditableFields()
                        }
                    },
                    onCancel: {
                        showingScanner = false
                        if service.state == .idle {
                            dismiss()
                        }
                    }
                )
                .ignoresSafeArea()
            }
        }
    }

    // MARK: - State Views

    private var promptView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 60))
                .foregroundColor(.appTextSecondary)
            Text("Position your camera over a cookbook page")
                .font(.body)
                .foregroundColor(.appTextSecondary)
            Button("Open Camera") {
                showingScanner = true
            }
            .buttonStyle(PrimaryButtonStyle())
            Spacer()
        }
        .padding()
    }

    private var recognizingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .scaleEffect(1.5)
            Text("Recognizing text...")
                .font(.subheadline)
                .foregroundColor(.appTextSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundColor(.appTextSecondary)
            Text(message)
                .font(.body)
                .foregroundColor(.appTextSecondary)
                .multilineTextAlignment(.center)
            Button("Try Again") {
                service.reset()
                showingScanner = true
            }
            .buttonStyle(PrimaryButtonStyle())
            Spacer()
        }
        .padding()
    }

    // MARK: - Review View

    private var reviewView: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Scanned pages with photo picker
                ScannedPagesCarousel(
                    pages: service.scannedPages,
                    selectedPhotoIndex: $service.selectedPhotoIndex
                )

                // Title
                titleSection

                // Servings
                servingsSection

                // Ingredients
                ingredientsSection

                // Instructions
                instructionsSection

                // Raw OCR text
                if case .parsed(let result) = service.state {
                    RawOCRTextSection(rawText: result.rawText, isExpanded: $showingRawText)
                }

                // Archetype selection
                archetypeSection

                // Action buttons
                actionButtons
            }
            .padding()
        }
    }

    // MARK: - Edit Sections

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Title")
                .font(.headline)
                .foregroundColor(.appTextPrimary)

            TextField("Recipe title", text: $editableTitle)
                .textFieldStyle(.plain)
                .padding()
                .background(Color.systemGray6)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private var servingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Servings")
                .font(.headline)
                .foregroundColor(.appTextPrimary)

            HStack {
                Stepper(value: $editableServings, in: 1...50) {
                    Text("\(editableServings) servings")
                        .font(.body)
                }
            }
            .padding()
            .background(Color.systemGray6)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private var ingredientsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Ingredients")
                    .font(.headline)
                    .foregroundColor(.appTextPrimary)

                Spacer()

                Text("\(editableIngredients.filter { $0.isIncluded }.count) items")
                    .font(.caption)
                    .foregroundColor(.appTextSecondary)
            }

            if editableIngredients.isEmpty {
                Text("No ingredients found. You can add them after importing.")
                    .font(.body)
                    .foregroundColor(.appTextSecondary)
                    .italic()
            } else {
                ForEach($editableIngredients) { $ingredient in
                    HStack {
                        Button {
                            ingredient.isIncluded.toggle()
                        } label: {
                            Image(systemName: ingredient.isIncluded ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(ingredient.isIncluded ? .appPrimary : .appTextSecondary)
                        }

                        TextField("Ingredient", text: $ingredient.displayText)
                            .font(.body)
                            .foregroundColor(ingredient.isIncluded ? .appTextPrimary : .appTextSecondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private var instructionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Instructions")
                    .font(.headline)
                    .foregroundColor(.appTextPrimary)

                Spacer()

                Text("\(editableInstructions.count) steps")
                    .font(.caption)
                    .foregroundColor(.appTextSecondary)
            }

            if editableInstructions.isEmpty {
                Text("No instructions found. You can add them after importing.")
                    .font(.body)
                    .foregroundColor(.appTextSecondary)
                    .italic()
            } else {
                ForEach(Array(editableInstructions.enumerated()), id: \.offset) { index, instruction in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(index + 1).")
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundColor(.appPrimary)
                            .frame(width: 24, alignment: .leading)

                        Text(instruction)
                            .font(.body)
                            .foregroundColor(.appTextPrimary)
                            .lineLimit(3)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var archetypeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recipe Type")
                .font(.headline)
                .foregroundColor(.appTextPrimary)

            Text("Select the types that best describe this recipe:")
                .font(.caption)
                .foregroundColor(.appTextSecondary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: 8) {
                ForEach(ArchetypeType.allCases) { archetype in
                    ArchetypeSelectionChip(
                        archetype: archetype,
                        isSelected: selectedArchetypes.contains(archetype),
                        action: {
                            if selectedArchetypes.contains(archetype) {
                                selectedArchetypes.remove(archetype)
                            } else {
                                selectedArchetypes.insert(archetype)
                            }
                        }
                    )
                }
            }
        }
        .padding()
        .cardStyle()
        .padding(.horizontal, -16)
        .padding(.horizontal)
    }

    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button {
                importRecipe()
            } label: {
                HStack {
                    Image(systemName: "checkmark.circle")
                    Text("Import Recipe")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(editableTitle.isEmpty)

            Button {
                service.reset()
                showingScanner = true
            } label: {
                HStack {
                    Image(systemName: "camera")
                    Text("Re-scan")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding(.top, 8)
    }

    // MARK: - Actions

    private func populateEditableFields() {
        guard case .parsed(let result) = service.state else { return }

        editableTitle = result.title
        editableIngredients = result.ingredients.map {
            EditableIngredient(original: $0, displayText: $0.displayString)
        }
        editableInstructions = result.instructions
    }

    private func importRecipe() {
        let recipe = Recipe(
            context: viewContext,
            title: editableTitle,
            servings: editableServings,
            instructions: editableInstructions,
            suggestedArchetypes: Array(selectedArchetypes),
            imageData: service.selectedPhotoData
        )

        let included = editableIngredients.filter { $0.isIncluded }
        for (index, editable) in included.enumerated() {
            let recipeIngredient = RecipeIngredient(
                context: viewContext,
                quantity: editable.original.quantity,
                unit: editable.original.unit,
                preparationNote: editable.original.preparationNote,
                isOptional: editable.original.isOptional,
                order: index,
                customName: editable.original.name
            )
            recipe.addToRecipeIngredients(recipeIngredient)
        }

        recipe.household = households.first

        AppLogger.scanner.info("Imported scanned recipe: \(editableTitle)")
        dismiss()
    }
}
#endif
