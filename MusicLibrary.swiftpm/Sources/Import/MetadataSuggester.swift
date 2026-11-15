import Foundation

/// What a suggester can look at.
struct SuggestionInput: Sendable {
    var fileName: String
    var pdfTitle: String?
    var pdfAuthor: String?
    var extractedText: String?
}

struct MetadataSuggestion: Sendable, Equatable {
    var metadata: ScoreMetadata
    /// Confidence 0...1 per `MetadataField.rawValue`.
    var confidence: [String: Double] = [:]
    var source: String
}

/// One interface for every source of metadata suggestions.
///
/// Today: `FilenameMetadataSuggester` at import, plus JSON from Claude (handled by
/// the exchange format). Later: Apple's on-device Foundation Models where the
/// device supports it, and an optional Anthropic API key stored in the Keychain.
protocol MetadataSuggester: Sendable {
    func suggest(for input: SuggestionInput) async -> MetadataSuggestion?
}
