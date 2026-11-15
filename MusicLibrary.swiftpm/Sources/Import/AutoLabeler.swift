import Foundation
import Observation
import SwiftData

/// Labels scores with Apple Intelligence, one at a time, in the background.
///
/// - `.apply` (used after import): writes the details straight to the score and
///   marks uncertain results so they appear under Needs Details.
/// - `.review` (used to relabel existing scores): collects suggestions and opens
///   the review screen at the end, so nothing changes without your OK.
@MainActor
@Observable
final class AutoLabeler {
    enum Mode { case apply, review }

    private(set) var isRunning = false
    private(set) var mode: Mode = .apply
    private(set) var done = 0
    private(set) var total = 0
    /// A message shown when a run finishes, until dismissed.
    var summary: String?

    @ObservationIgnored private var queue: [UUID] = []
    @ObservationIgnored private var cancelRequested = false
    @ObservationIgnored private var task: Task<Void, Never>?

    nonisolated init() {}

    /// Starts labelling, or adds to the current `.apply` run.
    func start(_ scoreIDs: [UUID], mode: Mode, context: ModelContext, appState: AppState) {
        guard !scoreIDs.isEmpty else { return }
        if isRunning {
            if self.mode == .apply && mode == .apply {
                queue += scoreIDs
                total += scoreIDs.count
            }
            return
        }
        self.mode = mode
        queue = scoreIDs
        done = 0
        total = scoreIDs.count
        summary = nil
        cancelRequested = false
        isRunning = true
        task = Task { await run(context: context, appState: appState) }
    }

    /// Waits for the current run to finish.
    func wait() async {
        await task?.value
    }

    func stop() {
        cancelRequested = true
    }

    private func run(context: ModelContext, appState: AppState) async {
        defer {
            isRunning = false
            task = nil
        }
        guard let suggester = AppleIntelligence.makeSuggester() else {
            summary = AppleIntelligence.status.message
            queue = []
            return
        }

        var entries: [ExchangeEntry] = []
        var labelled = 0
        var uncertain = 0
        var failed = 0

        while !queue.isEmpty && !cancelRequested {
            let id = queue.removeFirst()
            defer { done += 1 }
            guard let score = fetchScore(id, context: context) else { continue }

            if score.extractedText == nil {
                let text = await TextExtractor.extractText(from: score.fileURL)
                guard !score.isDeleted else { continue }
                score.extractedText = text
            }
            let input = SuggestionInput(fileName: score.originalFileName, extractedText: score.extractedText)
            guard let suggestion = await suggester.suggest(for: input) else {
                failed += 1
                continue
            }
            guard !score.isDeleted else { continue }

            let isUncertain = AutoLabelLogic.isUncertain(suggestion)
            switch mode {
            case .apply:
                score.metadata = AutoLabelLogic.merged(suggestion.metadata, into: score.metadata)
                score.labelStatus = isUncertain ? .autoUncertain : .auto
            case .review:
                entries.append(AutoLabelLogic.exchangeEntry(
                    id: score.id, fileName: score.originalFileName, sha256: score.contentHash,
                    base: score.metadata, suggestion: suggestion))
            }
            labelled += 1
            if isUncertain { uncertain += 1 }
            if labelled % 10 == 0 { try? context.save() }
        }
        try? context.save()

        let stopped = cancelRequested && !queue.isEmpty
        queue = []

        switch mode {
        case .apply:
            var lines = ["Apple Intelligence filled in \(labelled) score\(labelled == 1 ? "" : "s")."]
            if uncertain > 0 { lines.append("\(uncertain) to check under Needs Details.") }
            if failed > 0 { lines.append("\(failed) couldn't be read.") }
            if stopped { lines.append("Stopped early.") }
            summary = lines.joined(separator: " ")
        case .review:
            if entries.isEmpty {
                summary = failed > 0
                    ? "Apple Intelligence couldn't read \(failed) score\(failed == 1 ? "" : "s")."
                    : "Nothing to label."
            } else {
                summary = nil
                ImportCoordinator(context: context, appState: appState).presentReview(
                    of: MetadataExchangeFile(scores: entries, exportedAt: nil),
                    title: "Apple Intelligence",
                    emptyMessage: failed > 0 ? "\(failed) couldn't be read." : nil)
            }
        }
    }

    private func fetchScore(_ id: UUID, context: ModelContext) -> Score? {
        var descriptor = FetchDescriptor<Score>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}
