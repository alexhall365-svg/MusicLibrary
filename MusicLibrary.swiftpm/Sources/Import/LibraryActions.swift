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
    static func createSetlist(named name: String, in library: String? = nil, context: ModelContext) -> Setlist {
        let clean = name.trimmed
        let fallback = library == nil ? "New Setlist" : "New List"
        let setlist = Setlist(name: clean.isEmpty ? fallback : clean, cloudLibrary: library)
        context.insert(setlist)
        try? context.save()
        return setlist
    }

    /// Adds scores to a setlist. A choir list can only hold choir music (members
    /// need the PDFs), so your own scores added to one move into that Choir Library.
    static func add(_ scores: [Score], to setlist: Setlist, context: ModelContext) {
        if let library = setlist.cloudLibrary {
            for score in scores where score.cloudLibrary != library {
                guard score.isPersonal else { continue }
                score.cloudLibrary = library
            }
        }
        let scores = scores.filter { setlist.cloudLibrary == nil || $0.cloudLibrary == setlist.cloudLibrary }
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

    /// Moves your own scores into a Choir Library, so every member gets them.
    static func moveToChoir(_ scores: [Score], library: String, context: ModelContext) {
        for score in scores where score.isPersonal {
            score.cloudLibrary = library
        }
        try? context.save()
    }

    /// Takes a score out of a Choir Library: it's removed from members' devices.
    /// With `keepCopy` (the choir's owner only) it stays in your own library.
    static func removeFromChoir(_ score: Score, keepCopy: Bool, context: ModelContext) {
        guard let library = score.cloudLibrary else { return }
        for entry in score.setlistEntries ?? [] where entry.setlist?.cloudLibrary == library {
            entry.setlist?.entries?.removeAll { $0.id == entry.id }
            context.delete(entry)
        }
        if keepCopy {
            score.cloudLibrary = nil
            try? context.save()
        } else {
            delete(score, context: context)
        }
    }

    /// Copies a list (for example a choir list) into a new setlist of your own,
    /// which you can then reorder and change.
    @discardableResult
    static func copyToMySetlists(_ setlist: Setlist, context: ModelContext) -> Setlist {
        let copy = Setlist(name: setlist.name)
        copy.notes = setlist.notes
        context.insert(copy)
        try? context.save()
        add(setlist.orderedScores, to: copy, context: context)
        return copy
    }

    static func renumber(_ entries: [SetlistEntry]) {
        for (index, entry) in entries.enumerated() where entry.position != index {
            entry.position = index
        }
    }
}
