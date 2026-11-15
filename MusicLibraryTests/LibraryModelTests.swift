import XCTest
import SwiftData
@testable import MusicLibrary

@MainActor
final class LibraryModelTests: XCTestCase {
    private lazy var container: ModelContainer = LibraryDatabase.makeContainer(inMemory: true)
    private lazy var context: ModelContext = ModelContext(container)

    private func makeScore(_ metadata: ScoreMetadata, file: String = "file.pdf") -> Score {
        let score = Score(
            storedFileName: "\(UUID().uuidString).pdf", originalFileName: file,
            contentHash: UUID().uuidString, pageCount: 1, metadata: metadata)
        context.insert(score)
        return score
    }

    func testMetadataIsNormalisedOnSave() {
        let score = makeScore(ScoreMetadata())
        score.metadata = ScoreMetadata(
            title: "  Hear my prayer ", tags: ["Lent", " lent", "", "Evensong"], extra: ["Empty": " ", "Copies": "20"])
        XCTAssertEqual(score.title, "Hear my prayer")
        XCTAssertEqual(score.tags, ["Lent", "Evensong"])
        XCTAssertEqual(score.extraFields, ["Copies": "20"])
    }

    func testDisplayTitleFallsBackToFileName() {
        let score = makeScore(ScoreMetadata(), file: "Scan 0042.pdf")
        XCTAssertEqual(score.displayTitle, "Scan 0042")
        XCTAssertTrue(score.needsLabels)
    }

    func testSearchMatchesAcrossFieldsIgnoringAccents() {
        _ = makeScore(ScoreMetadata(title: "Cantique de Jean Racine", composer: "Fauré, Gabriel", catalogueNumber: "Op. 11"))
        _ = makeScore(ScoreMetadata(title: "Requiem", composer: "Duruflé, Maurice", catalogueNumber: "Op. 9"))
        let all = (try? context.fetch(FetchDescriptor<Score>())) ?? []
        let results = LibraryFilter.apply(all, search: "faure op. 11", facet: nil, sort: .title)
        XCTAssertEqual(results.map(\.title), ["Cantique de Jean Racine"])
    }

    func testFacetFilterAndCounts() throws {
        _ = makeScore(ScoreMetadata(title: "A", composer: "Byrd, William", tags: ["Advent", "Latin"]))
        _ = makeScore(ScoreMetadata(title: "B", composer: "byrd, william", tags: ["advent"]))
        _ = makeScore(ScoreMetadata(title: "C", composer: "Tallis, Thomas"))
        let all = try context.fetch(FetchDescriptor<Score>())

        let composers = LibraryFilter.facetValues(.composer, in: all)
        XCTAssertEqual(composers.map(\.count), [2, 1])
        XCTAssertEqual(LibraryFilter.facetValues(.tag, in: all).first { $0.value.lowercased() == "advent" }?.count, 2)

        let byrd = LibraryFilter.apply(all, search: "", facet: Facet(kind: .composer, value: "Byrd, William"), sort: .title)
        XCTAssertEqual(byrd.map(\.title), ["A", "B"])
    }

    func testComposerSortPutsUnknownLast() throws {
        _ = makeScore(ScoreMetadata(title: "Z", composer: "Allegri, Gregorio"))
        _ = makeScore(ScoreMetadata(title: "Unknown piece"))
        _ = makeScore(ScoreMetadata(title: "A", composer: "Wood, Charles"))
        let sorted = LibraryFilter.sorted(try context.fetch(FetchDescriptor<Score>()), by: .composer)
        XCTAssertEqual(sorted.map(\.title), ["Z", "A", "Unknown piece"])
    }

    func testCatalogueSortIsNumeric() throws {
        _ = makeScore(ScoreMetadata(title: "x", catalogueNumber: "BWV 1000"))
        _ = makeScore(ScoreMetadata(title: "y", catalogueNumber: "BWV 227"))
        let sorted = LibraryFilter.sorted(try context.fetch(FetchDescriptor<Score>()), by: .catalogue)
        XCTAssertEqual(sorted.map(\.catalogueNumber), ["BWV 227", "BWV 1000"])
    }

    func testSetlistOrderingAndCascade() throws {
        let first = makeScore(ScoreMetadata(title: "Introit"))
        let second = makeScore(ScoreMetadata(title: "Anthem"))
        let setlist = LibraryActions.createSetlist(named: "Evensong", context: context)
        LibraryActions.add([second, first], to: setlist, context: context)
        XCTAssertEqual(setlist.orderedScores.map(\.title), ["Anthem", "Introit"])

        var entries = setlist.orderedEntries
        entries.reverse()
        LibraryActions.renumber(entries)
        XCTAssertEqual(setlist.orderedScores.map(\.title), ["Introit", "Anthem"])

        context.delete(first)
        try context.save()
        XCTAssertEqual(setlist.orderedScores.map(\.title), ["Anthem"])
    }

    func testReaderSessionTurnsThroughSetlistBoundaries() throws {
        // Real PDFs aren't needed: missing files give zero pages, which exercises
        // the hand-over from one piece to the next.
        let first = makeScore(ScoreMetadata(title: "One"))
        let second = makeScore(ScoreMetadata(title: "Two"))
        let session = ReaderSession(scores: [first, second], startIndex: 0)
        XCTAssertTrue(session.isSetlist)
        XCTAssertTrue(session.canGoForward)
        session.nextPage()
        XCTAssertEqual(session.currentScore.title, "Two")
        XCTAssertFalse(session.hasNextScore)
        session.previousPage()
        XCTAssertEqual(session.currentScore.title, "One")
    }
}
