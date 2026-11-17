import Foundation

/// Pure rules for turning automatic suggestions into library changes.
enum AutoLabelLogic {
    static let uncertaintyThreshold = 0.7

    private static let placeholders: Set<String> = [
        "unknown", "n/a", "na", "none", "not specified", "not given", "not known",
        "unspecified", "-", "–", "?", "empty", "null",
    ]

    static func isPlaceholder(_ value: String) -> Bool {
        let clean = value.trimmed.lowercased()
        return clean.isEmpty || placeholders.contains(clean)
    }

    /// Blanks out "Unknown"-style answers and normalises the rest.
    static func cleaned(_ metadata: ScoreMetadata) -> ScoreMetadata {
        func clean(_ value: String) -> String { isPlaceholder(value) ? "" : value.trimmed }
        var result = metadata
        result.title = clean(metadata.title)
        result.composer = clean(metadata.composer)
        result.catalogueNumber = CatalogueNumbers.strict(clean(metadata.catalogueNumber))
        result.scoring = clean(metadata.scoring)
        result.key = clean(metadata.key)
        result.genre = clean(metadata.genre)
        result.notes = clean(metadata.notes)
        result.tags = metadata.tags.filter { !isPlaceholder($0) }
        return result.normalized()
    }

    /// Fields the suggestion fills in replace the existing values; empty
    /// suggestions leave them alone. Tags are combined. Notes and custom fields
    /// are kept.
    static func merged(_ suggestion: ScoreMetadata, into base: ScoreMetadata) -> ScoreMetadata {
        let suggested = cleaned(suggestion)
        var result = base
        if !suggested.title.isEmpty { result.title = suggested.title }
        if !suggested.composer.isEmpty { result.composer = suggested.composer }
        if !suggested.catalogueNumber.isEmpty { result.catalogueNumber = suggested.catalogueNumber }
        if !suggested.scoring.isEmpty { result.scoring = suggested.scoring }
        if !suggested.key.isEmpty { result.key = suggested.key }
        if !suggested.genre.isEmpty { result.genre = suggested.genre }
        if result.notes.isEmpty { result.notes = suggested.notes }
        result.tags = base.tags + suggested.tags
        return result.normalized()
    }

    static func isUncertain(_ suggestion: MetadataSuggestion) -> Bool {
        let confidence = suggestion.confidence["*"] ?? 1
        return confidence < uncertaintyThreshold || !suggestion.flags.isEmpty
            || suggestion.metadata.isMissingEssentials
    }

    /// An exchange entry so suggestions can go through the normal review screen.
    static func exchangeEntry(
        id: UUID, fileName: String, sha256: String, base: ScoreMetadata, suggestion: MetadataSuggestion
    ) -> ExchangeEntry {
        var flags = suggestion.flags
        if cleaned(suggestion.metadata).isMissingEssentials {
            flags.append("Couldn't identify the title or composer")
        }
        return ExchangeEntry(
            id: id.uuidString,
            file: fileName,
            sha256: sha256,
            metadata: ExchangeMetadata(merged(suggestion.metadata, into: base)),
            confidence: suggestion.confidence,
            flags: flags
        )
    }
}
