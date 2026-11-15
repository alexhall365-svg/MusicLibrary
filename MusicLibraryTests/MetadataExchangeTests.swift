import XCTest
@testable import MusicLibrary

final class MetadataExchangeTests: XCTestCase {
    func testRoundTrip() throws {
        let file = MetadataExchangeFile(
            scores: [
                ExchangeEntry(
                    id: UUID().uuidString,
                    file: "a.pdf",
                    sha256: "abc",
                    pageCount: 4,
                    text: "Hear my prayer",
                    metadata: ExchangeMetadata(
                        title: "Hear my prayer", composer: "Purcell, Henry", tags: ["Lent"],
                        extra: ["Publisher": "Novello"]),
                    confidence: ["title": 0.9],
                    flags: ["Check key"])
            ],
            exportedAt: Date(timeIntervalSince1970: 1_700_000_000),
            generator: "Tests",
            instructionsForClaude: "Do things"
        )
        let decoded = try MetadataExchangeCodec.decode(MetadataExchangeCodec.encode(file))
        XCTAssertEqual(decoded, file)
    }

    func testDecodesChatReplyWithCodeFenceAndLooseValues() throws {
        let reply = """
        Here are the labels:

        ```json
        {
          "schema": "music-library-metadata",
          "version": 1,
          "scores": [
            {
              "sha256": "ABC123",
              "file": "scan 1.pdf",
              "title": "Locus iste",
              "composer": "Bruckner, Anton",
              "catalogue": "WAB 23",
              "voicing": "SATB",
              "tags": "Dedication, Latin",
              "confidence": {"title": "high", "composer": 95, "catalogueNumber": 0.5},
              "flags": "Check the edition"
            }
          ]
        }
        ```
        Let me know if you need anything else.
        """
        let file = try MetadataExchangeCodec.decode(Data(reply.utf8))
        let entry = try XCTUnwrap(file.scores.first)
        XCTAssertEqual(entry.sha256, "ABC123")
        XCTAssertEqual(entry.metadata.title, "Locus iste")
        XCTAssertEqual(entry.metadata.composer, "Bruckner, Anton")
        XCTAssertEqual(entry.metadata.catalogueNumber, "WAB 23")
        XCTAssertEqual(entry.metadata.scoring, "SATB")
        XCTAssertEqual(entry.metadata.tags, ["Dedication", "Latin"])
        XCTAssertEqual(entry.confidence?["title"], 0.9)
        XCTAssertEqual(entry.confidence?["composer"], 0.95)
        XCTAssertEqual(entry.confidence?["catalogueNumber"], 0.5)
        XCTAssertEqual(entry.flags, ["Check the edition"])
    }

    func testAcceptsBareArrayAndSingleConfidence() throws {
        let json = #"[{"file": "x.pdf", "metadata": {"title": "X"}, "confidence": 0.4}]"#
        let file = try MetadataExchangeCodec.decode(Data(json.utf8))
        XCTAssertEqual(file.scores.count, 1)
        XCTAssertEqual(file.scores[0].confidence(for: .composer), 0.4)
    }

    func testRejectsNewerVersion() {
        let json = #"{"schema": "music-library-metadata", "version": 99, "scores": []}"#
        XCTAssertThrowsError(try MetadataExchangeCodec.decode(Data(json.utf8))) { error in
            XCTAssertEqual(error as? ExchangeError, .newerVersion(99))
        }
    }

    func testRejectsNonsense() {
        XCTAssertThrowsError(try MetadataExchangeCodec.decode(Data("hello".utf8)))
        XCTAssertThrowsError(try MetadataExchangeCodec.decode(Data()))
    }

    func testMissingFieldsLeaveValuesAndEmptyStringClears() {
        let base = ScoreMetadata(title: "Old", composer: "Tallis, Thomas", key: "F major", tags: ["Lent"])
        let patch = ExchangeMetadata(title: "If ye love me", key: "", extra: ["Publisher": "OUP"])
        let result = patch.applied(to: base)
        XCTAssertEqual(result.title, "If ye love me")
        XCTAssertEqual(result.composer, "Tallis, Thomas")
        XCTAssertEqual(result.key, "")
        XCTAssertEqual(result.tags, ["Lent"])
        XCTAssertEqual(result.extra, ["Publisher": "OUP"])
    }
}
