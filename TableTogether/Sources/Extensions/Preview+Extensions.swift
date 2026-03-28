import SwiftUI
import CoreData

// MARK: - Preview Helpers

/// Safe preview container using PersistenceController.preview
@MainActor
enum PreviewContainer {
    /// Returns the preview persistence controller's viewContext
    static var viewContext: NSManagedObjectContext {
        PersistenceController.preview.viewContext
    }
}

/// A view that wraps preview content with a Core Data preview context
@MainActor
struct PreviewWrapper<Content: View>: View {
    let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        content()
            .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
    }
}

// MARK: - View Extension for Preview Container

extension View {
    /// Applies the preview Core Data context for previews
    @MainActor
    func previewCoreDataContext() -> some View {
        self
            .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
    }
}
