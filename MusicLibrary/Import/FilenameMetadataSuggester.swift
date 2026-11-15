import Foundation

/// Guesses metadata from file names such as
/// "Bach – Jesu, meine Freude (BWV 227).pdf" or "Mozart - Ave verum corpus K618.pdf".
struct FilenameMetadataSuggester: MetadataSuggester {
    func suggest(for input: SuggestionInput) async -> MetadataSuggestion? {
        MetadataSuggestion(metadata: Self.parse(fileName: input.fileName), source: "File name")
    }

    static func parse(fileName: String) -> ScoreMetadata {
        var name = (fileName as NSString).deletingPathExtension
        name = name.replacingOccurrences(of: "_", with: " ")
        name = collapseWhitespace(name)

        var metadata = ScoreMetadata()
        if let found = findCatalogueNumber(in: name) {
            metadata.catalogueNumber = found.normalized
            name.removeSubrange(found.range)
        }
        name = cleanUp(name)

        for separator in [" – ", " — ", " - "] {
            if let range = name.range(of: separator) {
                metadata.composer = cleanUp(String(name[..<range.lowerBound]))
                metadata.title = cleanUp(String(name[range.upperBound...]))
                break
            }
        }
        if metadata.title.isEmpty && metadata.composer.isEmpty {
            metadata.title = name
        }
        return metadata.normalized()
    }

    // MARK: - Catalogue numbers

    private static let canonicalPrefixes: [String: String] = [
        "bwv": "BWV", "buxwv": "BuxWV", "hwv": "HWV", "rv": "RV", "swv": "SWV", "twv": "TWV",
        "woo": "WoO", "kv": "KV", "k": "K.", "op": "Op.", "hob": "Hob.", "d": "D.",
    ]

    private static let catalogueRegex: NSRegularExpression = {
        let pattern = #"\b(BWV|BuxWV|HWV|RV|SWV|TWV|WoO|KV|Hob|Op|K|D)\.?\s*([IVXLC]+[a-z]?:\s*\d+[a-z]?|\d+[a-z]?(?:\s*(?:No|Nr)\.?\s*\d+[a-z]?)?)\b"#
        // swiftlint:disable:next force_try
        return try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }()

    private static let numberRegex: NSRegularExpression = {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: #"\s*\b(?:No|Nr)\.?\s*"#, options: [.caseInsensitive])
    }()

    struct CatalogueMatch {
        let range: Range<String.Index>
        let normalized: String
    }

    static func findCatalogueNumber(in text: String) -> CatalogueMatch? {
        let nsRange = NSRange(text.startIndex..., in: text)
        guard let match = catalogueRegex.firstMatch(in: text, options: [], range: nsRange),
              let whole = Range(match.range, in: text),
              let prefixRange = Range(match.range(at: 1), in: text),
              let restRange = Range(match.range(at: 2), in: text) else {
            return nil
        }
        let prefix = canonicalPrefixes[text[prefixRange].lowercased()] ?? String(text[prefixRange])
        var rest = String(text[restRange])
        let restNS = NSRange(rest.startIndex..., in: rest)
        rest = numberRegex.stringByReplacingMatches(in: rest, options: [], range: restNS, withTemplate: " No. ")
        rest = rest.replacingOccurrences(of: ": ", with: ":")
        return CatalogueMatch(range: whole, normalized: collapseWhitespace("\(prefix) \(rest)"))
    }

    // MARK: - Helpers

    private static func collapseWhitespace(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    private static func cleanUp(_ text: String) -> String {
        var result = text
        for empty in ["()", "[]", "( )", "[ ]"] {
            result = result.replacingOccurrences(of: empty, with: "")
        }
        result = collapseWhitespace(result)
        let edgeJunk = CharacterSet.whitespaces.union(CharacterSet(charactersIn: "-–—,;:"))
        return result.trimmingCharacters(in: edgeJunk)
    }
}
