import Foundation
import CloudKit
import CryptoKit

/// Which library something belongs to, and where that library lives in CloudKit.
///
/// - Your own library (`nil`) lives in the `Library` zone of your private database.
/// - A Choir Library you host (`own/<zone>`) is a zone in your private database,
///   shared with the choir through a zone-wide `CKShare`.
/// - A Choir Library you joined (`shared/<owner>/<zone>`) is that zone, seen
///   through your shared database.
enum CloudLibrary {
    static let personalZoneName = "Library"
    static let hostedZonePrefix = "Choir-"

    static func isHosted(_ key: String?) -> Bool { key?.hasPrefix("own/") == true }
    static func isJoined(_ key: String?) -> Bool { key?.hasPrefix("shared/") == true }

    /// The key for a Choir Library you host in the given zone.
    static func hostedKey(zoneName: String) -> String { "own/\(zoneName)" }

    /// The library key for a zone, or nil for your own library.
    static func key(for zoneID: CKRecordZone.ID, scope: CKDatabase.Scope) -> String? {
        switch scope {
        case .shared:
            return "shared/\(zoneID.ownerName)/\(zoneID.zoneName)"
        default:
            return zoneID.zoneName == personalZoneName ? nil : hostedKey(zoneName: zoneID.zoneName)
        }
    }

    /// The zone and database that hold a library.
    static func location(of key: String?) -> (zoneID: CKRecordZone.ID, scope: CKDatabase.Scope) {
        guard let key else {
            return (CKRecordZone.ID(zoneName: personalZoneName, ownerName: CKCurrentUserDefaultName), .private)
        }
        let parts = key.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        if parts.first == "shared", parts.count >= 3 {
            return (CKRecordZone.ID(zoneName: parts[2...].joined(separator: "/"), ownerName: parts[1]), .shared)
        }
        let zoneName = parts.dropFirst().joined(separator: "/")
        return (CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName), .private)
    }
}

/// Record types and names used in CloudKit. Keep in step with `CloudKit/schema.ckdb`.
enum SyncRecordName {
    static let scoreType = "Score"
    static let scoreFileType = "ScoreFile"
    static let setlistType = "Setlist"
    static let annotationType = "AnnotationPage"

    static func score(_ id: UUID) -> String { "score-\(id.uuidString)" }
    /// The PDF is a separate record, so editing details never re-sends or
    /// re-downloads the file.
    static func scoreFile(_ id: UUID) -> String { "file-\(id.uuidString)" }
    static func setlist(_ id: UUID) -> String { "list-\(id.uuidString)" }
    static func annotation(scoreID: UUID, page: Int) -> String { "ann-\(scoreID.uuidString)-p\(page)" }

    enum Parsed: Equatable {
        case score(UUID)
        case scoreFile(UUID)
        case setlist(UUID)
        case annotation(scoreID: UUID, page: Int)
    }

    static func parse(_ name: String) -> Parsed? {
        if name.hasPrefix("score-"), let id = UUID(uuidString: String(name.dropFirst(6))) {
            return .score(id)
        }
        if name.hasPrefix("file-"), let id = UUID(uuidString: String(name.dropFirst(5))) {
            return .scoreFile(id)
        }
        if name.hasPrefix("list-"), let id = UUID(uuidString: String(name.dropFirst(5))) {
            return .setlist(id)
        }
        if name.hasPrefix("ann-") {
            let rest = name.dropFirst(4)
            guard let marker = rest.range(of: "-p", options: .backwards),
                  let id = UUID(uuidString: String(rest[..<marker.lowerBound])),
                  let page = Int(rest[marker.upperBound...]) else { return nil }
            return .annotation(scoreID: id, page: page)
        }
        return nil
    }
}

// MARK: - Values that sync

/// The synced fields of a score. Reading position and "last opened" stay on the
/// device, so each person (and each device) keeps their own.
struct ScoreRecordValues: Codable, Equatable {
    /// Page text is only a labelling aid; long text is trimmed to keep records small.
    static let maxExtractedText = 40_000

    var title = ""
    var composer = ""
    var catalogueNumber = ""
    var scoring = ""
    var key = ""
    var genre = ""
    var tags: [String] = []
    var notes = ""
    var extraFields: [String: String] = [:]
    var originalFileName = ""
    var contentHash = ""
    var pageCount = 0
    /// Whole seconds, so values survive CloudKit's date precision unchanged.
    var dateAdded: Double = 0
    var labelStatus: String?
    var extractedText: String?
    var pageFingerprint: Data?

    init() {}

    init(score: Score) {
        title = score.title
        composer = score.composer
        catalogueNumber = score.catalogueNumber
        scoring = score.scoring
        key = score.key
        genre = score.genre
        tags = score.tags
        notes = score.notes
        extraFields = score.extraFields
        originalFileName = score.originalFileName
        contentHash = score.contentHash
        pageCount = score.pageCount
        dateAdded = score.dateAdded.timeIntervalSince1970.rounded(.down)
        labelStatus = score.labelStatusRaw
        extractedText = score.extractedText.map { String($0.prefix(Self.maxExtractedText)) }
        pageFingerprint = score.pageFingerprint
    }

    init(record: CKRecord) {
        title = record["title"] as? String ?? ""
        composer = record["composer"] as? String ?? ""
        catalogueNumber = record["catalogueNumber"] as? String ?? ""
        scoring = record["scoring"] as? String ?? ""
        key = record["key"] as? String ?? ""
        genre = record["genre"] as? String ?? ""
        tags = record["tags"] as? [String] ?? []
        notes = record["notes"] as? String ?? ""
        if let json = record["extraFields"] as? String,
           let data = json.data(using: .utf8),
           let fields = try? JSONDecoder().decode([String: String].self, from: data) {
            extraFields = fields
        }
        originalFileName = record["originalFileName"] as? String ?? ""
        contentHash = record["contentHash"] as? String ?? ""
        pageCount = (record["pageCount"] as? Int) ?? Int((record["pageCount"] as? Int64) ?? 0)
        dateAdded = ((record["dateAdded"] as? Date) ?? Date()).timeIntervalSince1970.rounded(.down)
        labelStatus = record["labelStatus"] as? String
        extractedText = record["extractedText"] as? String
        pageFingerprint = record["pageFingerprint"] as? Data
    }

    func write(to record: CKRecord) {
        record["title"] = title
        record["composer"] = composer
        record["catalogueNumber"] = catalogueNumber
        record["scoring"] = scoring
        record["key"] = key
        record["genre"] = genre
        record["tags"] = tags.isEmpty ? nil : tags
        record["notes"] = notes
        if extraFields.isEmpty {
            record["extraFields"] = nil
        } else {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            record["extraFields"] = (try? encoder.encode(extraFields)).flatMap { String(data: $0, encoding: .utf8) }
        }
        record["originalFileName"] = originalFileName
        record["contentHash"] = contentHash
        record["pageCount"] = pageCount
        record["dateAdded"] = Date(timeIntervalSince1970: dateAdded)
        record["labelStatus"] = labelStatus
        record["extractedText"] = extractedText
        record["pageFingerprint"] = pageFingerprint
    }

    func apply(to score: Score) {
        // Set fields directly: values from the cloud are already normalised, and
        // normalising again could make them differ and bounce back.
        if score.title != title { score.title = title }
        if score.composer != composer { score.composer = composer }
        if score.catalogueNumber != catalogueNumber { score.catalogueNumber = catalogueNumber }
        if score.scoring != scoring { score.scoring = scoring }
        if score.key != key { score.key = key }
        if score.genre != genre { score.genre = genre }
        if score.tags != tags { score.tags = tags }
        if score.notes != notes { score.notes = notes }
        if score.extraFields != extraFields { score.extraFields = extraFields }
        if score.originalFileName != originalFileName { score.originalFileName = originalFileName }
        if score.contentHash != contentHash { score.contentHash = contentHash }
        if score.pageCount != pageCount { score.pageCount = pageCount }
        let added = Date(timeIntervalSince1970: dateAdded)
        if score.dateAdded.timeIntervalSince1970.rounded(.down) != dateAdded { score.dateAdded = added }
        if score.labelStatusRaw != labelStatus { score.labelStatusRaw = labelStatus }
        if let extractedText, score.extractedText != extractedText { score.extractedText = extractedText }
        if let pageFingerprint, score.pageFingerprint != pageFingerprint { score.pageFingerprint = pageFingerprint }
    }

    var fingerprint: String { SyncFingerprint.of(self) }
}

/// The synced fields of a setlist. The order is stored as a list of score IDs,
/// so a whole list (with its order) is saved and received in one piece.
struct SetlistRecordValues: Codable, Equatable {
    var name = ""
    var notes = ""
    var createdAt: Double = 0
    var scoreIDs: [String] = []

    init() {}

    init(setlist: Setlist) {
        name = setlist.name
        notes = setlist.notes
        createdAt = setlist.createdAt.timeIntervalSince1970.rounded(.down)
        scoreIDs = setlist.orderedEntries.compactMap { $0.score?.id.uuidString }
    }

    init(record: CKRecord) {
        name = record["name"] as? String ?? ""
        notes = record["notes"] as? String ?? ""
        createdAt = ((record["createdAt"] as? Date) ?? Date()).timeIntervalSince1970.rounded(.down)
        scoreIDs = record["scoreIDs"] as? [String] ?? []
    }

    func write(to record: CKRecord) {
        record["name"] = name
        record["notes"] = notes
        record["createdAt"] = Date(timeIntervalSince1970: createdAt)
        record["scoreIDs"] = scoreIDs.isEmpty ? nil : scoreIDs
    }

    var fingerprint: String { SyncFingerprint.of(self) }
}

enum SyncFingerprint {
    static func of<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = (try? encoder.encode(value)) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Annotation files change as a whole, so their size and date identify a version.
    static func ofFile(at url: URL) -> String? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
              let size = values.fileSize else { return nil }
        let date = values.contentModificationDate?.timeIntervalSince1970 ?? 0
        return "\(size)-\(Int(date * 1000))"
    }
}

// MARK: - System fields

enum RecordArchive {
    /// The record's identity and change tag, without its values.
    static func systemFields(of record: CKRecord) -> Data {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
        coder.finishEncoding()
        return coder.encodedData
    }

    static func record(fromSystemFields data: Data) -> CKRecord? {
        guard let coder = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        coder.requiresSecureCoding = true
        defer { coder.finishDecoding() }
        return CKRecord(coder: coder)
    }
}
