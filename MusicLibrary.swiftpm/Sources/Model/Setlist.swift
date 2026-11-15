import Foundation
import SwiftData

@Model
final class Setlist {
    var id: UUID = UUID()
    var name: String = ""
    var notes: String = ""
    var createdAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \SetlistEntry.setlist)
    var entries: [SetlistEntry]? = []

    init(name: String) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
    }

    var orderedEntries: [SetlistEntry] {
        (entries ?? []).sorted { $0.position < $1.position }
    }

    var orderedScores: [Score] {
        orderedEntries.compactMap(\.score)
    }
}

/// One slot in a setlist. The same score can appear more than once.
@Model
final class SetlistEntry {
    var id: UUID = UUID()
    var position: Int = 0
    var score: Score?
    var setlist: Setlist?

    init(position: Int) {
        self.id = UUID()
        self.position = position
    }
}
