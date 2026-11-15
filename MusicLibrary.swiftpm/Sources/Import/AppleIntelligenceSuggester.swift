#if canImport(FoundationModels)
import Foundation
import FoundationModels

/// The structure the on-device model fills in for each score.
@available(iOS 26.0, *)
@Generable
struct GeneratedScoreDetails {
    @Guide(description: "The piece's title as usually catalogued, e.g. 'Hear my prayer' or 'Magnificat and Nunc dimittis in G'. Not the composer or publisher. Empty if unknown.")
    var title: String

    @Guide(description: "The composer as 'Surname, Forenames', e.g. 'Stanford, Charles Villiers' or 'Bach, Johann Sebastian'. 'Anonymous' or 'Traditional' where that applies. Empty if unknown.")
    var composer: String

    @Guide(description: "A standard catalogue number shown in the text or file name, e.g. 'BWV 147', 'K. 618', 'HWV 258', 'Op. 51 No. 1'. Empty if none is shown.")
    var catalogueNumber: String

    @Guide(description: "Voicing or instrumentation in short form, e.g. 'SATB', 'SATB + organ', 'SSA', 'Unison + organ', 'Organ', 'Piano'. Empty if unknown.")
    var scoring: String

    @Guide(description: "The key, e.g. 'G major' or 'D minor'. Empty if not clear.")
    var key: String

    @Guide(description: "One of: Anthem, Canticle, Motet, Mass, Psalm, Hymn, Responses, Carol, Introit, Song, Organ, Instrumental, Other.")
    var genre: String

    @Guide(description: "Up to four short tags, such as the liturgical season or occasion (Advent, Christmas, Lent, Easter, Evensong, Communion, Wedding, Funeral) or the language (Latin). Empty list if none apply.")
    var tags: [String]

    @Guide(description: "How sure you are about the title and composer, from 0.0 (a guess) to 1.0 (certain).")
    var confidence: Double

    @Guide(description: "A short note if something should be checked, e.g. 'Two pieces in one PDF' or 'Composer unclear'. Empty if nothing.")
    var concern: String
}

/// Suggests metadata with Apple's on-device model. Free, private and offline.
@available(iOS 26.0, *)
struct AppleIntelligenceSuggester: MetadataSuggester {
    static let instructions = """
    You catalogue sheet music for a church and choral music library. You are given a PDF's file name and the text found on its first page or two. The text can contain OCR mistakes, publisher and copyright lines, page headers and lyrics. Identify the piece. Only give information that the text or file name supports, or that you are sure of. Leave a field empty rather than guessing.
    """

    func suggest(for input: SuggestionInput) async -> MetadataSuggestion? {
        let session = LanguageModelSession(instructions: Self.instructions)
        do {
            let response = try await session.respond(
                to: Self.prompt(for: input),
                generating: GeneratedScoreDetails.self,
                options: GenerationOptions(temperature: 0.2)
            )
            let details = response.content
            let metadata = ScoreMetadata(
                title: details.title,
                composer: details.composer,
                catalogueNumber: details.catalogueNumber,
                scoring: details.scoring,
                key: details.key,
                genre: details.genre,
                tags: Array(details.tags.prefix(4))
            )
            let concern = details.concern.trimmed
            return MetadataSuggestion(
                metadata: AutoLabelLogic.cleaned(metadata),
                confidence: ["*": min(max(details.confidence, 0), 1)],
                flags: AutoLabelLogic.isPlaceholder(concern) ? [] : [concern],
                source: "Apple Intelligence"
            )
        } catch {
            print("Apple Intelligence couldn't label \(input.fileName): \(error)")
            return nil
        }
    }

    static func prompt(for input: SuggestionInput) -> String {
        let text = input.extractedText?.trimmed ?? ""
        return """
        File name: \(input.fileName)

        Text from the first pages:
        \(text.isEmpty ? "(no text could be read)" : String(text.prefix(1500)))
        """
    }
}
#endif
