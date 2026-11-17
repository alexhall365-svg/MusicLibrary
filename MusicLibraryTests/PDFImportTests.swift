import XCTest
import SwiftData
import UIKit
@testable import MusicLibrary

/// Imports real (generated) PDFs into a temporary library.
@MainActor
final class PDFImportTests: XCTestCase {
    private let tempRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("PDFImportTests-\(UUID().uuidString)", isDirectory: true)

    private func makePDF(named name: String, pages: Int, text: String) throws -> URL {
        let url = tempRoot.appendingPathComponent("source", isDirectory: true).appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 595, height: 842))
        try renderer.writePDF(to: url) { context in
            for page in 0..<pages {
                context.beginPage()
                ("\(text) page \(page + 1)" as NSString).draw(
                    at: CGPoint(x: 72, y: 72),
                    withAttributes: [.font: UIFont.systemFont(ofSize: 12)])
            }
        }
        return url
    }

    func testImportCopiesFilesSkipsDuplicatesAndSuggestsMetadata() async throws {
        let container = LibraryDatabase.makeContainer(inMemory: true)
        let context = ModelContext(container)
        let paths = LibraryPaths(root: tempRoot.appendingPathComponent("lib"), cachesRoot: tempRoot.appendingPathComponent("cache"))
        let service = ImportService(context: context, paths: paths)

        let first = try makePDF(named: "Purcell - Hear my prayer (Z 15).pdf", pages: 3, text: "Hear my prayer")
        let report = await service.importItems([first])
        XCTAssertEqual(report.imported.count, 1)
        let score = try XCTUnwrap(report.imported.first)
        XCTAssertEqual(score.pageCount, 3)
        XCTAssertEqual(score.composer, "Purcell, Henry")
        XCTAssertEqual(score.title, "Hear my prayer")
        XCTAssertEqual(score.catalogueNumber, "Z. 15")
        XCTAssertEqual(score.contentHash.count, 64)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: paths.scoreFileURL(storedFileName: score.storedFileName).path))

        let again = await service.importItems([first])
        XCTAssertEqual(again.imported.count, 0)
        XCTAssertEqual(again.duplicates, ["Purcell - Hear my prayer (Z 15).pdf"])
    }

    func testFolderPackageWithMetadataJSON() async throws {
        let container = LibraryDatabase.makeContainer(inMemory: true)
        let context = ModelContext(container)
        let paths = LibraryPaths(root: tempRoot.appendingPathComponent("lib"), cachesRoot: tempRoot.appendingPathComponent("cache"))
        let service = ImportService(context: context, paths: paths)

        let pdf = try makePDF(named: "scan001.pdf", pages: 1, text: "Locus iste")
        let metadata = MetadataExchangeFile(scores: [
            ExchangeEntry(file: "scan001.pdf", metadata: ExchangeMetadata(title: "Locus iste", composer: "Bruckner, Anton"))
        ])
        try MetadataExchangeCodec.encode(metadata)
            .write(to: pdf.deletingLastPathComponent().appendingPathComponent("metadata.json"))

        let report = await service.importItems([pdf.deletingLastPathComponent()])
        XCTAssertEqual(report.imported.count, 1)
        let file = try XCTUnwrap(report.metadataFile)

        let score = try XCTUnwrap(report.imported.first)
        let subjects = [ReviewSubject(
            candidate: MatchCandidate(id: score.id, sha256: score.contentHash, fileName: score.originalFileName),
            metadata: score.metadata)]
        let review = MetadataReviewBuilder.build(file: file, subjects: subjects, title: "Package")
        XCTAssertEqual(review.items.first?.after.composer, "Bruckner, Anton")
    }

    func testTextExtractionReadsTextLayer() async throws {
        let pdf = try makePDF(named: "text.pdf", pages: 3, text: "Magnificat and Nunc dimittis in G major for choir")
        let text = await TextExtractor.extractText(from: pdf, maxPages: 2, maxCharacters: 500)
        XCTAssertTrue(text.contains("in G major for choir page 1"))
        XCTAssertTrue(text.contains("page 2"))
        XCTAssertFalse(text.contains("page 3"))
    }
}
