import Foundation
import PDFKit
import UIKit
import Vision

/// Reads text from the first pages of a PDF so Apple Intelligence can identify the piece.
/// Uses the PDF's own text layer when there is one, otherwise on-device text
/// recognition (Vision) for scanned pages.
enum TextExtractor {
    /// - Parameter allowOCR: false skips text recognition (fast, but scans give no text).
    static func extractText(
        from url: URL, maxPages: Int = 2, maxCharacters: Int = 1500, allowOCR: Bool = true
    ) async -> String {
        await Task.detached(priority: .utility) {
            TextExtractor.extractSynchronously(
                from: url, maxPages: maxPages, maxCharacters: maxCharacters, allowOCR: allowOCR)
        }.value
    }

    static func extractSynchronously(from url: URL, maxPages: Int, maxCharacters: Int, allowOCR: Bool = true) -> String {
        guard let document = PDFDocument(url: url) else { return "" }
        var chunks: [String] = []
        for index in 0..<min(maxPages, document.pageCount) {
            guard let page = document.page(at: index) else { continue }
            var text = page.string?.trimmed ?? ""
            if allowOCR && text.count < 40 {
                let recognized = recognizeText(on: page)
                if recognized.count > text.count { text = recognized }
            }
            if !text.isEmpty { chunks.append(tidy(text)) }
        }
        return String(chunks.joined(separator: "\n---\n").prefix(maxCharacters))
    }

    private static func recognizeText(on page: PDFPage) -> String {
        let bounds = page.bounds(for: .cropBox)
        guard bounds.width > 0, bounds.height > 0 else { return "" }
        let width: CGFloat = 1800
        let size = CGSize(width: width, height: width * bounds.height / bounds.width)
        guard let cgImage = page.thumbnail(of: size, for: .cropBox).cgImage else { return "" }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return ""
        }
        let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        return lines.joined(separator: "\n")
    }

    /// Collapses runs of spaces and blank lines to keep the export small.
    private static func tidy(_ text: String) -> String {
        text.components(separatedBy: .newlines)
            .map { $0.split(whereSeparator: { $0 == " " || $0 == "\t" }).joined(separator: " ") }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}
