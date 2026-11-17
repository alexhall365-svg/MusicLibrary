import XCTest
import CloudKit
import SwiftData
@testable import MusicLibrary

@MainActor
final class SyncTests: XCTestCase {
    private lazy var container: ModelContainer = LibraryDatabase.makeContainer(inMemory: true)
    private lazy var context: ModelContext = ModelContext(container)

    private func makeScore(title: String = "Ave verum", library: String? = nil) -> Score {
        let score = Score(
            storedFileName: "\(UUID().uuidString).pdf", originalFileName: "\(title).pdf",
            contentHash: UUID().uuidString, pageCount: 3,
            metadata: ScoreMetadata(title: title, composer: "Mozart, Wolfgang Amadeus", tags: ["Lent"]))
        score.cloudLibrary = library
        context.insert(score)
        return score
    }

    // MARK: - Names and libraries

    func testRecordNamesRoundTrip() {
        let id = UUID()
        XCTAssertEqual(SyncRecordName.parse(SyncRecordName.score(id)), .score(id))
        XCTAssertEqual(SyncRecordName.parse(SyncRecordName.scoreFile(id)), .scoreFile(id))
        XCTAssertEqual(SyncRecordName.parse(SyncRecordName.setlist(id)), .setlist(id))
        XCTAssertEqual(SyncRecordName.parse(SyncRecordName.annotation(scoreID: id, page: 12)), .annotation(scoreID: id, page: 12))
        XCTAssertNil(SyncRecordName.parse("cloudkit.zoneshare"))
        XCTAssertNil(SyncRecordName.parse("score-not-a-uuid"))
    }

    func testLibraryKeysMapToZones() {
        let personal = CloudLibrary.location(of: nil)
        XCTAssertEqual(personal.scope, .private)
        XCTAssertEqual(personal.zoneID.zoneName, "Library")
        XCTAssertNil(CloudLibrary.key(for: personal.zoneID, scope: .private))

        let hosted = CloudLibrary.hostedKey(zoneName: "Choir-AB12CD34")
        XCTAssertTrue(CloudLibrary.isHosted(hosted))
        let hostedLocation = CloudLibrary.location(of: hosted)
        XCTAssertEqual(hostedLocation.scope, .private)
        XCTAssertEqual(CloudLibrary.key(for: hostedLocation.zoneID, scope: .private), hosted)

        let sharedZone = CKRecordZone.ID(zoneName: "Choir-AB12CD34", ownerName: "_owner123")
        let joined = CloudLibrary.key(for: sharedZone, scope: .shared)
        XCTAssertEqual(joined, "shared/_owner123/Choir-AB12CD34")
        XCTAssertTrue(CloudLibrary.isJoined(joined))
        let joinedLocation = CloudLibrary.location(of: joined)
        XCTAssertEqual(joinedLocation.scope, .shared)
        XCTAssertEqual(joinedLocation.zoneID, sharedZone)
    }

    // MARK: - Record values

    func testScoreValuesSurviveARecord() {
        let score = makeScore()
        score.extraFields = ["Copies": "20"]
        score.labelStatus = .autoUncertain
        let values = ScoreRecordValues(score: score)
        let record = CKRecord(recordType: SyncRecordName.scoreType)
        values.write(to: record)
        XCTAssertEqual(ScoreRecordValues(record: record), values)

        let other = makeScore(title: "Other")
        values.apply(to: other)
        XCTAssertEqual(ScoreRecordValues(score: other), values)
    }

    func testSetlistValuesKeepOrder() {
        let a = makeScore(title: "A"), b = makeScore(title: "B")
        let setlist = Setlist(name: "Evensong")
        context.insert(setlist)
        LibraryActions.add([b, a, b], to: setlist, context: context)
        let values = SetlistRecordValues(setlist: setlist)
        XCTAssertEqual(values.scoreIDs, [b.id, a.id, b.id].map(\.uuidString))
        let record = CKRecord(recordType: SyncRecordName.setlistType)
        values.write(to: record)
        XCTAssertEqual(SetlistRecordValues(record: record), values)
    }

    func testSystemFieldsRoundTrip() {
        let record = CKRecord(recordType: "Score", recordID: CKRecord.ID(recordName: "score-x"))
        record["title"] = "Ignored"
        let data = RecordArchive.systemFields(of: record)
        let restored = RecordArchive.record(fromSystemFields: data)
        XCTAssertEqual(restored?.recordID.recordName, "score-x")
        XCTAssertNil(restored?["title"])
    }

    func testFingerprintChangesWithDetails() {
        let score = makeScore()
        let before = ScoreRecordValues(score: score).fingerprint
        XCTAssertEqual(before, ScoreRecordValues(score: score).fingerprint)
        score.notes = "Divisi in bar 12"
        XCTAssertNotEqual(before, ScoreRecordValues(score: score).fingerprint)
    }

    // MARK: - Working out what to send

    func testDiffFindsNewChangedMovedAndDeleted() {
        var ledger = SyncLedger()
        ledger.entries["same"] = .init(library: nil, fingerprint: "1")
        ledger.entries["changed"] = .init(library: nil, fingerprint: "1")
        ledger.entries["moved"] = .init(library: nil, fingerprint: "1")
        ledger.entries["gone"] = .init(library: nil, fingerprint: "1")
        let local = [
            LocalRecordState(recordName: "same", library: nil, fingerprint: "1"),
            LocalRecordState(recordName: "changed", library: nil, fingerprint: "2"),
            LocalRecordState(recordName: "moved", library: "own/Choir-1", fingerprint: "1"),
            LocalRecordState(recordName: "new", library: nil, fingerprint: "1"),
        ]
        let plan = SyncDiff.plan(local: local, ledger: ledger) { _ in false }
        XCTAssertEqual(plan.saves.map(\.recordName), ["changed", "moved", "new"])
        XCTAssertEqual(plan.deletes, [
            .init(recordName: "gone", library: nil),
            .init(recordName: "moved", library: nil),
        ])
    }

    func testDiffNeverSendsReadOnlyChoirChanges() {
        let member = "shared/_owner/Choir-1"
        var ledger = SyncLedger()
        ledger.entries["choir-score"] = .init(library: member, fingerprint: "1")
        ledger.entries["choir-gone"] = .init(library: member, fingerprint: "1")
        let local = [
            LocalRecordState(recordName: "choir-score", library: member, fingerprint: "edited"),
            LocalRecordState(recordName: "mine", library: nil, fingerprint: "1"),
        ]
        let plan = SyncDiff.plan(local: local, ledger: ledger) { $0 == member }
        XCTAssertEqual(plan.saves.map(\.recordName), ["mine"])
        XCTAssertTrue(plan.deletes.isEmpty)
    }

    func testLocalStateListsScoreFilesAndSetlists() {
        let score = makeScore()
        let setlist = Setlist(name: "Advent")
        context.insert(setlist)
        LibraryActions.add([score], to: setlist, context: context)
        let names = Set(CloudSync.localState(
            context: context,
            annotations: AnnotationStore(paths: LibraryPaths(
                root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
                cachesRoot: FileManager.default.temporaryDirectory))).map(\.recordName))
        XCTAssertEqual(names, [
            SyncRecordName.score(score.id), SyncRecordName.scoreFile(score.id), SyncRecordName.setlist(setlist.id),
        ])
    }

    // MARK: - Choir lists

    func testAddingYourScoreToAChoirListMovesItIntoTheChoir() {
        let choir = CloudLibrary.hostedKey(zoneName: "Choir-1")
        let mine = makeScore(title: "Mine")
        let list = LibraryActions.createSetlist(named: "Christmas season 2026", in: choir, context: context)
        LibraryActions.add([mine], to: list, context: context)
        XCTAssertEqual(mine.cloudLibrary, choir)
        XCTAssertEqual(list.orderedScores.map(\.id), [mine.id])
    }

    func testChoirListIgnoresAnotherChoirsMusic() {
        let choir = CloudLibrary.hostedKey(zoneName: "Choir-1")
        let other = makeScore(title: "Other choir", library: "shared/_x/Choir-2")
        let list = LibraryActions.createSetlist(named: "Evensong", in: choir, context: context)
        LibraryActions.add([other], to: list, context: context)
        XCTAssertEqual(other.cloudLibrary, "shared/_x/Choir-2")
        XCTAssertTrue(list.orderedScores.isEmpty)
    }

    func testCopyToMySetlistsMakesAPersonalCopy() {
        let choir = "shared/_owner/Choir-1"
        let a = makeScore(title: "A", library: choir), b = makeScore(title: "B", library: choir)
        let list = Setlist(name: "Evensong – Advent Sunday", cloudLibrary: choir)
        context.insert(list)
        let entryA = SetlistEntry(position: 0), entryB = SetlistEntry(position: 1)
        context.insert(entryA); context.insert(entryB)
        entryA.score = a; entryA.setlist = list
        entryB.score = b; entryB.setlist = list
        let copy = LibraryActions.copyToMySetlists(list, context: context)
        XCTAssertNil(copy.cloudLibrary)
        XCTAssertEqual(copy.name, list.name)
        XCTAssertEqual(copy.orderedScores.map(\.id), [a.id, b.id])
    }

    func testRemoveFromChoirKeepingACopy() {
        let choir = CloudLibrary.hostedKey(zoneName: "Choir-1")
        let score = makeScore(library: choir)
        let list = LibraryActions.createSetlist(named: "Evensong", in: choir, context: context)
        LibraryActions.add([score], to: list, context: context)
        LibraryActions.removeFromChoir(score, keepCopy: true, context: context)
        XCTAssertNil(score.cloudLibrary)
        XCTAssertTrue(list.orderedScores.isEmpty)
    }
}
