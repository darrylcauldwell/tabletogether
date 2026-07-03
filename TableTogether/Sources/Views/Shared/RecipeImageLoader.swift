import SwiftUI
import ImageIO
import os

#if canImport(UIKit)
import UIKit
typealias PlatformImageType = UIImage
#elseif canImport(AppKit)
import AppKit
typealias PlatformImageType = NSImage
#endif

/// Downsampling, de-duplicating, in-memory cache for remote recipe images.
///
/// The curated recipe library stores only remote `imageURL`s pointing at
/// full-resolution source photos (often >2000px). SwiftUI's `AsyncImage`
/// decodes those at full size on every appearance and leans on `URLCache`,
/// whose small default budget evicts a 226-image library — so scrolling
/// re-downloads and re-decodes constantly (the observed recipe-view lag).
///
/// This loader instead: downsamples to a display-appropriate max dimension via
/// ImageIO (decoding a thumbnail, never the full bitmap), holds results in an
/// `NSCache` keyed by URL, and coalesces concurrent requests for the same URL
/// so a grid of identical placeholders doesn't fire duplicate downloads.
actor RecipeImageLoader {
    static let shared = RecipeImageLoader()

    /// One cached entry per URL, sized generously enough for the full-width
    /// detail hero; grid cards downscale from it almost for free.
    static let maxPixelDimension: CGFloat = 1000

    private let cache = NSCache<NSURL, PlatformImageType>()
    private var inFlight: [URL: Task<PlatformImageType?, Never>] = [:]

    private init() {
        cache.countLimit = 300 // whole library + headroom; images are downsampled small
    }

    func image(for url: URL) async -> PlatformImageType? {
        let key = url as NSURL
        if let cached = cache.object(forKey: key) { return cached }
        if let existing = inFlight[url] { return await existing.value }

        let task = Task<PlatformImageType?, Never> {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                return Self.downsample(data: data, maxPixel: Self.maxPixelDimension)
            } catch {
                return nil
            }
        }
        inFlight[url] = task
        let image = await task.value
        inFlight[url] = nil
        if let image { cache.setObject(image, forKey: key) }
        return image
    }

    /// Decode only a thumbnail of `maxPixel` from the source data — never the
    /// full-resolution bitmap.
    private static func downsample(data: Data, maxPixel: CGFloat) -> PlatformImageType? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        #if canImport(UIKit)
        return UIImage(cgImage: cgImage)
        #elseif canImport(AppKit)
        return NSImage(cgImage: cgImage, size: .zero)
        #endif
    }
}

/// SwiftUI wrapper that renders a `RecipeImageLoader` result, with a builder for
/// the loading/failed placeholder. Shared by iOS/macOS and tvOS.
struct CachedRemoteImage<Placeholder: View>: View {
    let url: URL
    var contentMode: ContentMode = .fill
    @ViewBuilder let placeholder: () -> Placeholder

    @State private var image: PlatformImageType?

    var body: some View {
        Group {
            if let image {
                imageView(image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            image = await RecipeImageLoader.shared.image(for: url)
        }
    }

    private func imageView(_ image: PlatformImageType) -> Image {
        #if canImport(UIKit)
        Image(uiImage: image)
        #elseif canImport(AppKit)
        Image(nsImage: image)
        #endif
    }
}
