import Foundation
import Observation

/// Page-turning state for the reader: a single score or a whole setlist.
@MainActor
@Observable
final class ReaderSession {
    let scores: [Score]
    private(set) var scoreIndex: Int
    private(set) var renderer: PageRenderer
    private(set) var pageIndex = 0
    private(set) var isLandscape = false
    private(set) var twoUpEnabled: Bool

    var isAnnotating = false
    var isPerformanceMode = false
    var chromeVisible = true

    private static let twoUpKey = "reader.twoUpInLandscape"

    init(scores: [Score], startIndex: Int) {
        precondition(!scores.isEmpty, "The reader needs at least one score")
        self.scores = scores
        let index = min(max(startIndex, 0), scores.count - 1)
        self.scoreIndex = index
        let score = scores[index]
        self.renderer = PageRenderer(scoreID: score.id, url: score.fileURL)
        self.twoUpEnabled = UserDefaults.standard.object(forKey: Self.twoUpKey) as? Bool ?? true
        // A setlist always starts each piece at the top; a single score resumes.
        self.pageIndex = scores.count > 1 ? 0 : min(score.lastPageIndex, max(renderer.pageCount - 1, 0))
        score.lastOpened = Date()
        normalize()
    }

    // MARK: Derived state

    var currentScore: Score { scores[scoreIndex] }
    var pageCount: Int { renderer.pageCount }
    var isSetlist: Bool { scores.count > 1 }
    var hasNextScore: Bool { scoreIndex < scores.count - 1 }
    var hasPreviousScore: Bool { scoreIndex > 0 }
    var pagesPerSpread: Int { twoUpEnabled && isLandscape ? 2 : 1 }

    var visiblePages: [Int] {
        guard pageCount > 0 else { return [] }
        return Array(pageIndex..<min(pageIndex + pagesPerSpread, pageCount))
    }

    var canGoForward: Bool { pageIndex + pagesPerSpread < pageCount || hasNextScore }
    var canGoBack: Bool { pageIndex > 0 || hasPreviousScore }

    var pageLabel: String {
        guard let first = visiblePages.first, let last = visiblePages.last else { return "" }
        let range = first == last ? "\(first + 1)" : "\(first + 1)–\(last + 1)"
        return "\(range) of \(pageCount)"
    }

    // MARK: Actions

    func setLandscape(_ landscape: Bool) {
        guard landscape != isLandscape else { return }
        isLandscape = landscape
        normalize()
    }

    func toggleTwoUp() {
        twoUpEnabled.toggle()
        UserDefaults.standard.set(twoUpEnabled, forKey: Self.twoUpKey)
        normalize()
    }

    func nextPage() {
        let next = pageIndex + pagesPerSpread
        if next < pageCount {
            pageIndex = next
            saveProgress()
        } else if hasNextScore {
            moveToScore(scoreIndex + 1, atEnd: false)
        }
    }

    func previousPage() {
        if pageIndex > 0 {
            pageIndex = max(0, pageIndex - pagesPerSpread)
            normalize()
            saveProgress()
        } else if hasPreviousScore {
            moveToScore(scoreIndex - 1, atEnd: true)
        }
    }

    func goToPage(_ index: Int) {
        pageIndex = min(max(index, 0), max(pageCount - 1, 0))
        normalize()
        saveProgress()
    }

    func nextScore() {
        if hasNextScore { moveToScore(scoreIndex + 1, atEnd: false) }
    }

    func previousScore() {
        if hasPreviousScore { moveToScore(scoreIndex - 1, atEnd: false) }
    }

    func saveProgress() {
        currentScore.lastPageIndex = pageIndex
    }

    private func moveToScore(_ index: Int, atEnd: Bool) {
        saveProgress()
        scoreIndex = index
        let score = currentScore
        renderer = PageRenderer(scoreID: score.id, url: score.fileURL)
        score.lastOpened = Date()
        pageIndex = atEnd ? max(pageCount - 1, 0) : 0
        normalize()
    }

    /// In two-up mode spreads start on even pages (1–2, 3–4, …).
    private func normalize() {
        pageIndex = min(max(pageIndex, 0), max(pageCount - 1, 0))
        if pagesPerSpread == 2 {
            pageIndex -= pageIndex % 2
        }
    }
}
