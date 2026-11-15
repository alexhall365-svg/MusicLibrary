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
    /// Notes about anything that should be checked.
    var flags: [String] = []
    var source: String
}

/// One interface for every source of metadata suggestions.
///
/// Sources: `FilenameMetadataSuggester` (file names), `AppleIntelligenceSuggester`
/// (on-device model, iOS 26+), and JSON from Claude via the exchange format.
/// Later: an optional Anthropic API key stored in the Keychain.
protocol MetadataSuggester: Sendable {
    func suggest(for input: SuggestionInput) async -> MetadataSuggestion?
}
