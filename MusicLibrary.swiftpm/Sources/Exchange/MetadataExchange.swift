import Foundation

// The JSON format shared between the app and Claude. Documented in
// docs/metadata-schema.md. Decoding is deliberately forgiving because the JSON
// is often written by hand or by a language model.

struct MetadataExchangeFile: Codable, Equatable {
    static let schemaIdentifier = "music-library-metadata"
    static let currentVersion = 1

    var schema: String
    var version: Int
    var exportedAt: Date?
    var generator: String?
    var instructionsForClaude: String?
    var scores: [ExchangeEntry]

    init(
        scores: [ExchangeEntry],
        exportedAt: Date? = Date(),
        generator: String? = nil,
        instructionsForClaude: String? = nil
    ) {
        self.schema = Self.schemaIdentifier
        self.version = Self.currentVersion
        self.exportedAt = exportedAt
        self.generator = generator
        self.instructionsForClaude = instructionsForClaude
        self.scores = scores
    }

    enum CodingKeys: String, CodingKey {
        case schema, version, exportedAt, generator, instructionsForClaude, scores
    }
}

extension MetadataExchangeFile {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schema = (try? container.decodeIfPresent(String.self, forKey: .schema)) ?? Self.schemaIdentifier
        version = (try? container.decodeIfPresent(Int.self, forKey: .version)) ?? Self.currentVersion
        exportedAt = (try? container.decodeIfPresent(Date.self, forKey: .exportedAt)) ?? nil
        generator = (try? container.decodeIfPresent(String.self, forKey: .generator)) ?? nil
        instructionsForClaude = (try? container.decodeIfPresent(String.self, forKey: .instructionsForClaude)) ?? nil
        scores = try container.decode([ExchangeEntry].self, forKey: .scores)
    }
}

/// One score in the exchange file.
struct ExchangeEntry: Codable, Equatable {
    /// The app's id for the score (UUID string).
    var id: String?
    /// Original file name.
    var file: String?
    /// SHA-256 of the PDF; the most reliable way to match.
    var sha256: String?
    var pageCount: Int?
    /// Text from the first pages (export only; ignored on import).
    var text: String?
    var metadata: ExchangeMetadata
    /// 0...1 per field name. "*" applies to every field.
    var confidence: [String: Double]?
    /// Things for the user to check.
    var flags: [String]?
    var suggestedFileName: String?

    init(
        id: String? = nil,
        file: String? = nil,
        sha256: String? = nil,
        pageCount: Int? = nil,
        text: String? = nil,
        metadata: ExchangeMetadata = ExchangeMetadata(),
        confidence: [String: Double]? = nil,
        flags: [String]? = nil,
        suggestedFileName: String? = nil
    ) {
        self.id = id
        self.file = file
        self.sha256 = sha256
        self.pageCount = pageCount
        self.text = text
        self.metadata = metadata
        self.confidence = confidence
        self.flags = flags
        self.suggestedFileName = suggestedFileName
    }

    enum CodingKeys: String, CodingKey {
        case id, file, sha256, pageCount, text, metadata, confidence, flags, suggestedFileName
    }

    func confidence(for field: MetadataField) -> Double? {
        confidence?[field.rawValue] ?? confidence?["*"]
    }
}

extension ExchangeEntry {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = Self.string(container, .id)
        file = Self.string(container, .file)
        sha256 = Self.string(container, .sha256)
        pageCount = (try? container.decodeIfPresent(Int.self, forKey: .pageCount)) ?? nil
        text = Self.string(container, .text)
        if container.contains(.metadata) {
            metadata = try container.decode(ExchangeMetadata.self, forKey: .metadata)
        } else {
            // Accept the fields directly on the entry, too.
            metadata = try ExchangeMetadata(from: decoder)
        }
        if let perField = try? container.decodeIfPresent([String: FlexibleConfidence].self, forKey: .confidence) {
            confidence = perField.mapValues(\.value)
        } else if let overall = try? container.decodeIfPresent(FlexibleConfidence.self, forKey: .confidence) {
            confidence = ["*": overall.value]
        } else {
            confidence = nil
        }
        flags = (try? container.decodeIfPresent(FlexibleStringList.self, forKey: .flags))?.values
        suggestedFileName = Self.string(container, .suggestedFileName)
    }

    private static func string(_ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> String? {
        if let value = try? container.decodeIfPresent(String.self, forKey: key) { return value }
        if let number = try? container.decodeIfPresent(Int.self, forKey: key) { return String(number) }
        return nil
    }
}

/// Metadata in the exchange file. A missing (or null) field means "leave as is";
/// an empty string clears the field.
struct ExchangeMetadata: Codable, Equatable {
    var title: String?
    var composer: String?
    var catalogueNumber: String?
    var scoring: String?
    var key: String?
    var genre: String?
    var tags: [String]?
    var notes: String?
    var extra: [String: String]?

    init(
        title: String? = nil,
        composer: String? = nil,
        catalogueNumber: String? = nil,
        scoring: String? = nil,
        key: String? = nil,
        genre: String? = nil,
        tags: [String]? = nil,
        notes: String? = nil,
        extra: [String: String]? = nil
    ) {
        self.title = title
        self.composer = composer
        self.catalogueNumber = catalogueNumber
        self.scoring = scoring
        self.key = key
        self.genre = genre
        self.tags = tags
        self.notes = notes
        self.extra = extra
    }

    init(_ metadata: ScoreMetadata) {
        self.init(
            title: metadata.title,
            composer: metadata.composer,
            catalogueNumber: metadata.catalogueNumber,
            scoring: metadata.scoring,
            key: metadata.key,
            genre: metadata.genre,
            tags: metadata.tags,
            notes: metadata.notes,
            extra: metadata.extra.isEmpty ? nil : metadata.extra
        )
    }

    enum CodingKeys: String, CodingKey {
        case title, composer, catalogueNumber, scoring, key, genre, tags, notes, extra
    }

    /// Returns `base` with every provided field replaced.
    func applied(to base: ScoreMetadata) -> ScoreMetadata {
        var result = base
        if let title { result.title = title }
        if let composer { result.composer = composer }
        if let catalogueNumber {
            // New values from outside must be real catalogue numbers (never IMSLP numbers).
            result.catalogueNumber = catalogueNumber.trimmed == base.catalogueNumber
                ? catalogueNumber : CatalogueNumbers.strict(catalogueNumber)
        }
        if let scoring { result.scoring = scoring }
        if let key { result.key = key }
        if let genre { result.genre = genre }
        if let tags { result.tags = tags }
        if let notes { result.notes = notes }
        if let extra { result.extra.merge(extra) { _, new in new } }
        return result.normalized()
    }
}

extension ExchangeMetadata {
    /// Accepts a few common alternative field names.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyCodingKey.self)
        func string(_ names: String...) -> String? {
            for name in names {
                let key = AnyCodingKey(name)
                if let value = try? container.decodeIfPresent(String.self, forKey: key) { return value }
                if let number = try? container.decodeIfPresent(Double.self, forKey: key) {
                    return number.rounded() == number ? String(Int(number)) : String(number)
                }
            }
            return nil
        }
        title = string("title", "name")
        composer = string("composer")
        catalogueNumber = string("catalogueNumber", "catalogue", "catalogNumber", "catalog")
        scoring = string("scoring", "voicing", "instrumentation")
        key = string("key")
        genre = string("genre")
        notes = string("notes")
        tags = (try? container.decodeIfPresent(FlexibleStringList.self, forKey: AnyCodingKey("tags")))?.values
        extra = (try? container.decodeIfPresent([String: String].self, forKey: AnyCodingKey("extra"))) ?? nil
    }
}

// MARK: - Forgiving decoding helpers

struct AnyCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init(_ string: String) {
        stringValue = string
    }

    init?(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }
}

/// A confidence given as 0.8, 80, "0.8" or "high"/"medium"/"low".
struct FlexibleConfidence: Decodable {
    let value: Double

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Double.self) {
            value = Self.clamp(number > 1 ? number / 100 : number)
        } else if let text = try? container.decode(String.self) {
            switch text.trimmed.lowercased() {
            case "high", "certain", "very high": value = 0.9
            case "medium", "med", "moderate": value = 0.6
            case "low", "very low", "guess": value = 0.3
            default:
                let number = Double(text.trimmed) ?? 0.5
                value = Self.clamp(number > 1 ? number / 100 : number)
            }
        } else {
            throw DecodingError.typeMismatch(
                Double.self, .init(codingPath: decoder.codingPath, debugDescription: "Not a confidence"))
        }
    }

    private static func clamp(_ number: Double) -> Double { min(max(number, 0), 1) }
}

/// A list given as ["a", "b"] or as "a, b".
struct FlexibleStringList: Decodable {
    let values: [String]

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let list = try? container.decode([String].self) {
            values = list
        } else if let text = try? container.decode(String.self) {
            values = text.components(separatedBy: CharacterSet(charactersIn: ",;"))
                .map(\.trimmed)
                .filter { !$0.isEmpty }
        } else {
            values = []
        }
    }
}
