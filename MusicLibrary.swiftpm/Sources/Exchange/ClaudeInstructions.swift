import Foundation

/// Text embedded in exports so Claude knows what to do with the file.
/// Kept in sync with docs/claude-labelling.md.
enum ClaudeInstructions {
    /// The short message the user sends with the file.
    static let chatMessage = """
    Please label the scores in the attached Quire export. Follow the "instructionsForClaude" in the file and reply with only the JSON.
    """

    static let labelling = """
    You are helping catalogue a personal sheet-music library (much of it choral and church music, but it can be anything). Each entry in "scores" is one PDF. "file" is its original file name and "text" is text read from its first page or two; it may contain OCR mistakes, page headers, copyright lines or lyrics.

    For every entry, fill in "metadata" as accurately as you can:
    - title: the piece's title as it is usually catalogued, e.g. "Hear my prayer" or "Magnificat and Nunc dimittis in G". Not the composer or publisher.
    - composer: "Surname, Forenames", e.g. "Stanford, Charles Villiers", "Bach, Johann Sebastian", "Vaughan Williams, Ralph" (some surnames have two words). Just the surname if the forenames aren't known. Use "Anonymous" or "Traditional" where that applies. For an arrangement, put the original composer here and the arranger in notes.
    - catalogueNumber: only a composer's catalogue number, e.g. "BWV 147", "K. 618", "HWV 258", "RV 589", "BuxWV 78", "Op. 51 No. 1". Never an IMSLP or CPDL number, nor a publisher, plate or page number. Usually "".
    - scoring: voicing or instrumentation in short form, e.g. "SATB", "SATB + organ", "SSA", "SATB divisi", "Unison + organ", "Organ", "Piano".
    - key: e.g. "G major", "D minor", or "" if unknown.
    - genre: one of Anthem, Canticle, Motet, Mass, Psalm, Hymn, Responses, Carol, Introit, Song, Organ, Instrumental, Other. Every Magnificat, Nunc dimittis, Te Deum and Jubilate is a Canticle.
    - tags: leave out. The owner adds tags by hand.
    - notes: anything useful that fits nowhere else (arranger, editor, source of the text). Keep it short.
    - extra: keep any existing custom fields and fill them in if you can. Don't invent new ones.

    Rules:
    1. Keep "id", "sha256" and "file" exactly as given so the app can match your answers. Leave "text" out of your reply.
    2. Don't guess wildly. If you're unsure of a field, give your best answer with a lower confidence. If you have no idea, use "".
    3. Add "confidence": an object with a number from 0 to 1 for each field you filled, e.g. {"title": 0.95, "composer": 0.6}.
    4. Add "flags": a list of short notes for anything the owner should check, e.g. "Two pieces in one PDF" or "Composer unclear: Tallis or Byrd?". Use [] if there's nothing.
    5. Optionally add "suggestedFileName" in the form "Surname – Title (Catalogue).pdf".
    6. Reply with one JSON object with the same "schema" and "version" as this file and a "scores" array, and nothing else. Leave out "instructionsForClaude".
    """
}
