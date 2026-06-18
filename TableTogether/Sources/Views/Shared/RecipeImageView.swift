import SwiftUI

/// A reusable view that renders a recipe image with a three-step fallback chain:
///
/// 1. Local `imageData` (user-taken photo, in-app capture, demo data) — preferred
///    because it works offline and is already on disk.
/// 2. Remote `imageURL` (curated library thumbnails from #44) — fetched lazily via
///    SwiftUI's `AsyncImage`, which uses the system `URLCache` so each image only
///    hits the network once per app launch (and is reused thereafter from disk
///    cache).
/// 3. A neutral placeholder icon — shown while the URL is loading, when both
///    sources are nil, or when an `AsyncImage` fetch fails.
///
/// The view does not impose framing or clipping — callers wrap it with their own
/// `.frame`, `.clipped`, `.cornerRadius`, etc. so the existing layouts in the
/// recipe library, recipe detail, planning sidebar, and meal slot editor all
/// continue to look exactly as they did before.
struct RecipeImageView: View {

    let imageData: Data?
    let imageURL: URL?
    var contentMode: ContentMode = .fill

    var body: some View {
        if let imageData, let image = Self.platformImage(from: imageData) {
            image
                .resizable()
                .aspectRatio(contentMode: contentMode)
        } else if let imageURL {
            AsyncImage(url: imageURL, transaction: Transaction(animation: .default)) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                case .empty:
                    placeholder
                        .overlay {
                            ProgressView()
                                .controlSize(.small)
                        }
                case .failure:
                    placeholder
                @unknown default:
                    placeholder
                }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        ZStack {
            Theme.Colors.cardBackground
            Image(systemName: "photo")
                .font(AppTypography.title2)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }

    /// Decode raw image data into a SwiftUI `Image` on the current platform.
    private static func platformImage(from data: Data) -> Image? {
        #if canImport(UIKit)
        if let uiImage = UIImage(data: data) {
            return Image(uiImage: uiImage)
        }
        #elseif canImport(AppKit)
        if let nsImage = NSImage(data: data) {
            return Image(nsImage: nsImage)
        }
        #endif
        return nil
    }
}
