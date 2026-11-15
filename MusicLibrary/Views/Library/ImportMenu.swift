import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// The Import button: PDFs, or a whole folder (optionally with a metadata.json package).
struct ImportMenu: View {
    private enum Kind { case pdfs, folder }

    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @State private var kind: Kind?

    var body: some View {
        Menu {
            Button("Import PDFs…", systemImage: "doc.badge.plus") { kind = .pdfs }
            Button("Import a Folder or Package…", systemImage: "folder.badge.plus") { kind = .folder }
        } label: {
            Label("Import", systemImage: "plus")
        }
        .fileImporter(
            isPresented: Binding(get: { kind != nil }, set: { if !$0 { kind = nil } }),
            allowedContentTypes: kind == .folder ? [.folder] : [.pdf],
            allowsMultipleSelection: kind != .folder
        ) { result in
            switch result {
            case .success(let urls):
                Task { await ImportCoordinator(context: modelContext, appState: appState).importItems(urls) }
            case .failure(let error):
                appState.alert = AppAlert(title: "Couldn't Import", message: error.localizedDescription)
            }
        }
    }
}

/// Handles PDFs dragged in from other apps (e.g. Files in Split View).
enum DropImporter {
    static func importPDFs(from providers: [NSItemProvider], coordinator: ImportCoordinator) {
        Task { @MainActor in
            var urls: [URL] = []
            for provider in providers {
                if let url = await copy(provider) { urls.append(url) }
            }
            await coordinator.importItems(urls)
            for url in urls {
                try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
            }
        }
    }

    private static func copy(_ provider: NSItemProvider) async -> URL? {
        let suggestedName = provider.suggestedName
        return await withCheckedContinuation { continuation in
            _ = provider.loadFileRepresentation(forTypeIdentifier: UTType.pdf.identifier) { url, _ in
                guard let url else {
                    continuation.resume(returning: nil)
                    return
                }
                let folder = FileManager.default.temporaryDirectory
                    .appendingPathComponent("Drop-\(UUID().uuidString)", isDirectory: true)
                var name = suggestedName ?? url.deletingPathExtension().lastPathComponent
                if !name.lowercased().hasSuffix(".pdf") { name += ".pdf" }
                let target = folder.appendingPathComponent(name)
                do {
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    try FileManager.default.copyItem(at: url, to: target)
                    continuation.resume(returning: target)
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
