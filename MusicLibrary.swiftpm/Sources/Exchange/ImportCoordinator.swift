import Foundation
import SwiftData

/// Connects import actions in the UI to the services, and reports results
/// through `AppState`.
struct ImportCoordinator {
    let context: ModelContext
    let appState: AppState

    @MainActor
    func importItems(_ urls: [URL]) async {
        guard !urls.isEmpty else { return }
        appState.busyMessage = "Importing…"
        let service = ImportService(context: context)
        let report = await service.importItems(urls) { done, total in
            appState.busyMessage = "Importing \(done) of \(total)…"
        }
        appState.busyMessage = nil

        let newIDs = report.imported.map(\.id)
        let useAppleIntelligence = report.metadataFile == nil && !newIDs.isEmpty
            && appState.pro.isPro
            && AppleIntelligence.autoLabelOnImport && AppleIntelligence.status.isAvailable
        let isSingleClean = report.imported.count == 1 && report.duplicates.isEmpty && report.failures.isEmpty

        if let file = report.metadataFile {
            presentReview(of: file, title: "Package Details", emptyMessage: report.summary)
        } else if isSingleClean {
            // One new score: fill it in, then show its details to check.
            if useAppleIntelligence && !appState.autoLabeler.isRunning {
                appState.busyMessage = "Reading the score with Apple Intelligence…"
                appState.autoLabeler.start(newIDs, mode: .apply, context: context, appState: appState)
                await appState.autoLabeler.wait()
                appState.autoLabeler.summary = nil
                appState.busyMessage = nil
            } else if useAppleIntelligence {
                appState.autoLabeler.start(newIDs, mode: .apply, context: context, appState: appState)
            }
            appState.editingScore = report.imported[0]
        } else {
            var message = report.summary
            if useAppleIntelligence {
                appState.autoLabeler.start(newIDs, mode: .apply, context: context, appState: appState)
                message += "\n\nApple Intelligence is filling in the details in the background. You can keep using the app."
            }
            appState.alert = AppAlert(title: "Import Finished", message: message)
        }
    }

    @MainActor
    func importMetadata(_ data: Data, title: String) {
        do {
            let file = try MetadataExchangeCodec.decode(data)
            presentReview(of: file, title: title, emptyMessage: nil)
        } catch {
            appState.alert = AppAlert(title: "Couldn't Read Details", message: error.localizedDescription)
        }
    }

    @MainActor
    func importMetadataFile(at url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            importMetadata(try Data(contentsOf: url), title: "Review Details")
        } catch {
            appState.alert = AppAlert(title: "Couldn't Open File", message: error.localizedDescription)
        }
    }

    /// Files opened from other apps ("Open in…", share sheet, Files).
    @MainActor
    func handleOpenedURL(_ url: URL) async {
        if url.pathExtension.lowercased() == "json" {
            importMetadataFile(at: url)
        } else {
            await importItems([url])
        }
        if url.path.contains("/Inbox/") {
            try? FileManager.default.removeItem(at: url)
        }
    }

    @MainActor
    func presentReview(of file: MetadataExchangeFile, title: String, emptyMessage: String?) {
        let scores = (try? context.fetch(FetchDescriptor<Score>())) ?? []
        let subjects = scores.map {
            ReviewSubject(
                candidate: MatchCandidate(id: $0.id, sha256: $0.contentHash, fileName: $0.originalFileName),
                metadata: $0.metadata)
        }
        let review = MetadataReviewBuilder.build(file: file, subjects: subjects, title: title)
        if review.items.isEmpty {
            var lines: [String] = []
            if let emptyMessage { lines.append(emptyMessage) }
            lines.append("No changes to review. \(review.unchangedCount) matched with nothing new, \(review.unmatchedFiles.count) not found in your library.")
            appState.alert = AppAlert(title: "Nothing to Update", message: lines.joined(separator: "\n\n"))
        } else {
            appState.review = review
        }
    }
}
