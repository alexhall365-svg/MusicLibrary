import Foundation

enum ExchangeError: LocalizedError, Equatable {
    case empty
    case newerVersion(Int)
    case invalid(String)

    var errorDescription: String? {
        switch self {
        case .empty:
            return "There was nothing to import."
        case .newerVersion(let version):
            return "This file uses format version \(version), which is newer than this app understands (\(MetadataExchangeFile.currentVersion)). Please update the app."
        case .invalid(let detail):
            return "This doesn't look like Quire library details. \(detail)"
        }
    }
}

enum MetadataExchangeCodec {
    static func encode(_ file: MetadataExchangeFile) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(file)
    }

    /// Decodes an exchange file. Also accepts a bare array of entries, and JSON
    /// wrapped in other text (e.g. a chat reply with a ```json code block).
    static func decode(_ data: Data) throws -> MetadataExchangeFile {
        guard !data.isEmpty else { throw ExchangeError.empty }
        var candidates = [data]
        if let text = String(data: data, encoding: .utf8), let inner = extractJSON(from: text), inner != data {
            candidates.append(inner)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var firstError: Error?
        for candidate in candidates {
            do {
                let file = try decoder.decode(MetadataExchangeFile.self, from: candidate)
                return try validated(file)
            } catch let error as ExchangeError {
                throw error
            } catch {
                if firstError == nil { firstError = error }
            }
            if let entries = try? decoder.decode([ExchangeEntry].self, from: candidate) {
                return MetadataExchangeFile(scores: entries, exportedAt: nil)
            }
        }
        throw ExchangeError.invalid(describe(firstError))
    }

    private static func validated(_ file: MetadataExchangeFile) throws -> MetadataExchangeFile {
        if file.version > MetadataExchangeFile.currentVersion {
            throw ExchangeError.newerVersion(file.version)
        }
        return file
    }

    /// The text from the first "{" or "[" to the last matching "}" or "]".
    static func extractJSON(from text: String) -> Data? {
        guard let start = text.firstIndex(where: { $0 == "{" || $0 == "[" }) else { return nil }
        let closer: Character = text[start] == "{" ? "}" : "]"
        guard let end = text.lastIndex(of: closer), end > start else { return nil }
        return Data(text[start...end].utf8)
    }

    private static func describe(_ error: Error?) -> String {
        guard let error = error as? DecodingError else { return "" }
        switch error {
        case .keyNotFound(let key, _):
            return "Missing \"\(key.stringValue)\"."
        case .dataCorrupted(let context):
            return context.debugDescription
        case .typeMismatch(_, let context), .valueNotFound(_, let context):
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            return "Unexpected value at \(path)."
        @unknown default:
            return ""
        }
    }
}
