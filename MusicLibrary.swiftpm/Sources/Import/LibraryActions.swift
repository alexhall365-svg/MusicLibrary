import Foundation
import SwiftData

/// Library changes that touch both the database and files.
@MainActor
enum LibraryActions {
    static func delete(_ score: Score, context: ModelContext) {
        let id = score.id
        let file = score.fileURL
        context.delete(score)
        try? context.save()
        try? FileManager.default.removeItem(at: file)
        AnnotationStore().deleteAll(for: id)
        ThumbnailCache.shared.remove(id)
    }

    /// Deletes `duplicate`, first moving its setlist entries to `keeper`.
    static func deleteDuplicate(_ duplicate: Score, keeping keeper: Score?, context: ModelContext) {
        if let keeper, keeper.id != duplicate.id {
            for entry in duplicate.setlistEntries ?? [] {
                entry.score = keeper
            }
            duplicate.setlistEntries = []
        }
        delete(duplicate, context: context)
    }

    @discardableResult
    static func createSetlist(named name: String, context: ModelContext) -> Setlist {
        let clean = name.trimmed
        let setlist = Setlist(name: clean.isEmpty ? "New Setlist" : clean)
        context.insert(setlist)
        try? context.save()
        return setlist
    }

    static func add(_ scores: [Score], to setlist: Setlist, context: ModelContext) {
        var next = ((setlist.entries ?? []).map(\.position).max() ?? -1) + 1
        for score in scores {
            let entry = SetlistEntry(position: next)
            context.insert(entry)
            entry.score = score
            entry.setlist = setlist
            next += 1
        }
        try? context.save()
    }

    static func renumber(_ entries: [SetlistEntry]) {
        for (index, entry) in entries.enumerated() where entry.position != index {
            entry.position = index
        }
    }
}
