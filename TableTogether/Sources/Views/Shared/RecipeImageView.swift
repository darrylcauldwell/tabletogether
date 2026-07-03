import SwiftUI

/// A reusable view that renders a recipe image with a three-step fallback chain:
///
/// 1. Local `imageData` (user-taken photo, in-app capture, demo data) — preferred
///    because it works offline and is already on disk.
/// 2. Remote `imageURL` (curated library thumbnails from #44) — fetched via
///    `RecipeImageLoader`, which downsamples to a display size and caches the
///    result in memory so scrolling never re-downloads or re-decodes the
///    full-resolution source (replaced AsyncImage, which did both and caused
///    recipe-view lag).
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
            CachedRemoteImage(url: imageURL, contentMode: contentMode) {
                placeholder
                    .overlay {
                        ProgressView()
                            .controlSize(.small)
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
