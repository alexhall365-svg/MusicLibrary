import XCTest
@testable import MusicLibrary

final class MetadataMatchingTests: XCTestCase {
    private let a = MatchCandidate(id: UUID(), sha256: "aaa", fileName: "Byrd - Ave verum.pdf")
    private let b = MatchCandidate(id: UUID(), sha256: "bbb", fileName: "Psalm.pdf")
    private let c = MatchCandidate(id: UUID(), sha256: "ccc", fileName: "Psalm.pdf")

    func testMatchesByHashFirst() {
        // The file name points at b, but the hash wins.
        let entries = [ExchangeEntry(file: "Psalm.pdf", sha256: "AAA")]
        let result = MetadataMatcher.match(entries, against: [a, b, c])
        XCTAssertEqual(result.matched[0], a.id)
    }

    func testMatchesByIDThenUniqueFileName() {
        let entries = [
            ExchangeEntry(id: b.id.uuidString),
            ExchangeEntry(file: "byrd - ave verum"),
            ExchangeEntry(file: "Psalm.pdf"),
            ExchangeEntry(file: "Unknown.pdf"),
        ]
        let result = MetadataMatcher.match(entries, against: [a, b, c])
        XCTAssertEqual(result.matched[0], b.id)
        XCTAssertEqual(result.matched[1], a.id)
        XCTAssertNil(result.matched[2], "Ambiguous file names must not match")
        XCTAssertEqual(result.unmatched, [2, 3])
    }

    func testReviewFlagsUncertainAndSkipsUnchanged() {
        let subjects = [
            ReviewSubject(candidate: a, metadata: ScoreMetadata(title: "Ave verum corpus", composer: "Byrd, William")),
            ReviewSubject(candidate: b, metadata: ScoreMetadata(title: "Psalm 23")),
        ]
        let file = MetadataExchangeFile(scores: [
            ExchangeEntry(sha256: "aaa", metadata: ExchangeMetadata(title: "Ave verum corpus")),
            ExchangeEntry(
                sha256: "bbb",
                metadata: ExchangeMetadata(composer: "Howells, Herbert", scoring: "SATB + organ"),
                confidence: ["composer": 0.4, "scoring": 0.9]),
            ExchangeEntry(file: "Missing.pdf", sha256: "zzz", metadata: ExchangeMetadata(title: "?")),
        ])
        let review = MetadataReviewBuilder.build(file: file, subjects: subjects, title: "Test")

        XCTAssertEqual(review.unchangedCount, 1)
        XCTAssertEqual(review.unmatchedFiles, ["Missing.pdf"])
        XCTAssertEqual(review.items.count, 1)
        let item = review.items[0]
        XCTAssertEqual(item.scoreID, b.id)
        XCTAssertEqual(item.after.title, "Psalm 23")
        XCTAssertEqual(item.after.composer, "Howells, Herbert")
        XCTAssertEqual(item.changes.map { $0.field }, [MetadataField.composer, MetadataField.scoring])
        XCTAssertTrue(item.needsAttention)
        XCTAssertEqual(item.changes.filter { $0.isUncertain }.map { $0.field }, [MetadataField.composer])
    }

    func testFlagsAloneNeedAttention() {
        let subjects = [ReviewSubject(candidate: a, metadata: ScoreMetadata(title: "Ave"))]
        let file = MetadataExchangeFile(scores: [
            ExchangeEntry(sha256: "aaa", metadata: ExchangeMetadata(), flags: ["Two pieces in one PDF"])
        ])
        let review = MetadataReviewBuilder.build(file: file, subjects: subjects, title: "Test")
        XCTAssertEqual(review.items.count, 1)
        XCTAssertTrue(review.items[0].needsAttention)
    }
}
