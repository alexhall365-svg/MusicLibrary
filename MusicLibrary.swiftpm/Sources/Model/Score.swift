import Foundation
import SwiftData

/// One PDF in the library. The PDF itself lives in `LibraryPaths.scoresDirectory`
/// and is never modified; annotations are stored separately per page.
///
/// Every stored property has a default value and relationships are optional so the
/// model can later sync with CloudKit without a migration.
@Model
final class Score {
    var id: UUID = UUID()

    // Descriptive metadata (see `ScoreMetadata`).
    var title: String = ""
    var composer: String = ""
    var catalogueNumber: String = ""
    var scoring: String = ""
    var key: String = ""
    var genre: String = ""
    var tags: [String] = []
    var notes: String = ""
    /// User-defined fields, for expanding the metadata without a schema change.
    var extraFields: [String: String] = [:]

    // File information.
    var storedFileName: String = ""
    var originalFileName: String = ""
    var contentHash: String = ""
    var pageCount: Int = 0

    // Usage.
    var dateAdded: Date = Date()
    var lastOpened: Date?
    var lastPageIndex: Int = 0

    /// Text read from the first pages, cached for labelling.
    var extractedText: String?

    /// How the details were last filled automatically (see `LabelStatus`).
    var labelStatusRaw: String?

    @Relationship(deleteRule: .cascade, inverse: \SetlistEntry.score)
    var setlistEntries: [SetlistEntry]? = []

    init(
        id: UUID = UUID(),
        storedFileName: String,
        originalFileName: String,
        contentHash: String,
        pageCount: Int,
        metadata: ScoreMetadata = ScoreMetadata()
    ) {
        let clean = metadata.normalized()
        self.id = id
        self.storedFileName = storedFileName
        self.originalFileName = originalFileName
        self.contentHash = contentHash
        self.pageCount = pageCount
        self.title = clean.title
        self.composer = clean.composer
        self.catalogueNumber = clean.catalogueNumber
        self.scoring = clean.scoring
        self.key = clean.key
        self.genre = clean.genre
        self.tags = clean.tags
        self.notes = clean.notes
        self.extraFields = clean.extra
        self.dateAdded = Date()
    }
}

extension Score {
    /// All descriptive fields as one value. Setting it normalises the values.
    var metadata: ScoreMetadata {
        get {
            ScoreMetadata(
                title: title,
                composer: composer,
                catalogueNumber: catalogueNumber,
                scoring: scoring,
                key: key,
                genre: genre,
                tags: tags,
                notes: notes,
                extra: extraFields
            )
        }
        set {
            let clean = newValue.normalized()
            title = clean.title
            composer = clean.composer
            catalogueNumber = clean.catalogueNumber
            scoring = clean.scoring
            key = clean.key
            genre = clean.genre
            tags = clean.tags
            notes = clean.notes
            extraFields = clean.extra
        }
    }

    var displayTitle: String {
        if !title.isEmpty { return title }
        let base = (originalFileName as NSString).deletingPathExtension
        return base.isEmpty ? "Untitled" : base
    }

    /// "Composer · Catalogue" for compact rows.
    var subtitle: String {
        [composer, catalogueNumber].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    var fileURL: URL {
        LibraryPaths.shared.scoreFileURL(storedFileName: storedFileName)
    }

    var needsLabels: Bool { metadata.isMissingEssentials }

    var labelStatus: LabelStatus? {
        get { labelStatusRaw.flatMap(LabelStatus.init(rawValue:)) }
        set { labelStatusRaw = newValue?.rawValue }
    }

    /// Missing details, or filled automatically with low confidence.
    var needsAttention: Bool { needsLabels || labelStatus == .autoUncertain }
}

enum LabelStatus: String {
    /// Filled automatically and confidently.
    case auto
    /// Filled automatically, but worth checking.
    case autoUncertain
}
