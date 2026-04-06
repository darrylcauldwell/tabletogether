import Foundation
import CoreData
import os
import SwiftUI
import UniformTypeIdentifiers

/// Exports recipes to JSON format for sharing and backup.
@Observable
@MainActor
final class RecipeExporter {
    private let logger = AppLogger.app

    /// Export recipes as JSON data.
    func exportRecipes(_ recipes: [Recipe]) throws -> Data {
        let codableRecipes = recipes.map { CodableRecipe(from: $0) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(codableRecipes)
        logger.info("Exported \(recipes.count) recipes (\(data.count) bytes)")
        return data
    }
}

/// FileDocument wrapper for exporting recipe JSON via the system file picker.
struct RecipeExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
