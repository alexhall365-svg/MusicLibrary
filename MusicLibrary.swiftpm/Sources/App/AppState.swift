import Foundation
import Observation

/// App-wide presentation state shared through the SwiftUI environment.
@MainActor
@Observable
final class AppState {
    /// Background labelling with Apple Intelligence.
    let autoLabeler = AutoLabeler()
    /// The one-time Pro unlock.
    let pro = ProStore()

    /// When set, the reader is shown full screen.
    var readerRequest: ReaderRequest?
    /// When set, the metadata review sheet is shown.
    var review: MetadataReview?
    /// When set, the details editor is shown for this score.
    var editingScore: Score?
    /// A simple message alert.
    var alert: AppAlert?
    /// Imports in progress, shown in a small banner while the app stays usable.
    var importStatus: String?
    /// How many imports are running (several can overlap).
    var importsRunning = 0
    /// A short message shown when an import finishes, until dismissed.
    var importSummary: String?
}

struct AppAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

struct ReaderRequest: Identifiable {
    let id = UUID()
    /// One score, or every score in a setlist (played in order).
    let scores: [Score]
    let startIndex: Int
}
