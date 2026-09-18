import Foundation
import PDFKit
import Vision
import UIKit

struct OreDocumentAdmissionReceiptV3: Sendable {
    enum ExtractionMode: String, Sendable {
        case textLayer = "client_pdf_text_layer_unverified"
        case visionOCR = "client_vision_ocr_unverified"
    }

    let text: String
    let mode: ExtractionMode
    let pageCount: Int
    let processedPages: Int
    let truncated: Bool

    var isUsable: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).count >= 8
    }
}

enum OreDocumentAdmissionV3 {
    static let revision = "AURORA-ORE-DOCUMENT-ADMISSION-V3-2026.09.17"
    static let maximumOCRPages = 24
    private static let minimumUsefulTextCharacters = 80

    /// OCR frequently confuses the letter O with zero inside short oxide formulae.
    /// Correction is deliberately restricted to the first whitespace-delimited token
    /// on a line so free prose, values and sample identifiers are never rewritten.
    static func normalizeRecoveredChemistryText(_ text: String) -> String {
        let aliases: [String: String] = [
            "K20": "K2O",
            "NA20": "Na2O",
            "FE203": "Fe2O3",
            "AL203": "Al2O3",
            "SI02": "SiO2",
            "TI02": "TiO2",
            "P205": "P2O5",
            "CR203": "Cr2O3",
            "CA0": "CaO",
            "MG0": "MgO",
            "MN0": "MnO",
            "S03": "SO3"
        ]

        return text.split(separator: "\n", omittingEmptySubsequences: false).map { rawLine in
            let line = String(rawLine)
            guard let firstRange = line.range(of: #"^\s*([^\s]+)"#, options: .regularExpression) else {
                return line
            }
            let tokenWithWhitespace = String(line[firstRange])
            let token = tokenWithWhitespace.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let canonical = aliases[token.uppercased()] else { return line }
            guard let tokenRange = line.range(of: token, range: firstRange) else { return line }
            var out = line
            out.replaceSubrange(tokenRange, with: canonical)
            return out
        }.joined(separator: "\n")
    }

    static func extractFallbackText(fromPDF data: Data) async throws -> OreDocumentAdmissionReceiptV3 {
        try await Task.detached(priority: .userInitiated) {
            guard let document = PDFDocument(data: data) else {
                throw AdmissionError.invalidPDF
            }

            let pageCount = document.pageCount
            let nativeText = (document.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if nativeText.count >= minimumUsefulTextCharacters {
                return OreDocumentAdmissionReceiptV3(
                    text: normalizeRecoveredChemistryText(nativeText),
                    mode: .textLayer,
                    pageCount: pageCount,
                    processedPages: pageCount,
                    truncated: false
                )
            }

            let limit = min(pageCount, maximumOCRPages)
            var pages: [String] = []
            pages.reserveCapacity(limit)

            for index in 0..<limit {
                guard let page = document.page(at: index) else { continue }
                autoreleasepool {
                    let thumbnail = page.thumbnail(
                        of: CGSize(width: 1800, height: 2400),
                        for: .mediaBox
                    )
                    guard let cgImage = thumbnail.cgImage else { return }

                    let request = VNRecognizeTextRequest()
                    request.recognitionLevel = .accurate
                    request.usesLanguageCorrection = true
                    request.recognitionLanguages = ["en-US"]
                    request.minimumTextHeight = 0.008

                    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                    do {
                        try handler.perform([request])
                        let observations = request.results ?? []
                        let text = observations
                            .compactMap { $0.topCandidates(1).first?.string }
                            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                            .joined(separator: "\n")
                        if !text.isEmpty {
                            pages.append("--- PAGE \(index + 1) ---\n" + normalizeRecoveredChemistryText(text))
                        }
                    } catch {
                        // Page-level OCR failure is non-fatal. The receipt remains review-only.
                    }
                }
            }

            let joined = pages.joined(separator: "\n")
            if joined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw AdmissionError.noRecognizableText
            }

            return OreDocumentAdmissionReceiptV3(
                text: joined,
                mode: .visionOCR,
                pageCount: pageCount,
                processedPages: limit,
                truncated: pageCount > limit
            )
        }.value
    }

    enum AdmissionError: LocalizedError {
        case invalidPDF
        case noRecognizableText

        var errorDescription: String? {
            switch self {
            case .invalidPDF:
                return "The selected file is not a readable PDF document."
            case .noRecognizableText:
                return "No usable text could be recovered from the PDF text layer or local Vision OCR."
            }
        }
    }
}
