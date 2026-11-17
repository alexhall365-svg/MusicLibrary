import Foundation
import CloudKit
import SwiftData

/// Writing changes received from iCloud into the library.
extension CloudSync {
    func applyFetched(_ changes: CKSyncEngine.Event.FetchedRecordZoneChanges, scope: CKDatabase.Scope) {
        guard let context = modelContainerContext else { return }

        // Files and scores first, so lists can link to them.
        func rank(_ record: CKRecord) -> Int {
            switch record.recordType {
            case SyncRecordName.scoreFileType: return 0
            case SyncRecordName.scoreType: return 1
            case SyncRecordName.setlistType: return 2
            default: return 3
            }
        }
        let records = changes.modifications.map(\.record).sorted { rank($0) < rank($1) }
        for record in records {
            let library = CloudLibrary.key(for: record.recordID.zoneID, scope: scope)
            if let share = record as? CKShare {
                if let library { updateChoir(library, from: share) }
                continue
            }
            switch SyncRecordName.parse(record.recordID.recordName) {
            case .scoreFile(let id): applyScoreFile(record, id: id, library: library, context: context)
            case .score(let id): applyScore(record, id: id, library: library, context: context)
            case .setlist(let id): applySetlist(record, id: id, library: library, context: context)
            case .annotation(let scoreID, let page): applyAnnotation(record, scoreID: scoreID, page: page, library: library)
            case nil: break
            }
        }

        for deletion in changes.deletions {
            let name = deletion.recordID.recordName
            let library = CloudLibrary.key(for: deletion.recordID.zoneID, scope: scope)
            // Ignore deletions of a copy that has since moved to another library.
            guard let entry = ledger.entries[name], entry.library == library else {
                if ledger.pendingScores[name]?.library == library {
                    ledger.pendingScores.removeValue(forKey: name)
                }
                continue
            }
            switch SyncRecordName.parse(name) {
            case .score:
                deferScoreDeletion(name: name, library: library)
            case .scoreFile:
                ledger.entries.removeValue(forKey: name)
            case .setlist(let id):
                ledger.entries.removeValue(forKey: name)
                ledger.pendingOrders.removeValue(forKey: name)
                if let setlist = Self.fetchSetlist(id, context: context), setlist.cloudLibrary == library {
                    context.delete(setlist)
                }
            case .annotation(let scoreID, let page):
                ledger.entries.removeValue(forKey: name)
                AnnotationStore().removeFile(scoreID: scoreID, page: page)
            case nil:
                break
            }
        }

        relinkPendingOrders(context: context)
        saveLedgerNow()
        try? context.save()
    }

    /// Applies score deletions once every zone has been fetched.
    func finishFetch() {
        guard let context = modelContainerContext else { return }
        let deletions = takeDeferredScoreDeletions()
        for deletion in deletions {
            guard case .score(let id) = SyncRecordName.parse(deletion.name) else { continue }
            // Still in the ledger for the same library: really deleted, not moved.
            guard let entry = ledger.entries[deletion.name], entry.library == deletion.library else { continue }
            ledger.entries.removeValue(forKey: deletion.name)
            ledger.entries.removeValue(forKey: SyncRecordName.scoreFile(id))
            if let score = Self.fetchScore(id, context: context), score.cloudLibrary == deletion.library {
                removeScoreLocally(score, context: context)
            }
        }
        relinkPendingOrders(context: context)
        saveLedgerNow()
        try? context.save()
    }

    // MARK: - Scores

    private func applyScoreFile(_ record: CKRecord, id: UUID, library: String?, context: ModelContext) {
        let name = record.recordID.recordName
        let hash = record["contentHash"] as? String ?? ""
        let existing = Self.fetchScore(id, context: context)
        let destination = existing?.fileURL
            ?? LibraryPaths.shared.scoreFileURL(storedFileName: "\(id.uuidString).pdf")
        let needsCopy = existing == nil
            || existing?.contentHash != hash
            || !FileManager.default.fileExists(atPath: destination.path)
        if needsCopy {
            guard let asset = record["file"] as? CKAsset, let source = asset.fileURL,
                  Self.copyReplacing(source, to: destination) else { return }
            ThumbnailCache.shared.remove(id)
        }
        ledger.entries[name] = SyncLedger.Entry(
            library: library, fingerprint: hash, systemFields: RecordArchive.systemFields(of: record))

        // Details that arrived before the file can now become a score.
        let scoreName = SyncRecordName.score(id)
        if existing == nil, let pending = ledger.pendingScores[scoreName], pending.library == library {
            ledger.pendingScores.removeValue(forKey: scoreName)
            insertScore(id: id, values: pending.values, library: library, context: context)
            if let fields = pending.systemFields, let score = Self.fetchScore(id, context: context) {
                ledger.entries[scoreName] = SyncLedger.Entry(
                    library: library, fingerprint: ScoreRecordValues(score: score).fingerprint, systemFields: fields)
            }
        }
    }

    private func applyScore(_ record: CKRecord, id: UUID, library: String?, context: ModelContext) {
        let name = record.recordID.recordName
        let values = ScoreRecordValues(record: record)
        var score = Self.fetchScore(id, context: context)

        if score == nil, library == nil, let match = unsyncedScore(contentHash: values.contentHash, context: context) {
            // The same PDF was imported on two devices before they first synced:
            // keep one score, with the ID already in iCloud.
            adopt(match, newID: id)
            score = match
        }

        if score == nil {
            let file = LibraryPaths.shared.scoreFileURL(storedFileName: "\(id.uuidString).pdf")
            guard FileManager.default.fileExists(atPath: file.path) else {
                // The PDF hasn't arrived yet: hold on to the details until it does.
                ledger.pendingScores[name] = SyncLedger.PendingScore(
                    library: library, values: values, systemFields: RecordArchive.systemFields(of: record))
                return
            }
            score = insertScore(id: id, values: values, library: library, context: context)
        }
        guard let score else { return }
        values.apply(to: score)
        if score.cloudLibrary != library { score.cloudLibrary = library }
        ledger.pendingScores.removeValue(forKey: name)
        ledger.entries[name] = SyncLedger.Entry(
            library: library,
            fingerprint: ScoreRecordValues(score: score).fingerprint,
            systemFields: RecordArchive.systemFields(of: record))
    }

    @discardableResult
    private func insertScore(id: UUID, values: ScoreRecordValues, library: String?, context: ModelContext) -> Score {
        let score = Score(
            id: id,
            storedFileName: "\(id.uuidString).pdf",
            originalFileName: values.originalFileName,
            contentHash: values.contentHash,
            pageCount: values.pageCount)
        context.insert(score)
        values.apply(to: score)
        score.cloudLibrary = library
        return score
    }

    /// A score in your own library that has never been synced, with this PDF.
    private func unsyncedScore(contentHash: String, context: ModelContext) -> Score? {
        guard !contentHash.isEmpty else { return nil }
        var descriptor = FetchDescriptor<Score>(predicate: #Predicate { $0.contentHash == contentHash })
        descriptor.fetchLimit = 5
        let matches = (try? context.fetch(descriptor)) ?? []
        return matches.first { $0.cloudLibrary == nil && ledger.entries[SyncRecordName.score($0.id)] == nil }
    }

    private func adopt(_ score: Score, newID: UUID) {
        let oldID = score.id
        guard oldID != newID else { return }
        let paths = LibraryPaths.shared
        let oldAnnotations = paths.annotationsDirectory(for: oldID)
        let newAnnotations = paths.annotationsDirectory(for: newID)
        if FileManager.default.fileExists(atPath: oldAnnotations.path) {
            try? FileManager.default.removeItem(at: newAnnotations)
            try? FileManager.default.moveItem(at: oldAnnotations, to: newAnnotations)
        }
        // A copy of the PDF may already have arrived under the new ID.
        let stray = paths.scoreFileURL(storedFileName: "\(newID.uuidString).pdf")
        if stray != score.fileURL { try? FileManager.default.removeItem(at: stray) }
        ThumbnailCache.shared.remove(oldID)
        score.id = newID
        // Never synced, so nothing about the old ID is in iCloud.
        ledger.entries.removeValue(forKey: SyncRecordName.scoreFile(oldID))
    }

    // MARK: - Setlists

    private func applySetlist(_ record: CKRecord, id: UUID, library: String?, context: ModelContext) {
        let name = record.recordID.recordName
        let values = SetlistRecordValues(record: record)
        let setlist: Setlist
        if let existing = Self.fetchSetlist(id, context: context) {
            setlist = existing
        } else {
            setlist = Setlist(name: values.name, cloudLibrary: library)
            setlist.id = id
            context.insert(setlist)
        }
        if setlist.name != values.name { setlist.name = values.name }
        if setlist.notes != values.notes { setlist.notes = values.notes }
        if setlist.createdAt.timeIntervalSince1970.rounded(.down) != values.createdAt {
            setlist.createdAt = Date(timeIntervalSince1970: values.createdAt)
        }
        if setlist.cloudLibrary != library { setlist.cloudLibrary = library }

        if link(setlist, to: values.scoreIDs, context: context) {
            ledger.pendingOrders.removeValue(forKey: name)
        } else {
            ledger.pendingOrders[name] = values.scoreIDs
        }
        ledger.entries[name] = SyncLedger.Entry(
            library: library,
            fingerprint: SetlistRecordValues(setlist: setlist).fingerprint,
            systemFields: RecordArchive.systemFields(of: record))
    }

    /// Rebuilds a setlist's entries in the given order. Returns false if some
    /// scores aren't on this device yet.
    @discardableResult
    func link(_ setlist: Setlist, to scoreIDs: [String], context: ModelContext) -> Bool {
        var scores: [Score] = []
        var complete = true
        var cache: [UUID: Score] = [:]
        for raw in scoreIDs {
            guard let id = UUID(uuidString: raw) else { continue }
            if let score = cache[id] ?? Self.fetchScore(id, context: context) {
                cache[id] = score
                scores.append(score)
            } else {
                complete = false
            }
        }
        let current = setlist.orderedEntries.compactMap { $0.score?.id }
        guard current != scores.map(\.id) else { return complete }
        for entry in setlist.entries ?? [] { context.delete(entry) }
        setlist.entries = []
        for (position, score) in scores.enumerated() {
            let entry = SetlistEntry(position: position)
            context.insert(entry)
            entry.score = score
            entry.setlist = setlist
        }
        return complete
    }

    private func relinkPendingOrders(context: ModelContext) {
        for (name, order) in ledger.pendingOrders {
            guard case .setlist(let id) = SyncRecordName.parse(name),
                  let setlist = Self.fetchSetlist(id, context: context) else {
                ledger.pendingOrders.removeValue(forKey: name)
                continue
            }
            let complete = link(setlist, to: order, context: context)
            if complete { ledger.pendingOrders.removeValue(forKey: name) }
            // What's linked now matches what iCloud has, as far as this device can show.
            ledger.entries[name]?.fingerprint = SetlistRecordValues(setlist: setlist).fingerprint
        }
    }

    // MARK: - Annotations

    private func applyAnnotation(_ record: CKRecord, scoreID: UUID, page: Int, library: String?) {
        guard library == nil, let asset = record["drawing"] as? CKAsset, let source = asset.fileURL else { return }
        let store = AnnotationStore()
        let destination = store.fileURL(scoreID: scoreID, page: page)
        try? FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard Self.copyReplacing(source, to: destination) else { return }
        ledger.entries[record.recordID.recordName] = SyncLedger.Entry(
            library: nil,
            fingerprint: SyncFingerprint.ofFile(at: destination) ?? "",
            systemFields: RecordArchive.systemFields(of: record))
        AnnotationStore.postRemoteChange(scoreID: scoreID, page: page)
    }

    // MARK: - Helpers

    static func copyReplacing(_ source: URL, to destination: URL) -> Bool {
        let fileManager = FileManager.default
        let temporary = destination.deletingLastPathComponent()
            .appendingPathComponent(".incoming-\(UUID().uuidString)")
        do {
            try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fileManager.copyItem(at: source, to: temporary)
            if fileManager.fileExists(atPath: destination.path) {
                _ = try fileManager.replaceItemAt(destination, withItemAt: temporary)
            } else {
                try fileManager.moveItem(at: temporary, to: destination)
            }
            return true
        } catch {
            try? fileManager.removeItem(at: temporary)
            print("Could not save a file from iCloud: \(error)")
            return false
        }
    }
}
