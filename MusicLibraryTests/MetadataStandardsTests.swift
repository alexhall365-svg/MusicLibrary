import XCTest
@testable import MusicLibrary

final class MetadataStandardsTests: XCTestCase {
    // MARK: Composers

    func testBachVariantsBecomeOneName() {
        for variant in ["Bach", "BACH", "J.S. Bach", "JS Bach", "J. S. Bach", "Bach, JS", "Bach, J.S.",
                        "Bach J.S.", "Johann Sebastian Bach", "bach, johann sebastian"] {
            XCTAssertEqual(ComposerNames.normalized(variant), "Bach, Johann Sebastian", variant)
        }
        XCTAssertEqual(ComposerNames.normalized("C.P.E. Bach"), "Bach, Carl Philipp Emanuel")
        XCTAssertEqual(ComposerNames.normalized("Bach, CPE"), "Bach, Carl Philipp Emanuel")
    }

    func testMultiWordSurnames() {
        for variant in ["Vaughan Williams", "Ralph Vaughan Williams", "R. Vaughan Williams",
                        "Vaughan Williams, R.", "Williams, Ralph Vaughan", "RVW Vaughan Williams"] where variant != "RVW Vaughan Williams" {
            XCTAssertEqual(ComposerNames.normalized(variant), "Vaughan Williams, Ralph", variant)
        }
        XCTAssertEqual(ComposerNames.normalized("Andrew Lloyd Webber"), "Lloyd Webber, Andrew")
        XCTAssertEqual(ComposerNames.normalized("Peter Maxwell Davies"), "Maxwell Davies, Peter")
        XCTAssertEqual(ComposerNames.normalized("Josquin"), "Josquin des Prez")
    }

    func testParticlesAndAliases() {
        XCTAssertEqual(ComposerNames.normalized("Ludwig van Beethoven"), "Beethoven, Ludwig van")
        XCTAssertEqual(ComposerNames.normalized("Tomás Luis de Victoria"), "Victoria, Tomás Luis de")
        XCTAssertEqual(ComposerNames.normalized("Orlando di Lasso"), "Lassus, Orlande de")
        XCTAssertEqual(ComposerNames.normalized("Palestrina"), "Palestrina, Giovanni Pierluigi da")
        XCTAssertEqual(ComposerNames.normalized("Faure"), "Fauré, Gabriel")
        XCTAssertEqual(ComposerNames.normalized("Rachmaninov"), "Rachmaninoff, Sergei")
        XCTAssertEqual(ComposerNames.normalized("Felix Mendelssohn Bartholdy"), "Mendelssohn, Felix")
        XCTAssertEqual(ComposerNames.normalized("Saint Saens"), "Saint-Saëns, Camille")
    }

    func testUnknownComposersAreFormattedNotInvented() {
        XCTAssertEqual(ComposerNames.normalized("Grayston Ives"), "Ives, Grayston")
        XCTAssertEqual(ComposerNames.normalized("jane smith"), "Smith, Jane")
        XCTAssertEqual(ComposerNames.normalized("Smith, JA"), "Smith, J. A.")
        XCTAssertEqual(ComposerNames.normalized("Smith"), "Smith")
        XCTAssertEqual(ComposerNames.normalized("anon."), "Anonymous")
        XCTAssertEqual(ComposerNames.normalized("Trad"), "Traditional")
        XCTAssertEqual(ComposerNames.normalized("Byrd & Tallis"), "Byrd & Tallis")
        XCTAssertEqual(ComposerNames.normalized(""), "")
    }

    // MARK: Catalogue numbers

    func testCatalogueNumbers() {
        XCTAssertEqual(CatalogueNumbers.tidy("IMSLP12345"), "")
        XCTAssertEqual(CatalogueNumbers.tidy("bwv227"), "BWV 227")
        XCTAssertEqual(CatalogueNumbers.tidy("Op 81"), "Op. 81")
        XCTAssertEqual(CatalogueNumbers.tidy("Z 15"), "Z. 15")
        XCTAssertEqual(CatalogueNumbers.strict("Novello 29"), "")
        XCTAssertEqual(CatalogueNumbers.strict("BuxWV 78 (cantata)"), "BuxWV 78")
        XCTAssertEqual(CatalogueNumbers.strict("PMLP71061"), "")
    }

    func testIMSLPFileNamesAreCleaned() {
        let metadata = FilenameMetadataSuggester.parse(fileName: "IMSLP31209-PMLP71061-Bach - Jesu meine Freude BWV227.pdf")
        XCTAssertEqual(metadata.composer, "Bach, Johann Sebastian")
        XCTAssertEqual(metadata.title, "Jesu meine Freude")
        XCTAssertEqual(metadata.catalogueNumber, "BWV 227")
    }

    // MARK: Voicing

    func testVoicingVariantsGroupTogether() {
        for variant in ["SATB + organ", "satb and organ", "S.A.T.B. & Organ", "SATB/org.", "SATB choir with organ accompaniment"] {
            XCTAssertEqual(ScoringNames.normalized(variant), "SATB + organ", variant)
        }
        XCTAssertEqual(ScoringNames.normalized("SATB a cappella"), "SATB")
        XCTAssertEqual(ScoringNames.normalized("ssa, piano"), "SSA + piano")
        XCTAssertEqual(ScoringNames.normalized("SATB divisi"), "SATB divisi")
        XCTAssertEqual(ScoringNames.normalized("unison and organ"), "Unison + organ")
        XCTAssertEqual(ScoringNames.normalized("organ"), "Organ")
        XCTAssertEqual(ScoringNames.normalized("SATB + optional descant"), "SATB + optional descant",
                       "Anything not understood is kept as typed")
    }

    // MARK: Genres

    func testGenresAndCanticles() {
        XCTAssertEqual(GenreNames.normalized("anthems", title: "Hear my prayer"), "Anthem")
        XCTAssertEqual(GenreNames.normalized("Evening Service", title: "Service in G"), "Canticle")
        XCTAssertEqual(GenreNames.normalized("", title: "Magnificat and Nunc dimittis in G"), "Canticle")
        XCTAssertEqual(GenreNames.normalized("Anthem", title: "Nunc dimittis (Collegium Regale)"), "Canticle")
        XCTAssertEqual(GenreNames.normalized("Motets", title: "Ave verum corpus"), "Motet")
        XCTAssertEqual(GenreNames.normalized("requiem", title: "Requiem"), "Requiem")
    }

    func testNormalizedMetadataAppliesAllStandards() {
        let metadata = ScoreMetadata(
            title: "Magnificat in G", composer: "C. V. Stanford", catalogueNumber: "IMSLP99",
            scoring: "satb & organ", genre: "").normalized()
        XCTAssertEqual(metadata.composer, "Stanford, Charles Villiers")
        XCTAssertEqual(metadata.catalogueNumber, "")
        XCTAssertEqual(metadata.scoring, "SATB + organ")
        XCTAssertEqual(metadata.genre, "Canticle")
    }
}
