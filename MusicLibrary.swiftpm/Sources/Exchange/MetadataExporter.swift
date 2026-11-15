import Foundation

@MainActor
enum MetadataExporter {
    static func entry(for score: Score, includeText: Bool) -> ExchangeEntry {
        ExchangeEntry(
            id: score.id.uuidString,
            file: score.originalFileName,
            sha256: score.contentHash,
            pageCount: score.pageCount,
            text: includeText ? (score.extractedText ?? "") : nil,
            metadata: ExchangeMetadata(score.metadata)
        )
    }

    /// Writes one or more JSON files to a temporary folder and returns their URLs.
    static func writeFiles(
        for scores: [Score],
        includeText: Bool,
        batchSize: Int?,
        fileStem: String
    ) throws -> [URL] {
        let directory = LibraryPaths.shared.exportsDirectory
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: directory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let entries = scores.map { entry(for: $0, includeText: includeText) }
        let size = max(batchSize ?? entries.count, 1)
        let chunks = stride(from: 0, to: entries.count, by: size).map {
            Array(entries[$0..<min($0 + size, entries.count)])
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let date = formatter.string(from: Date())

        var urls: [URL] = []
        for (index, chunk) in chunks.enumerated() {
            let file = MetadataExchangeFile(
                scores: chunk,
                generator: "\(AppConfig.displayName) \(AppConfig.version)",
                instructionsForClaude: includeText ? ClaudeInstructions.labelling : nil
            )
            let name = chunks.count > 1
                ? "\(fileStem) \(date) part \(index + 1) of \(chunks.count).json"
                : "\(fileStem) \(date).json"
            let url = directory.appendingPathComponent(name)
            try MetadataExchangeCodec.encode(file).write(to: url, options: .atomic)
            urls.append(url)
        }
        return urls
    }
}
