import XCTest
@testable import MusicLibrary

final class FilenameMetadataSuggesterTests: XCTestCase {
    func testComposerTitleAndCatalogueInBrackets() {
        let metadata = FilenameMetadataSuggester.parse(fileName: "Bach – Jesu, meine Freude (BWV 227).pdf")
        XCTAssertEqual(metadata.composer, "Bach, Johann Sebastian")
        XCTAssertEqual(metadata.title, "Jesu, meine Freude")
        XCTAssertEqual(metadata.catalogueNumber, "BWV 227")
    }

    func testHyphenSeparatorAndKöchelWithoutSpace() {
        let metadata = FilenameMetadataSuggester.parse(fileName: "Mozart - Ave verum corpus K618.pdf")
        XCTAssertEqual(metadata.composer, "Mozart, Wolfgang Amadeus")
        XCTAssertEqual(metadata.title, "Ave verum corpus")
        XCTAssertEqual(metadata.catalogueNumber, "K. 618")
    }

    func testUnderscoresWithoutSeparatorBecomeTitle() {
        let metadata = FilenameMetadataSuggester.parse(fileName: "Stanford_Magnificat_in_G.pdf")
        XCTAssertEqual(metadata.title, "Stanford Magnificat in G")
        XCTAssertEqual(metadata.composer, "")
        XCTAssertEqual(metadata.catalogueNumber, "")
    }

    func testOpusWithNumberIsNormalised() {
        let metadata = FilenameMetadataSuggester.parse(fileName: "Brahms - Warum ist das Licht gegeben op 74 no 1.pdf")
        XCTAssertEqual(metadata.composer, "Brahms, Johannes")
        XCTAssertEqual(metadata.title, "Warum ist das Licht gegeben")
        XCTAssertEqual(metadata.catalogueNumber, "Op. 74 No. 1")
    }

    func testLowercaseCatalogueIsNormalised() {
        XCTAssertEqual(FilenameMetadataSuggester.findCatalogueNumber(in: "cantata bwv147")?.normalized, "BWV 147")
        XCTAssertEqual(FilenameMetadataSuggester.findCatalogueNumber(in: "Hob. XXII:9 Mass")?.normalized, "Hob. XXII:9")
    }

    func testWordsStartingWithCatalogueLettersAreNotMatched() {
        XCTAssertNil(FilenameMetadataSuggester.findCatalogueNumber(in: "Kyrie eleison"))
        XCTAssertNil(FilenameMetadataSuggester.findCatalogueNumber(in: "Magnificat in D"))
    }
}
