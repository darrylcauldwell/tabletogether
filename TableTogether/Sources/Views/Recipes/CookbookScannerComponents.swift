//
//  CookbookScannerComponents.swift
//  TableTogether
//
//  Extracted subviews for the cookbook scanner: document camera wrapper,
//  scanned image preview, and raw OCR text section.
//

#if os(iOS)
import SwiftUI
import VisionKit

// MARK: - Document Scanner View

struct DocumentScannerView: UIViewControllerRepresentable {
    var onScanComplete: ([UIImage]) -> Void
    var onCancel: () -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let scanner = VNDocumentCameraViewController()
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onScanComplete: onScanComplete, onCancel: onCancel)
    }

    class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onScanComplete: ([UIImage]) -> Void
        let onCancel: () -> Void

        init(onScanComplete: @escaping ([UIImage]) -> Void, onCancel: @escaping () -> Void) {
            self.onScanComplete = onScanComplete
            self.onCancel = onCancel
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFinishWith scan: VNDocumentCameraScan
        ) {
            var images: [UIImage] = []
            for pageIndex in 0..<scan.pageCount {
                images.append(scan.imageOfPage(at: pageIndex))
            }
            onScanComplete(images)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            onCancel()
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFailWithError error: Error
        ) {
            AppLogger.scanner.error("Document camera failed", error: error)
            onCancel()
        }
    }
}

// MARK: - Scanned Pages Carousel

struct ScannedPagesCarousel: View {
    let pages: [Data]
    @Binding var selectedPhotoIndex: Int
    @State private var fullScreenPageIndex: Int = 0
    @State private var showingFullScreen = false

    var body: some View {
        if pages.isEmpty { return AnyView(EmptyView()) }

        return AnyView(VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Scanned Pages")
                    .font(AppTypography.headline)
                    .foregroundColor(.appTextPrimary)
                Spacer()
                Text("\(pages.count) page\(pages.count == 1 ? "" : "s")")
                    .font(AppTypography.caption)
                    .foregroundColor(.appTextSecondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, pageData in
                        if let uiImage = UIImage(data: pageData) {
                            pageThumb(uiImage: uiImage, index: index)
                        }
                    }
                }
            }

            if pages.count > 1 {
                Text("Tap a page to view full size. The selected page becomes the recipe photo.")
                    .font(AppTypography.caption)
                    .foregroundColor(.appTextSecondary)
            }
        }
        .fullScreenCover(isPresented: $showingFullScreen) {
            fullScreenPage(index: fullScreenPageIndex)
        })
    }

    private func pageThumb(uiImage: UIImage, index: Int) -> some View {
        let isSelected = index == selectedPhotoIndex
        return Button {
            selectedPhotoIndex = index
        } label: {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: pages.count == 1 ? nil : 160, height: 200)
                .frame(maxWidth: pages.count == 1 ? .infinity : nil)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isSelected ? Color.appPrimary : Color.appTextSecondary.opacity(0.3),
                                lineWidth: isSelected ? 3 : 1)
                )
                .overlay(alignment: .topTrailing) {
                    if isSelected {
                        Image(systemName: "photo.fill")
                            .font(AppTypography.caption)
                            .padding(6)
                            .background(Color.appPrimary)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .padding(6)
                    }
                }
                .overlay(alignment: .bottom) {
                    Text("Page \(index + 1)")
                        .font(AppTypography.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .padding(.bottom, 8)
                }
        }
        .contextMenu {
            Button {
                fullScreenPageIndex = index
                showingFullScreen = true
            } label: {
                Label("View Full Size", systemImage: "arrow.up.left.and.arrow.down.right")
            }
            Button {
                selectedPhotoIndex = index
            } label: {
                Label("Use as Recipe Photo", systemImage: "photo")
            }
        }
    }

    private func fullScreenPage(index: Int) -> some View {
        NavigationStack {
            Group {
                if pages.indices.contains(index),
                   let uiImage = UIImage(data: pages[index]) {
                    ScrollView {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    }
                }
            }
            .background(Color.black)
            .navigationTitle("Page \(index + 1) of \(pages.count)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        showingFullScreen = false
                    }
                    .foregroundColor(.white)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        selectedPhotoIndex = index
                        showingFullScreen = false
                    } label: {
                        Label("Use as Photo", systemImage: "photo")
                    }
                }
            }
        }
    }
}

// MARK: - Raw OCR Text Section

struct RawOCRTextSection: View {
    let rawText: String
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: "doc.text")
                        .font(AppTypography.caption)
                    Text("Raw OCR Text")
                        .font(AppTypography.headline)
                        .foregroundColor(.appTextPrimary)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(AppTypography.caption)
                        .foregroundColor(.appTextSecondary)
                }
            }

            if isExpanded {
                Text(rawText)
                    .font(AppTypography.caption)
                    .foregroundColor(.appTextSecondary)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.systemGray6)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}
#endif
