import Foundation

/// The descriptive fields of a score as a plain value, used for editing,
/// suggestions and the JSON exchange format.
struct ScoreMetadata: Equatable, Codable, Sendable {
    var title: String = ""
    var composer: String = ""
    var catalogueNumber: String = ""
    /// Voicing or instrumentation, e.g. "SATB + organ".
    var scoring: String = ""
    var key: String = ""
    var genre: String = ""
    var tags: [String] = []
    var notes: String = ""
    /// Custom fields added by the user.
    var extra: [String: String] = [:]

    var isMissingEssentials: Bool {
        title.trimmed.isEmpty || composer.trimmed.isEmpty
    }

    /// Applies the library's standards: composer names as "Surname, Forenames",
    /// tidy catalogue numbers (never IMSLP numbers), standard voicing and genres,
    /// trimmed text, no duplicate tags and no empty custom fields.
    func normalized() -> ScoreMetadata {
        var copy = self
        copy.title = title.trimmed
        copy.composer = ComposerNames.normalized(composer)
        copy.catalogueNumber = CatalogueNumbers.tidy(catalogueNumber)
        copy.scoring = ScoringNames.normalized(scoring)
        copy.key = key.trimmed
        copy.genre = GenreNames.normalized(genre, title: title)
        copy.notes = notes.trimmed
        copy.tags = Self.normalizedTags(tags)
        var cleanExtra: [String: String] = [:]
        for (name, value) in extra {
            let cleanName = name.trimmed
            let cleanValue = value.trimmed
            if !cleanName.isEmpty && !cleanValue.isEmpty {
                cleanExtra[cleanName] = cleanValue
            }
        }
        copy.extra = cleanExtra
        return copy
    }

    static func normalizedTags(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for tag in tags {
            let clean = tag.trimmed
            guard !clean.isEmpty else { continue }
            if seen.insert(clean.lowercased()).inserted {
                result.append(clean)
            }
        }
        return result
    }

    /// Parses a comma- or semicolon-separated tag list.
    static func parseTags(_ text: String) -> [String] {
        normalizedTags(text.components(separatedBy: CharacterSet(charactersIn: ",;")))
    }
}

/// The standard fields, in display order.
enum MetadataField: String, CaseIterable, Identifiable, Sendable {
    case title, composer, catalogueNumber, scoring, key, genre, tags, notes

    var id: String { rawValue }

    var label: String {
        switch self {
        case .title: return "Title"
        case .composer: return "Composer"
        case .catalogueNumber: return "Catalogue"
        case .scoring: return "Voicing"
        case .key: return "Key"
        case .genre: return "Genre"
        case .tags: return "Tags"
        case .notes: return "Notes"
        }
    }

    func value(in metadata: ScoreMetadata) -> String {
        switch self {
        case .title: return metadata.title
        case .composer: return metadata.composer
        case .catalogueNumber: return metadata.catalogueNumber
        case .scoring: return metadata.scoring
        case .key: return metadata.key
        case .genre: return metadata.genre
        case .tags: return metadata.tags.joined(separator: ", ")
        case .notes: return metadata.notes
        }
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
