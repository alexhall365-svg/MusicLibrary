import Foundation

/// Catalogue numbers: only real composer catalogues (BWV, K., Op., HWV, RV…),
/// never IMSLP numbers, publisher numbers or plate numbers.
enum CatalogueNumbers {
    /// True for things that are definitely not catalogue numbers.
    static func isNotACatalogueNumber(_ text: String) -> Bool {
        let folded = ComposerNames.fold(text)
        return folded.contains("imslp") || folded.contains("pmlp") || folded.contains("cpdl")
    }

    /// Light tidying for any source, including typing: removes IMSLP-style
    /// numbers and standardises recognised catalogue numbers ("bwv227" → "BWV 227").
    static func tidy(_ text: String) -> String {
        let clean = text.trimmed
        guard !clean.isEmpty, !isNotACatalogueNumber(clean) else { return "" }
        if let match = FilenameMetadataSuggester.findCatalogueNumber(in: clean),
           clean[match.range].count >= clean.count - 2 {
            return match.normalized
        }
        return clean
    }

    /// Strict version for automatic sources (Apple Intelligence, import packages, file
    /// names): returns a recognised catalogue number or nothing.
    static func strict(_ text: String) -> String {
        let clean = text.trimmed
        guard !clean.isEmpty, !isNotACatalogueNumber(clean) else { return "" }
        return FilenameMetadataSuggester.findCatalogueNumber(in: clean)?.normalized ?? ""
    }
}

/// Voicing and instrumentation in one standard form, e.g. "SATB + organ".
enum ScoringNames {
    private static let instruments: [String: String] = [
        "organ": "organ", "org": "organ", "piano": "piano", "pf": "piano", "pno": "piano",
        "pianoforte": "piano", "orchestra": "orchestra", "orch": "orchestra", "strings": "strings",
        "brass": "brass", "harp": "harp", "continuo": "continuo", "bc": "continuo",
        "keyboard": "keyboard", "kbd": "keyboard", "guitar": "guitar", "flute": "flute",
        "oboe": "oboe", "clarinet": "clarinet", "trumpet": "trumpet", "trumpets": "trumpets",
        "tpt": "trumpet", "timpani": "timpani", "percussion": "percussion", "perc": "percussion",
        "cello": "cello", "violin": "violin", "handbells": "handbells", "harpsichord": "harpsichord",
    ]

    /// Words that add nothing to the voicing.
    private static let fillers: Set<String> = [
        "and", "with", "plus", "choir", "chorus", "mixed", "voices", "voice", "acc", "accomp",
        "accompaniment", "accompanied", "for", "a", "cappella", "capella", "unaccompanied",
    ]

    private static let voicesRegex = try! NSRegularExpression(pattern: "^[satb]{2,8}$")
    private static let partsRegex = try! NSRegularExpression(pattern: "^([1-8])-?part$")

    /// The standard form, or the text as typed if it can't be fully understood.
    static func normalized(_ raw: String) -> String {
        let trimmed = raw.trimmed
        guard !trimmed.isEmpty else { return "" }
        let folded = ComposerNames.fold(trimmed)
        let tokens = folded
            .components(separatedBy: CharacterSet(charactersIn: "+&,/;()").union(.whitespaces))
            .filter { !$0.isEmpty }

        var voices: [String] = []
        var found: [String] = []
        var unison = false
        var parts: String?
        var divisi = false
        for token in tokens {
            let word = token.replacingOccurrences(of: ".", with: "")
            if word.isEmpty || fillers.contains(word) { continue }
            if matches(voicesRegex, word) {
                voices.append(word.uppercased())
            } else if word == "unison" {
                unison = true
            } else if let match = partsRegex.firstMatch(in: word, range: NSRange(word.startIndex..., in: word)),
                      let range = Range(match.range(at: 1), in: word) {
                parts = "\(word[range])-part"
            } else if word == "divisi" || word == "div" {
                divisi = true
            } else if let instrument = instruments[word] {
                if !found.contains(instrument) { found.append(instrument) }
            } else {
                // Something we don't recognise: keep what was typed.
                return trimmed
            }
        }

        var voicing = voices.joined(separator: " ")
        if voicing.isEmpty, unison { voicing = "Unison" }
        if voicing.isEmpty, let parts { voicing = parts }
        if divisi, !voicing.isEmpty { voicing += " divisi" }

        if voicing.isEmpty {
            guard let first = found.first else { return trimmed }
            let capitalised = first.prefix(1).uppercased() + String(first.dropFirst())
            return ([capitalised] + Array(found.dropFirst())).joined(separator: " + ")
        }
        return ([voicing] + found).joined(separator: " + ")
    }

    static func groupingKey(_ raw: String) -> String {
        ComposerNames.fold(normalized(raw))
    }

    private static func matches(_ regex: NSRegularExpression, _ text: String) -> Bool {
        regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }
}

/// Genres in one standard list, with all Magnificats and Nunc dimittises
/// (and the other canticles) under "Canticle".
enum GenreNames {
    static let standard = [
        "Anthem", "Canticle", "Motet", "Mass", "Psalm", "Hymn", "Responses", "Carol",
        "Introit", "Song", "Organ", "Instrumental", "Other",
    ]

    private static let synonyms: [String: String] = [
        "anthem": "Anthem", "full anthem": "Anthem", "verse anthem": "Anthem",
        "canticle": "Canticle", "evening canticles": "Canticle", "morning canticles": "Canticle",
        "evening service": "Canticle", "morning service": "Canticle", "service": "Canticle",
        "mag and nunc": "Canticle", "mag & nunc": "Canticle", "magnificat": "Canticle",
        "nunc dimittis": "Canticle", "te deum": "Canticle", "jubilate": "Canticle",
        "motet": "Motet", "mass": "Mass", "mass setting": "Mass", "communion service": "Mass",
        "eucharist": "Mass", "missa": "Mass", "psalm": "Psalm", "psalm chant": "Psalm",
        "anglican chant": "Psalm", "chant": "Psalm", "hymn": "Hymn", "hymn tune": "Hymn",
        "responses": "Responses", "preces": "Responses", "preces and responses": "Responses",
        "carol": "Carol", "christmas carol": "Carol", "introit": "Introit", "song": "Song",
        "part song": "Song", "partsong": "Song", "part-song": "Song", "organ": "Organ",
        "organ voluntary": "Organ", "voluntary": "Organ", "instrumental": "Instrumental",
        "other": "Other",
    ]

    /// Titles that are always canticles.
    private static let canticleTitleWords = [
        "magnificat", "nunc dimittis", "mag and nunc", "mag & nunc", "te deum", "jubilate",
        "benedicite", "evening service", "morning service",
    ]

    static func normalized(_ raw: String, title: String) -> String {
        let foldedTitle = ComposerNames.fold(title)
        if canticleTitleWords.contains(where: { foldedTitle.contains($0) }) { return "Canticle" }
        let clean = raw.trimmed
        guard !clean.isEmpty else { return "" }
        let folded = ComposerNames.fold(clean)
        if let standard = synonyms[folded] { return standard }
        if folded.hasSuffix("s"), let standard = synonyms[String(folded.dropLast())] { return standard }
        return clean.prefix(1).uppercased() + clean.dropFirst()
    }
}
