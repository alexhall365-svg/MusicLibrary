import Foundation
import PDFKit
import SwiftData

struct ImportFailure: Identifiable {
    let id = UUID()
    let fileName: String
    let reason: String
}

struct ImportReport {
    var imported: [Score] = []
    var duplicates: [String] = []
    var failures: [ImportFailure] = []
    /// A metadata.json found alongside the PDFs (an import package).
    var metadataFile: MetadataExchangeFile?
    var metadataError: String?

    var summary: String {
        var lines = ["Imported \(imported.count) score\(imported.count == 1 ? "" : "s")."]
        if !duplicates.isEmpty {
            lines.append("Skipped \(duplicates.count) already in your library.")
        }
        if !failures.isEmpty {
            lines.append("Couldn't import \(failures.count):")
            lines += failures.prefix(8).map { "• \($0.fileName): \($0.reason)" }
            if failures.count > 8 { lines.append("…and \(failures.count - 8) more.") }
        }
        if let metadataError {
            lines.append("The metadata file couldn't be read: \(metadataError)")
        }
        return lines.joined(separator: "\n")
    }
}

enum ImportError: LocalizedError {
    case unreadablePDF
    case passwordProtected

    var errorDescription: String? {
        switch self {
        case .unreadablePDF: return "not a readable PDF"
        case .passwordProtected: return "the PDF is password-protected"
        }
    }
}

/// Copies PDFs into the library, skipping duplicates by content hash.
@MainActor
final class ImportService {
    private let context: ModelContext
    private let paths: LibraryPaths
    private let suggester: any MetadataSuggester

    init(
        context: ModelContext,
        paths: LibraryPaths = .shared,
        suggester: any MetadataSuggester = FilenameMetadataSuggester()
    ) {
        self.context = context
        self.paths = paths
        self.suggester = suggester
    }

    /// Imports PDFs and folders (searched recursively). A folder may also contain
    /// a `metadata.json` import package, which is returned in the report.
    func importItems(_ urls: [URL], progress: ((Int, Int) -> Void)? = nil) async -> ImportReport {
        var report = ImportReport()
        try? paths.ensureDirectories()

        let accessed = urls.filter { $0.startAccessingSecurityScopedResource() }
        defer { accessed.forEach { $0.stopAccessingSecurityScopedResource() } }

        let (pdfs, metadataURL) = Self.collectFiles(from: urls)
        if let metadataURL {
            do {
                report.metadataFile = try MetadataExchangeCodec.decode(Data(contentsOf: metadataURL))
            } catch {
                report.metadataError = error.localizedDescription
            }
        }

        var knownHashes = existingHashes()
        for (index, url) in pdfs.enumerated() {
            progress?(index + 1, pdfs.count)
            let fileName = url.lastPathComponent
            do {
                let hash = try await Self.hash(url)
                if knownHashes.contains(hash) {
                    report.duplicates.append(fileName)
                    continue
                }
                let id = UUID()
                let storedName = "\(id.uuidString).pdf"
                let info = try await Self.copyAndInspect(
                    from: url, to: paths.scoreFileURL(storedFileName: storedName))
                let suggestion = await suggester.suggest(
                    for: SuggestionInput(fileName: fileName, pdfTitle: info.title, pdfAuthor: info.author))
                let score = Score(
                    id: id,
                    storedFileName: storedName,
                    originalFileName: fileName,
                    contentHash: hash,
                    pageCount: info.pageCount,
                    metadata: suggestion?.metadata ?? ScoreMetadata()
                )
                context.insert(score)
                knownHashes.insert(hash)
                report.imported.append(score)
            } catch {
                report.failures.append(ImportFailure(fileName: fileName, reason: error.localizedDescription))
            }
        }
        try? context.save()
        return report
    }

    private func existingHashes() -> Set<String> {
        let scores = (try? context.fetch(FetchDescriptor<Score>())) ?? []
        return Set(scores.map(\.contentHash))
    }

    // MARK: - Background work

    struct PDFInfo: Sendable {
        let pageCount: Int
        let title: String?
        let author: String?
    }

    nonisolated static func collectFiles(from urls: [URL]) -> (pdfs: [URL], metadata: URL?) {
        let fileManager = FileManager.default
        var pdfs: [URL] = []
        var metadata: URL?
        for url in urls {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }
            if isDirectory.boolValue {
                let contents = fileManager.enumerator(
                    at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
                while let child = contents?.nextObject() as? URL {
                    let ext = child.pathExtension.lowercased()
                    if ext == "pdf" {
                        pdfs.append(child)
                    } else if child.lastPathComponent.lowercased() == "metadata.json" {
                        metadata = child
                    }
                }
            } else if url.pathExtension.lowercased() == "pdf" {
                pdfs.append(url)
            }
        }
        pdfs.sort { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        return (pdfs, metadata)
    }

    nonisolated static func hash(_ url: URL) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            try FileHasher.sha256(of: url)
        }.value
    }

    nonisolated static func copyAndInspect(from source: URL, to destination: URL) async throws -> PDFInfo {
        try await Task.detached(priority: .userInitiated) {
            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.copyItem(at: source, to: destination)
            guard let document = PDFDocument(url: destination) else {
                try? fileManager.removeItem(at: destination)
                throw ImportError.unreadablePDF
            }
            if document.isLocked {
                try? fileManager.removeItem(at: destination)
                throw ImportError.passwordProtected
            }
            let attributes = document.documentAttributes
            return PDFInfo(
                pageCount: document.pageCount,
                title: attributes?[PDFDocumentAttribute.titleAttribute] as? String,
                author: attributes?[PDFDocumentAttribute.authorAttribute] as? String
            )
        }.value
    }
}
