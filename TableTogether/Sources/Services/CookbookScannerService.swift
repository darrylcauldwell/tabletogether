//
//  CookbookScannerService.swift
//  TableTogether
//
//  Orchestrates cookbook page scanning: runs Vision OCR on scanned images
//  and feeds the extracted text to CookbookTextParser for segmentation.
//

#if os(iOS)
import Foundation
import UIKit
import Vision
import os.log

@Observable
@MainActor
final class CookbookScannerService {

    // MARK: - State

    enum ScanState: Equatable {
        case idle
        case recognizing
        case parsed(CookbookTextParser.ParseResult)
        case error(String)

        static func == (lhs: ScanState, rhs: ScanState) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.recognizing, .recognizing):
                return true
            case (.error(let a), .error(let b)):
                return a == b
            case (.parsed, .parsed):
                return true
            default:
                return false
            }
        }
    }

    var state: ScanState = .idle
    var scannedPages: [Data] = []
    var selectedPhotoIndex: Int = 0

    var selectedPhotoData: Data? {
        guard scannedPages.indices.contains(selectedPhotoIndex) else { return nil }
        return scannedPages[selectedPhotoIndex]
    }

    // MARK: - Public API

    func processScannedImages(_ images: [UIImage]) async {
        guard !images.isEmpty else {
            state = .error("No pages were scanned.")
            return
        }

        state = .recognizing

        // Store all pages as compressed JPEG
        scannedPages = images.compactMap { $0.jpegData(compressionQuality: 0.8) }
        selectedPhotoIndex = 0

        do {
            let allText = try await recognizeText(from: images)
            let result = CookbookTextParser.parse(allText)
            state = .parsed(result)
            AppLogger.scanner.info("OCR complete: \(images.count) pages, \(allText.count) chars")
        } catch {
            state = .error("Failed to recognize text: \(error.localizedDescription)")
            AppLogger.scanner.error("OCR failed", error: error)
        }
    }

    func reset() {
        state = .idle
        scannedPages = []
        selectedPhotoIndex = 0
    }

    // MARK: - Vision OCR

    private func recognizeText(from images: [UIImage]) async throws -> String {
        // Extract CGImages on the main actor, then run the OCR off it.
        let cgImages = images.compactMap { $0.cgImage }
        return try await Self.recognizeText(fromCGImages: cgImages)
    }

    /// Runs Vision OCR off the main actor. `handler.perform` is synchronous, CPU-heavy
    /// work (accurate recognition with language correction); marking this `nonisolated`
    /// hops it to the cooperative thread pool instead of freezing the UI for seconds.
    private nonisolated static func recognizeText(fromCGImages cgImages: [CGImage]) async throws -> String {
        var allPageTexts: [String] = []

        for cgImage in cgImages {
            let pageText = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
                let request = VNRecognizeTextRequest { request, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                        return
                    }

                    let observations = request.results as? [VNRecognizedTextObservation] ?? []
                    let text = observations
                        .compactMap { $0.topCandidates(1).first?.string }
                        .joined(separator: "\n")
                    continuation.resume(returning: text)
                }

                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                request.recognitionLanguages = ["en-GB", "en-US"]

                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(throwing: error)
                }
            }

            allPageTexts.append(pageText)
        }

        return allPageTexts.joined(separator: "\n\n")
    }
}
#endif
