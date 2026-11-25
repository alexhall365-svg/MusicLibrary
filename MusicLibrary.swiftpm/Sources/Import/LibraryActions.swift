import Foundation
import SwiftData

/// Library changes that touch both the database and files.
@MainActor
enum LibraryActions {
    static func delete(_ scores: [Score], context: ModelContext) {
        let items = scores.map { ($0.id, $0.fileURL) }
        scores.forEach { context.delete($0) }
        try? context.save()
        let store = AnnotationStore()
        for (id, file) in items {
            try? FileManager.default.removeItem(at: file)
            store.deleteAll(for: id)
            ThumbnailCache.shared.remove(id)
        }
    }

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

    /// Adds scores to a setlist. A group list can only hold that group's music
    /// (members need the PDFs), so your own scores added to one are copied into
    /// the group; your own library keeps them.
    static func add(_ scores: [Score], to setlist: Setlist, context: ModelContext) {
        var scores = scores
        if let library = setlist.cloudLibrary {
            scores = scores.compactMap { score in
                if score.cloudLibrary == library { return score }
                return score.isPersonal ? groupCopy(of: score, in: library, context: context) : nil
            }
        }
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

    /// Copies your own scores into a group, so every member gets them. Your own
    /// library keeps its copy, with your markings still private to you.
    static func copyToChoir(_ scores: [Score], library: String, context: ModelContext) {
        for score in scores where score.isPersonal {
            _ = groupCopy(of: score, in: library, context: context)
        }
        try? context.save()
    }

    /// The group's copy of a score: the one already there (same PDF), or a new
    /// copy with the same details. Your markings are copied too, and in the group
    /// they show to everyone as the director's markings.
    static func groupCopy(of score: Score, in library: String, context: ModelContext) -> Score? {
        let hash = score.contentHash
        var descriptor = FetchDescriptor<Score>(predicate: #Predicate { $0.contentHash == hash })
        descriptor.fetchLimit = 20
        if !hash.isEmpty, let existing = ((try? context.fetch(descriptor)) ?? []).first(where: { $0.cloudLibrary == library }) {
            return existing
        }
        let fileManager = FileManager.default
        let id = UUID()
        let storedName = "\(id.uuidString).pdf"
        let paths = LibraryPaths.shared
        do {
            try fileManager.copyItem(at: score.fileURL, to: paths.scoreFileURL(storedFileName: storedName))
        } catch {
            return nil
        }
        let copy = Score(
            id: id, storedFileName: storedName, originalFileName: score.originalFileName,
            contentHash: score.contentHash, pageCount: score.pageCount, metadata: score.metadata)
        copy.extractedText = score.extractedText
        copy.labelStatusRaw = score.labelStatusRaw
        copy.pageFingerprint = score.pageFingerprint
        copy.cloudLibrary = library
        context.insert(copy)

        // Your own markings (not markings received from another group's director).
        let source = paths.annotationsDirectory(for: score.id)
        let files = (try? fileManager.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)) ?? []
        let drawings = files.filter { $0.pathExtension == "drawing" }
        if !drawings.isEmpty {
            let destination = paths.annotationsDirectory(for: id)
            try? fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
            for file in drawings {
                try? fileManager.copyItem(at: file, to: destination.appendingPathComponent(file.lastPathComponent))
            }
            NotificationCenter.default.post(name: AnnotationStore.didChange, object: nil)
        }
        return copy
    }

    /// Takes a score out of a Choir Library: it's removed from members' devices.
    /// With `keepCopy` (the choir's owner only) it stays in your own library.
    static func removeFromChoir(_ score: Score, keepCopy: Bool, context: ModelContext) {
        guard let library = score.cloudLibrary else { return }
        for entry in score.setlistEntries ?? [] where entry.setlist?.cloudLibrary == library {
            entry.setlist?.entries?.removeAll { $0.id == entry.id }
            context.delete(entry)
        }
        let hash = score.contentHash
        var descriptor = FetchDescriptor<Score>(predicate: #Predicate { $0.contentHash == hash })
        descriptor.fetchLimit = 20
        let alreadyKept = !hash.isEmpty
            && ((try? context.fetch(descriptor)) ?? []).contains { $0.isPersonal && $0.id != score.id }
        if keepCopy && !alreadyKept {
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
