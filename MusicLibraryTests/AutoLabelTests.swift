import XCTest
@testable import MusicLibrary

final class AutoLabelTests: XCTestCase {
    func testPlaceholdersAreBlanked() {
        let cleaned = AutoLabelLogic.cleaned(ScoreMetadata(
            title: "Locus iste", composer: "Unknown", catalogueNumber: "N/A", key: "  ", genre: "Motet",
            tags: ["Latin", "none"]))
        XCTAssertEqual(cleaned.title, "Locus iste")
        XCTAssertEqual(cleaned.composer, "")
        XCTAssertEqual(cleaned.catalogueNumber, "")
        XCTAssertEqual(cleaned.genre, "Motet")
        XCTAssertEqual(cleaned.tags, ["Latin"])
    }

    func testMergeReplacesFilledFieldsKeepsOthersAndCombinesTags() {
        let base = ScoreMetadata(
            title: "scan 0042", composer: "", key: "F major", tags: ["Lent"], notes: "Our copy", extra: ["Copies": "20"])
        let suggestion = ScoreMetadata(
            title: "If ye love me", composer: "Tallis, Thomas", key: "unknown", genre: "Anthem", tags: ["lent", "Pentecost"])
        let merged = AutoLabelLogic.merged(suggestion, into: base)
        XCTAssertEqual(merged.title, "If ye love me")
        XCTAssertEqual(merged.composer, "Tallis, Thomas")
        XCTAssertEqual(merged.key, "F major", "An 'unknown' answer must not overwrite a value")
        XCTAssertEqual(merged.genre, "Anthem")
        XCTAssertEqual(merged.tags, ["Lent", "Pentecost"])
        XCTAssertEqual(merged.notes, "Our copy")
        XCTAssertEqual(merged.extra, ["Copies": "20"])
    }

    func testUncertainty() {
        let good = MetadataSuggestion(
            metadata: ScoreMetadata(title: "A", composer: "B"), confidence: ["*": 0.9], source: "test")
        XCTAssertFalse(AutoLabelLogic.isUncertain(good))

        var low = good
        low.confidence = ["*": 0.5]
        XCTAssertTrue(AutoLabelLogic.isUncertain(low))

        var flagged = good
        flagged.flags = ["Two pieces in one PDF"]
        XCTAssertTrue(AutoLabelLogic.isUncertain(flagged))

        var noComposer = good
        noComposer.metadata.composer = ""
        XCTAssertTrue(AutoLabelLogic.isUncertain(noComposer))
    }

    func testSuggestionsFlowIntoTheReviewScreen() {
        let id = UUID()
        let base = ScoreMetadata(title: "Scan 1")
        let suggestion = MetadataSuggestion(
            metadata: ScoreMetadata(title: "Ave verum corpus", composer: "Byrd, William"),
            confidence: ["*": 0.6], source: "test")
        let entry = AutoLabelLogic.exchangeEntry(
            id: id, fileName: "Scan 1.pdf", sha256: "abc", base: base, suggestion: suggestion)
        let file = MetadataExchangeFile(scores: [entry])
        let subject = ReviewSubject(
            candidate: MatchCandidate(id: id, sha256: "abc", fileName: "Scan 1.pdf"), metadata: base)
        let review = MetadataReviewBuilder.build(file: file, subjects: [subject], title: "AI")
        XCTAssertEqual(review.items.count, 1)
        XCTAssertEqual(review.items[0].after.composer, "Byrd, William")
        XCTAssertTrue(review.items[0].needsAttention, "60% confidence should be highlighted")
    }

    func testStatusIsReportedWithoutCrashing() {
        // The simulator usually has no model; this checks the fallback path.
        let status = AppleIntelligence.status
        XCTAssertFalse(status.message.isEmpty)
        if !status.isAvailable {
            XCTAssertNil(AppleIntelligence.makeSuggester())
        }
    }
}
