import SwiftUI
import SwiftData

// MARK: - Preview Helpers

/// Safe preview container creation that won't crash Xcode previews
enum PreviewContainer {
    /// Creates a ModelContainer for previews with error handling
    /// Returns nil if creation fails, allowing previews to show placeholder content
    static func create(for types: any PersistentModel.Type...) -> ModelContainer? {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        do {
            return try ModelContainer(for: Schema(types), configurations: config)
        } catch {
            AppLogger.app.error("Preview container creation failed: \(error.localizedDescription)")
            return nil
        }
    }
}

/// A view that wraps preview content with a safe model container
struct PreviewWrapper<Content: View>: View {
    let types: [any PersistentModel.Type]
    let content: () -> Content

    @State private var container: ModelContainer?
    @State private var loadFailed = false

    init(for types: any PersistentModel.Type..., @ViewBuilder content: @escaping () -> Content) {
        self.types = types
        self.content = content
    }

    var body: some View {
        if let container = container {
            content()
                .modelContainer(container)
        } else if loadFailed {
            ContentUnavailableView(
                "Preview Unavailable",
                systemImage: "exclamationmark.triangle",
                description: Text("Failed to create preview container")
            )
        } else {
            ProgressView("Loading preview...")
                .task {
                    await loadContainer()
                }
        }
    }

    @MainActor
    private func loadContainer() async {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        do {
            container = try ModelContainer(for: Schema(types), configurations: config)
        } catch {
            AppLogger.app.error("Preview container failed: \(error.localizedDescription)")
            loadFailed = true
        }
    }
}

// MARK: - View Extension for Preview Container

extension View {
    /// Applies a safe model container for previews
    @ViewBuilder
    func previewModelContainer(for types: any PersistentModel.Type...) -> some View {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        if let container = try? ModelContainer(for: Schema(types), configurations: config) {
            self.modelContainer(container)
        } else {
            ContentUnavailableView(
                "Preview Unavailable",
                systemImage: "exclamationmark.triangle",
                description: Text("Failed to create model container")
            )
        }
    }
}
