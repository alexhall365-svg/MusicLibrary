import Foundation
import SwiftData

/// One-off updates to existing libraries when the app's standards change.
@MainActor
enum LibraryMaintenance {
    private static let versionKey = "maintenance.version"
    /// 1: standard composer names, voicing, genres; IMSLP numbers removed.
    private static let currentVersion = 1

    static func runIfNeeded(context: ModelContext) {
        let defaults = UserDefaults.standard
        guard defaults.integer(forKey: versionKey) < currentVersion else { return }
        let scores = (try? context.fetch(FetchDescriptor<Score>())) ?? []
        for score in scores {
            let current = score.metadata
            let tidied = current.normalized()
            if tidied != current { score.metadata = tidied }
        }
        try? context.save()
        defaults.set(currentVersion, forKey: versionKey)
    }
}
