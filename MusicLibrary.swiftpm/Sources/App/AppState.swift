import Foundation
import Observation

/// App-wide presentation state shared through the SwiftUI environment.
@MainActor
@Observable
final class AppState {
    /// Background labelling with Apple Intelligence.
    let autoLabeler = AutoLabeler()

    /// When set, the reader is shown full screen.
    var readerRequest: ReaderRequest?
    /// When set, the metadata review sheet is shown.
    var review: MetadataReview?
    /// When set, the details editor is shown for this score.
    var editingScore: Score?
    /// A simple message alert.
    var alert: AppAlert?
    /// When set, a blocking progress overlay is shown with this text.
    var busyMessage: String?
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
