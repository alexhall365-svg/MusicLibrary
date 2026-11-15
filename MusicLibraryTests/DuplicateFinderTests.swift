import XCTest
@testable import MusicLibrary

final class DuplicateFinderTests: XCTestCase {
    private func candidate(
        _ title: String, composer: String = "", file: String? = nil, pages: Int = 4,
        hash: String? = nil, text: String? = nil, fingerprint: [UInt8]? = nil
    ) -> DuplicateCandidate {
        DuplicateCandidate(
            id: UUID(), fileName: file ?? "\(title).pdf", title: title, composer: composer,
            pageCount: pages, sha256: hash ?? UUID().uuidString, text: text,
            fingerprint: fingerprint.map { Data($0) })
    }

    func testCopyMarkersAndAccentsAreIgnoredInNames() {
        XCTAssertEqual(DuplicateFinder.normalizedName("Fauré – Cantique (1).pdf"), "faure cantique")
        XCTAssertEqual(DuplicateFinder.normalizedName("Fauré - Cantique copy 2.pdf"), "faure cantique")
    }

    func testSameTitleAndComposerAreGrouped() {
        let a = candidate("Hear my prayer", composer: "Purcell, Henry", file: "scan1.pdf")
        let b = candidate("Hear My Prayer", composer: "Purcell, Henry", file: "hmp.pdf")
        let c = candidate("Hear my prayer", composer: "Mendelssohn, Felix", file: "other.pdf")
        let groups = DuplicateFinder.findGroups([a, b, c])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(Set(groups[0].scoreIDs), [a.id, b.id])
        XCTAssertEqual(groups[0].reasons, [.sameName])
    }

    func testCopiedFileNamesAreGrouped() {
        let a = candidate("x", file: "Stanford in G.pdf")
        let b = candidate("y", file: "Stanford in G (1).pdf")
        XCTAssertEqual(DuplicateFinder.findGroups([a, b]).count, 1)
    }

    func testDifferentNumbersAreNotSimilar() {
        let a = candidate("Psalm 23 Anglican chant")
        let b = candidate("Psalm 24 Anglican chant")
        XCTAssertTrue(DuplicateFinder.findGroups([a, b]).isEmpty)
    }

    func testSimilarTitleIsGrouped() {
        let a = candidate("Magnificat and Nunc dimittis in G major", composer: "Stanford, Charles Villiers")
        let b = candidate("Magnificat & Nunc dimittis in G major", composer: "")
        let groups = DuplicateFinder.findGroups([a, b])
        XCTAssertEqual(groups.first?.reasons, [.similarName])
    }

    func testSameTextWithDifferentNamesIsGrouped() {
        let text = "Ave verum corpus natum de Maria virgine vere passum immolatum in cruce pro homine cujus latus perforatum fluxit aqua et sanguine esto nobis praegustatum in mortis examine"
        let a = candidate("scan0001", text: text)
        let b = candidate("Mozart motet", text: text + " Novello edition")
        let groups = DuplicateFinder.findGroups([a, b])
        XCTAssertEqual(groups.first?.reasons, [.sameText])
    }

    func testSameLookingFirstPageIsGrouped() {
        let page = (0..<1024).map { UInt8(($0 * 37) % 256) }
        let slightlyDifferent = page.map { $0 > 250 ? $0 : $0 + 3 }
        let a = candidate("scan A", fingerprint: page)
        let b = candidate("scan B", fingerprint: slightlyDifferent)
        let c = candidate("scan C", fingerprint: Array(page.reversed()))
        let groups = DuplicateFinder.findGroups([a, b, c])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(Set(groups[0].scoreIDs), [a.id, b.id])
        XCTAssertEqual(groups[0].reasons, [.samePage])
    }

    func testIdenticalHashAndIgnoredPairs() {
        let a = candidate("One", hash: "abc")
        let b = candidate("Two", hash: "ABC")
        XCTAssertEqual(DuplicateFinder.findGroups([a, b]).first?.reasons, [.identicalFile])
        let ignored: Set<String> = [DuplicateFinder.pairKey(b.id, a.id)]
        XCTAssertTrue(DuplicateFinder.findGroups([a, b], ignoredPairs: ignored).isEmpty)
    }

    func testChainsBecomeOneGroup() {
        let a = candidate("Te Deum in B flat", composer: "Stanford, Charles Villiers", file: "a.pdf")
        let b = candidate("Te Deum in B flat", composer: "", file: "b.pdf", hash: "h")
        let c = candidate("Something else", file: "c.pdf", hash: "h")
        let groups = DuplicateFinder.findGroups([a, b, c])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].scoreIDs.count, 3)
        XCTAssertEqual(groups[0].reasons, [.identicalFile, .sameName])
    }
}
