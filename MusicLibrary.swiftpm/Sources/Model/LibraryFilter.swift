import Foundation

enum ScoreSort: String, CaseIterable, Identifiable {
    case title, composer, catalogue, dateAdded, recentlyOpened

    var id: String { rawValue }

    var label: String {
        switch self {
        case .title: return "Title"
        case .composer: return "Composer"
        case .catalogue: return "Catalogue Number"
        case .dateAdded: return "Date Added"
        case .recentlyOpened: return "Recently Opened"
        }
    }
}

enum FacetKind: String, CaseIterable, Identifiable, Hashable {
    case composer, genre, scoring, tag

    var id: String { rawValue }

    var label: String {
        switch self {
        case .composer: return "Composer"
        case .genre: return "Genre"
        case .scoring: return "Voicing"
        case .tag: return "Tag"
        }
    }

    var pluralLabel: String {
        switch self {
        case .composer: return "Composers"
        case .genre: return "Genres"
        case .scoring: return "Voicing & Instruments"
        case .tag: return "Tags"
        }
    }

    var systemImage: String {
        switch self {
        case .composer: return "person.2"
        case .genre: return "square.grid.2x2"
        case .scoring: return "pianokeys"
        case .tag: return "tag"
        }
    }
}

struct Facet: Hashable {
    let kind: FacetKind
    let value: String
}

struct FacetValue: Identifiable, Equatable {
    let value: String
    let count: Int
    var id: String { value }
}

/// Searching, filtering and sorting of scores. Kept free of UI so it can be tested.
enum LibraryFilter {
    static func apply(_ scores: [Score], search: String, facet: Facet?, sort: ScoreSort) -> [Score] {
        var result = scores
        if let facet {
            result = result.filter { matches($0, facet: facet) }
        }
        if !search.trimmed.isEmpty {
            result = result.filter { matches($0, search: search) }
        }
        return sorted(result, by: sort)
    }

    /// Every word in the search must appear in at least one field.
    /// Case and accents are ignored, so "faure" finds "Fauré".
    static func matches(_ score: Score, search: String) -> Bool {
        let tokens = search.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !tokens.isEmpty else { return true }
        let fields = [
            score.displayTitle, score.composer, score.catalogueNumber, score.scoring,
            score.key, score.genre, score.notes, score.originalFileName,
        ] + score.tags + Array(score.extraFields.values)
        return tokens.allSatisfy { token in
            fields.contains { $0.range(of: token, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
    }

    static func matches(_ score: Score, facet: Facet) -> Bool {
        values(of: facet.kind, for: score).contains { same($0, facet.value) }
    }

    static func sorted(_ scores: [Score], by sort: ScoreSort) -> [Score] {
        switch sort {
        case .title:
            return scores.sorted { compare($0.displayTitle, $1.displayTitle) }
        case .composer:
            return scores.sorted { a, b in
                if a.composer.isEmpty != b.composer.isEmpty { return !a.composer.isEmpty }
                if !same(a.composer, b.composer) { return compare(a.composer, b.composer) }
                return compare(a.displayTitle, b.displayTitle)
            }
        case .catalogue:
            return scores.sorted { a, b in
                if a.catalogueNumber.isEmpty != b.catalogueNumber.isEmpty { return !a.catalogueNumber.isEmpty }
                if !same(a.catalogueNumber, b.catalogueNumber) { return compare(a.catalogueNumber, b.catalogueNumber) }
                return compare(a.displayTitle, b.displayTitle)
            }
        case .dateAdded:
            return scores.sorted { $0.dateAdded > $1.dateAdded }
        case .recentlyOpened:
            return scores.sorted { ($0.lastOpened ?? .distantPast) > ($1.lastOpened ?? .distantPast) }
        }
    }

    /// Distinct values for a facet with how many scores have each, alphabetical.
    static func facetValues(_ kind: FacetKind, in scores: [Score]) -> [FacetValue] {
        var counts: [String: Int] = [:]
        var display: [String: String] = [:]
        for score in scores {
            for value in values(of: kind, for: score) {
                let key = value.lowercased()
                counts[key, default: 0] += 1
                if display[key] == nil { display[key] = value }
            }
        }
        return counts.keys
            .map { FacetValue(value: display[$0] ?? $0, count: counts[$0] ?? 0) }
            .sorted { compare($0.value, $1.value) }
    }

    static func values(of kind: FacetKind, for score: Score) -> [String] {
        let raw: [String]
        switch kind {
        case .composer: raw = [ComposerNames.normalized(score.composer)]
        case .genre: raw = [GenreNames.normalized(score.genre, title: score.title)]
        case .scoring: raw = [ScoringNames.normalized(score.scoring)]
        case .tag: raw = score.tags
        }
        return raw.map(\.trimmed).filter { !$0.isEmpty }
    }

    private static func compare(_ a: String, _ b: String) -> Bool {
        a.localizedStandardCompare(b) == .orderedAscending
    }

    private static func same(_ a: String, _ b: String) -> Bool {
        a.compare(b, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }
}
