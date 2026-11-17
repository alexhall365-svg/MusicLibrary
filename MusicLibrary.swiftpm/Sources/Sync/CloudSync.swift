import Foundation
import CloudKit
import SwiftData
import Observation
import UIKit

/// A Choir Library this person hosts or has joined.
struct ChoirInfo: Codable, Identifiable, Equatable {
    /// The library key (see `CloudLibrary`).
    var id: String
    var name: String
    var isOwner: Bool
    /// Owners and editors can add, remove, reorder and edit. Members only read.
    var canEdit: Bool
    var ownerName: String?
    var memberCount: Int = 0
}

/// Local-first iCloud sync with CloudKit's `CKSyncEngine`.
///
/// The library on the device is always the source of truth and works offline.
/// Sync compares it with what was last exchanged (`SyncLedger`) and sends the
/// difference; changes from iCloud are written into the library and the ledger.
///
/// Two engines run: one for the private database (your own library and any
/// Choir Library you host) and one for the shared database (choirs you joined).
@MainActor
@Observable
final class CloudSync {
    static let shared = CloudSync()

    /// True when this build can use iCloud (TestFlight/App Store builds).
    let isSupported: Bool
    let containerIdentifier: String?

    /// "Sync with iCloud" in Settings. On by default.
    var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            UserDefaults.standard.set(isEnabled, forKey: Keys.enabled)
            if isEnabled { start() } else { stop() }
        }
    }

    private(set) var accountStatus: CKAccountStatus = .couldNotDetermine
    private(set) var isFetching = false
    private(set) var isSending = false
    private(set) var pendingChanges = 0
    private(set) var lastSync: Date?
    /// A problem worth showing (iCloud full, signed out…).
    var problem: String?
    private(set) var choirs: [ChoirInfo] = []

    var hostedChoir: ChoirInfo? { choirs.first { $0.isOwner } }
    var joinedChoirs: [ChoirInfo] { choirs.filter { !$0.isOwner } }

    @ObservationIgnored private var container: CKContainer?
    @ObservationIgnored private var modelContainer: ModelContainer?
    @ObservationIgnored private var privateEngine: CKSyncEngine?
    @ObservationIgnored private var sharedEngine: CKSyncEngine?
    @ObservationIgnored var ledger = SyncLedger()
    @ObservationIgnored private var inFlight: [String: String] = [:]
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    /// Score deletions are applied when a fetch ends, so a score moved between
    /// libraries (deleted from one, added to another) is never lost.
    @ObservationIgnored private var deferredScoreDeletions: [(name: String, library: String?)] = []

    var modelContainerContext: ModelContext? { modelContainer?.mainContext }

    func deferScoreDeletion(name: String, library: String?) {
        deferredScoreDeletions.append((name, library))
    }

    func takeDeferredScoreDeletions() -> [(name: String, library: String?)] {
        defer { deferredScoreDeletions = [] }
        return deferredScoreDeletions
    }

    func saveLedgerNow() {
        files.save(ledger, to: FileNames.ledger)
    }
    @ObservationIgnored private let files = SyncFileStore.shared

    private enum Keys {
        static let enabled = "sync.enabled"
        static let lastSync = "sync.lastSync"
        static let fetchedOnce = "sync.fetchedOnce."
    }

    private enum FileNames {
        static let ledger = "ledger.json"
        static let choirs = "choirs.json"
        static func engine(_ scope: CKDatabase.Scope) -> String { "engine-\(scope == .shared ? "shared" : "private").json" }
    }

    private init() {
        let info = Bundle.main.infoDictionary ?? [:]
        let flag = (info["QuireCloudSync"] as? String)?.uppercased() == "YES" || (info["QuireCloudSync"] as? Bool) == true
        let identifier = (info["QuireCloudKitContainer"] as? String)?.trimmingCharacters(in: .whitespaces)
        if flag, let identifier, identifier.hasPrefix("iCloud.") {
            isSupported = true
            containerIdentifier = identifier
        } else {
            isSupported = false
            containerIdentifier = nil
        }
        isEnabled = UserDefaults.standard.object(forKey: Keys.enabled) as? Bool ?? true
        lastSync = UserDefaults.standard.object(forKey: Keys.lastSync) as? Date
    }

    // MARK: - Starting and stopping

    func configure(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        ledger = files.load(SyncLedger.self, from: FileNames.ledger) ?? SyncLedger()
        choirs = files.load([ChoirInfo].self, from: FileNames.choirs) ?? []
        guard isSupported, let containerIdentifier else { return }
        container = CKContainer(identifier: containerIdentifier)
        observeChanges()
        if isEnabled { start() }
    }

    private func start() {
        guard isSupported, let container, privateEngine == nil else { return }
        privateEngine = makeEngine(database: container.privateCloudDatabase)
        sharedEngine = makeEngine(database: container.sharedCloudDatabase)
        privateEngine?.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneName: CloudLibrary.personalZoneName))])
        Task {
            await refreshAccountStatus()
            await refreshChoirDetails()
        }
        scheduleScan(after: 0.5)
    }

    private func stop() {
        scanTask?.cancel()
        privateEngine = nil
        sharedEngine = nil
        isFetching = false
        isSending = false
        pendingChanges = 0
    }

    private func makeEngine(database: CKDatabase) -> CKSyncEngine {
        let scope = database.databaseScope
        var serialization: CKSyncEngine.State.Serialization?
        if let data = files.loadData(FileNames.engine(scope)) {
            serialization = try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: data)
        }
        let configuration = CKSyncEngine.Configuration(
            database: database, stateSerialization: serialization, delegate: self)
        return CKSyncEngine(configuration)
    }

    private func engine(for scope: CKDatabase.Scope) -> CKSyncEngine? {
        scope == .shared ? sharedEngine : privateEngine
    }

    private func observeChanges() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: ModelContext.didSave, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleScan() }
        })
        observers.append(center.addObserver(forName: AnnotationStore.didChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleScan(after: 3) }
        })
        observers.append(center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.scheduleScan(after: 0.5)
                Task {
                    await self.refreshAccountStatus()
                    // Push notifications normally announce changes; fetching on
                    // return also covers any that were missed.
                    try? await self.privateEngine?.fetchChanges()
                    try? await self.sharedEngine?.fetchChanges()
                }
            }
        })
        observers.append(center.addObserver(forName: .CKAccountChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                Task { await self.refreshAccountStatus() }
            }
        })
    }

    func refreshAccountStatus() async {
        guard let container else { return }
        do {
            accountStatus = try await container.accountStatus()
        } catch {
            accountStatus = .couldNotDetermine
        }
        switch accountStatus {
        case .available:
            if problem == Self.signedOutMessage { problem = nil }
        case .noAccount, .restricted:
            problem = Self.signedOutMessage
        default:
            break
        }
    }

    private static let signedOutMessage = "Sign in to iCloud in the Settings app to sync your library."

    /// Fetches and sends now (the "Sync Now" button, and pull to refresh).
    func syncNow() async {
        guard isEnabled, privateEngine != nil else { return }
        scan()
        for engine in [privateEngine, sharedEngine].compactMap({ $0 }) {
            do {
                try await engine.fetchChanges()
                try await engine.sendChanges()
            } catch {
                report(error)
            }
        }
        await refreshChoirDetails()
    }

    // MARK: - Finding local changes

    func scheduleScan(after delay: TimeInterval = 1.5) {
        guard isEnabled, privateEngine != nil else { return }
        scanTask?.cancel()
        scanTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.scan()
        }
    }

    /// Compares the library with the ledger and queues the differences.
    func scan() {
        guard let context = modelContainer?.mainContext, privateEngine != nil else { return }
        let local = Self.localState(context: context)
        let plan = SyncDiff.plan(local: local, ledger: ledger) { [weak self] library in
            !(self?.canEdit(library) ?? false)
        }
        var byScope: [CKDatabase.Scope: [CKSyncEngine.PendingRecordZoneChange]] = [:]
        for save in plan.saves {
            let location = CloudLibrary.location(of: save.library)
            guard hasFetchedOnce(location.scope) else { continue }
            byScope[location.scope, default: []].append(
                .saveRecord(CKRecord.ID(recordName: save.recordName, zoneID: location.zoneID)))
        }
        for delete in plan.deletes {
            let location = CloudLibrary.location(of: delete.library)
            guard hasFetchedOnce(location.scope) else { continue }
            byScope[location.scope, default: []].append(
                .deleteRecord(CKRecord.ID(recordName: delete.recordName, zoneID: location.zoneID)))
        }
        for (scope, changes) in byScope {
            guard let engine = engine(for: scope) else { continue }
            let existing = Set(engine.state.pendingRecordZoneChanges)
            let new = changes.filter { !existing.contains($0) }
            if !new.isEmpty { engine.state.add(pendingRecordZoneChanges: new) }
        }
        updatePendingCount()
    }

    /// Every record the library has now.
    static func localState(context: ModelContext, annotations: AnnotationStore = AnnotationStore()) -> [LocalRecordState] {
        var result: [LocalRecordState] = []
        let scores = (try? context.fetch(FetchDescriptor<Score>())) ?? []
        for score in scores {
            result.append(LocalRecordState(
                recordName: SyncRecordName.score(score.id),
                library: score.cloudLibrary,
                fingerprint: ScoreRecordValues(score: score).fingerprint))
            result.append(LocalRecordState(
                recordName: SyncRecordName.scoreFile(score.id),
                library: score.cloudLibrary,
                fingerprint: score.contentHash))
        }
        let setlists = (try? context.fetch(FetchDescriptor<Setlist>())) ?? []
        for setlist in setlists {
            result.append(LocalRecordState(
                recordName: SyncRecordName.setlist(setlist.id),
                library: setlist.cloudLibrary,
                fingerprint: SetlistRecordValues(setlist: setlist).fingerprint))
        }
        for page in annotations.allPages() {
            guard let fingerprint = SyncFingerprint.ofFile(at: page.url) else { continue }
            result.append(LocalRecordState(
                recordName: SyncRecordName.annotation(scoreID: page.scoreID, page: page.page),
                library: nil,
                fingerprint: fingerprint))
        }
        return result
    }

    private func hasFetchedOnce(_ scope: CKDatabase.Scope) -> Bool {
        UserDefaults.standard.bool(forKey: Keys.fetchedOnce + (scope == .shared ? "shared" : "private"))
    }

    private func setFetchedOnce(_ scope: CKDatabase.Scope, _ value: Bool) {
        UserDefaults.standard.set(value, forKey: Keys.fetchedOnce + (scope == .shared ? "shared" : "private"))
    }

    private func updatePendingCount() {
        pendingChanges = [privateEngine, sharedEngine].compactMap { $0 }
            .reduce(0) { $0 + $1.state.pendingRecordZoneChanges.count }
    }

    // MARK: - Permissions

    /// Whether this person can change things in a library.
    func canEdit(_ library: String?) -> Bool {
        guard let library else { return true }
        if CloudLibrary.isHosted(library) { return true }
        return choirs.first { $0.id == library }?.canEdit ?? false
    }

    func canEdit(_ score: Score) -> Bool { canEdit(score.cloudLibrary) }
    func canEdit(_ setlist: Setlist) -> Bool { canEdit(setlist.cloudLibrary) }

    func choir(_ library: String?) -> ChoirInfo? {
        guard let library else { return nil }
        return choirs.first { $0.id == library }
    }

    /// Libraries an editor can add scores to.
    var editableChoirs: [ChoirInfo] { choirs.filter(\.canEdit) }

    // MARK: - Ledger

    private func saveLedger() {
        files.save(ledger, to: FileNames.ledger)
    }

    private func saveChoirs() {
        files.save(choirs, to: FileNames.choirs)
    }

    func upsertChoir(_ info: ChoirInfo) {
        if let index = choirs.firstIndex(where: { $0.id == info.id }) {
            if choirs[index] != info { choirs[index] = info }
        } else {
            choirs.append(info)
        }
        choirs.sort { ($0.isOwner ? 0 : 1, $0.name) < ($1.isOwner ? 0 : 1, $1.name) }
        saveChoirs()
    }

    func removeChoirInfo(_ library: String) {
        choirs.removeAll { $0.id == library }
        saveChoirs()
    }

    // MARK: - Errors

    func report(_ error: Error) {
        guard let ckError = error as? CKError else {
            problem = error.localizedDescription
            return
        }
        switch ckError.code {
        case .quotaExceeded:
            problem = "Your iCloud storage is full, so changes can't be uploaded. Free up space in the Settings app; everything stays on this device meanwhile."
        case .notAuthenticated:
            problem = Self.signedOutMessage
        case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited, .zoneBusy, .operationCancelled:
            break // Temporary: the sync engine tries again by itself.
        case .partialFailure:
            if let first = ckError.partialErrorsByItemID?.values.first { report(first) }
        default:
            problem = ckError.localizedDescription
        }
    }

    func clearProblem() { problem = nil }

    // MARK: - Engine access for sharing

    var cloudContainer: CKContainer? { container }

    func addPendingZoneSave(_ zoneID: CKRecordZone.ID) {
        privateEngine?.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
    }

    func addPendingZoneDelete(_ zoneID: CKRecordZone.ID) {
        privateEngine?.state.add(pendingDatabaseChanges: [.deleteZone(zoneID)])
    }

    func fetchShared() async {
        try? await sharedEngine?.fetchChanges()
    }

    // MARK: - Space used

    /// Bytes this person's iCloud holds for them: their library, any Choir
    /// Library they host, and their annotations. Choirs they joined count
    /// against the choir owner's iCloud, not theirs.
    func iCloudBytesUsed() -> Int64 {
        guard let context = modelContainer?.mainContext else { return 0 }
        let scores = (try? context.fetch(FetchDescriptor<Score>())) ?? []
        var total: Int64 = 0
        for score in scores where score.cloudLibrary == nil || CloudLibrary.isHosted(score.cloudLibrary) {
            total += Self.size(of: score.fileURL)
        }
        for page in AnnotationStore().allPages() {
            total += Self.size(of: page.url)
        }
        return total
    }

    func bytesUsed(byChoir library: String) -> Int64 {
        guard let context = modelContainer?.mainContext else { return 0 }
        let scores = (try? context.fetch(FetchDescriptor<Score>())) ?? []
        return scores.filter { $0.cloudLibrary == library }.reduce(0) { $0 + Self.size(of: $1.fileURL) }
    }

    private static func size(of url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
    }
}

// MARK: - CKSyncEngineDelegate

extension CloudSync: CKSyncEngineDelegate {
    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        let scope = syncEngine.database.databaseScope
        // Ignore events from an engine that was replaced (sync turned off, or account changed).
        guard syncEngine === engine(for: scope) else { return }

        switch event {
        case .stateUpdate(let update):
            if let data = try? JSONEncoder().encode(update.stateSerialization) {
                files.saveData(data, to: FileNames.engine(scope))
            }

        case .accountChange(let change):
            handleAccountChange(change, scope: scope)

        case .fetchedDatabaseChanges(let changes):
            for modification in changes.modifications {
                zoneAppeared(modification.zoneID, scope: scope)
            }
            for deletion in changes.deletions {
                zoneDisappeared(deletion.zoneID, scope: scope)
            }

        case .fetchedRecordZoneChanges(let changes):
            applyFetched(changes, scope: scope)

        case .sentDatabaseChanges(let sent):
            for failure in sent.failedZoneSaves {
                report(failure.error)
            }

        case .sentRecordZoneChanges(let sent):
            handleSent(sent, scope: scope, engine: syncEngine)

        case .willFetchChanges:
            isFetching = true

        case .didFetchChanges:
            isFetching = false
            setFetchedOnce(scope, true)
            finishFetch()
            lastSync = Date()
            UserDefaults.standard.set(lastSync, forKey: Keys.lastSync)
            scheduleScan(after: 0.5)

        case .willSendChanges:
            isSending = true

        case .didSendChanges:
            isSending = false
            lastSync = Date()
            UserDefaults.standard.set(lastSync, forKey: Keys.lastSync)

        case .willFetchRecordZoneChanges, .didFetchRecordZoneChanges:
            break

        @unknown default:
            break
        }
        updatePendingCount()
    }

    func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let scope = syncEngine.database.databaseScope
        let pending = syncEngine.state.pendingRecordZoneChanges
            .filter { context.options.scope.contains($0) }
            .prefix(100)
        guard !pending.isEmpty else { return nil }

        var records: [CKRecord.ID: CKRecord] = [:]
        var dropped: [CKSyncEngine.PendingRecordZoneChange] = []
        for change in pending {
            guard case .saveRecord(let recordID) = change else { continue }
            if let record = makeRecord(recordID, scope: scope) {
                records[recordID] = record
            } else {
                dropped.append(change)
            }
        }
        if !dropped.isEmpty {
            syncEngine.state.remove(pendingRecordZoneChanges: dropped)
        }
        let droppedSet = Set(dropped)
        let changes = pending.filter { !droppedSet.contains($0) }
        guard !changes.isEmpty else { return nil }
        let provided = records
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: Array(changes)) { recordID in
            provided[recordID]
        }
    }
}

// MARK: - Building records to send

extension CloudSync {
    fileprivate func makeRecord(_ recordID: CKRecord.ID, scope: CKDatabase.Scope) -> CKRecord? {
        guard let context = modelContainer?.mainContext,
              let parsed = SyncRecordName.parse(recordID.recordName) else { return nil }
        let name = recordID.recordName
        let library = CloudLibrary.key(for: recordID.zoneID, scope: scope)
        guard canEdit(library) else { return nil }

        func base(_ type: String) -> CKRecord {
            if let entry = ledger.entries[name], entry.library == library,
               let fields = entry.systemFields,
               let record = RecordArchive.record(fromSystemFields: fields),
               record.recordType == type {
                return record
            }
            return CKRecord(recordType: type, recordID: recordID)
        }

        switch parsed {
        case .score(let id):
            guard let score = Self.fetchScore(id, context: context), score.cloudLibrary == library else { return nil }
            let values = ScoreRecordValues(score: score)
            let record = base(SyncRecordName.scoreType)
            values.write(to: record)
            inFlight[name] = values.fingerprint
            return record

        case .scoreFile(let id):
            guard let score = Self.fetchScore(id, context: context), score.cloudLibrary == library,
                  FileManager.default.fileExists(atPath: score.fileURL.path) else { return nil }
            let record = base(SyncRecordName.scoreFileType)
            record["contentHash"] = score.contentHash
            record["file"] = CKAsset(fileURL: score.fileURL)
            inFlight[name] = score.contentHash
            return record

        case .setlist(let id):
            guard let setlist = Self.fetchSetlist(id, context: context), setlist.cloudLibrary == library else { return nil }
            let values = SetlistRecordValues(setlist: setlist)
            let record = base(SyncRecordName.setlistType)
            values.write(to: record)
            inFlight[name] = values.fingerprint
            return record

        case .annotation(let scoreID, let page):
            guard library == nil else { return nil }
            let url = AnnotationStore().fileURL(scoreID: scoreID, page: page)
            guard let fingerprint = SyncFingerprint.ofFile(at: url) else { return nil }
            // Upload a snapshot, so later pen strokes can't change the file mid-upload.
            let snapshot = FileManager.default.temporaryDirectory
                .appendingPathComponent("upload-\(name).drawing")
            try? FileManager.default.removeItem(at: snapshot)
            guard (try? FileManager.default.copyItem(at: url, to: snapshot)) != nil else { return nil }
            let record = base(SyncRecordName.annotationType)
            record["scoreID"] = scoreID.uuidString
            record["page"] = page
            record["drawing"] = CKAsset(fileURL: snapshot)
            inFlight[name] = fingerprint
            return record
        }
    }

    static func fetchScore(_ id: UUID, context: ModelContext) -> Score? {
        var descriptor = FetchDescriptor<Score>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    static func fetchSetlist(_ id: UUID, context: ModelContext) -> Setlist? {
        var descriptor = FetchDescriptor<Setlist>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}

// MARK: - Results of sending

extension CloudSync {
    fileprivate func handleSent(_ sent: CKSyncEngine.Event.SentRecordZoneChanges, scope: CKDatabase.Scope, engine: CKSyncEngine) {
        for record in sent.savedRecords {
            let name = record.recordID.recordName
            let library = CloudLibrary.key(for: record.recordID.zoneID, scope: scope)
            let fingerprint = inFlight.removeValue(forKey: name) ?? ledger.entries[name]?.fingerprint ?? ""
            ledger.entries[name] = SyncLedger.Entry(
                library: library, fingerprint: fingerprint, systemFields: RecordArchive.systemFields(of: record))
            if case .annotation = SyncRecordName.parse(name) {
                try? FileManager.default.removeItem(
                    at: FileManager.default.temporaryDirectory.appendingPathComponent("upload-\(name).drawing"))
            }
        }

        var retry: [CKSyncEngine.PendingRecordZoneChange] = []
        var zonesToCreate: [CKRecordZone.ID] = []
        for failure in sent.failedRecordSaves {
            let record = failure.record
            let name = record.recordID.recordName
            let library = CloudLibrary.key(for: record.recordID.zoneID, scope: scope)
            inFlight.removeValue(forKey: name)
            switch failure.error.code {
            case .serverRecordChanged:
                // Someone saved this record since we last saw it. The change made
                // here is newer, so keep it: take the server's change tag and resend.
                if let server = failure.error.serverRecord {
                    var entry = ledger.entries[name] ?? SyncLedger.Entry(library: library, fingerprint: "")
                    entry.library = library
                    entry.systemFields = RecordArchive.systemFields(of: server)
                    ledger.entries[name] = entry
                }
                retry.append(.saveRecord(record.recordID))
            case .zoneNotFound, .userDeletedZone:
                if scope == .private {
                    zonesToCreate.append(record.recordID.zoneID)
                    retry.append(.saveRecord(record.recordID))
                }
            case .unknownItem:
                // The record was removed from iCloud: send it again as new.
                ledger.entries[name]?.systemFields = nil
                retry.append(.saveRecord(record.recordID))
            case .permissionFailure:
                if let library, var info = choir(library) {
                    info.canEdit = false
                    upsertChoir(info)
                }
                problem = "You can only view this Choir Library. Ask its owner to make you an editor."
            case .quotaExceeded:
                report(failure.error)
                retry.append(.saveRecord(record.recordID))
            case .networkFailure, .networkUnavailable, .zoneBusy, .serviceUnavailable,
                 .notAuthenticated, .operationCancelled, .requestRateLimited, .batchRequestFailed,
                 .assetFileModified:
                retry.append(.saveRecord(record.recordID))
            default:
                report(failure.error)
            }
        }
        if !zonesToCreate.isEmpty {
            engine.state.add(pendingDatabaseChanges: Set(zonesToCreate).map { .saveZone(CKRecordZone(zoneID: $0)) })
        }
        if !retry.isEmpty {
            engine.state.add(pendingRecordZoneChanges: retry)
        }

        for recordID in sent.deletedRecordIDs {
            forgetDeleted(recordID, scope: scope)
        }
        for (recordID, error) in sent.failedRecordDeletes {
            switch error.code {
            case .unknownItem, .zoneNotFound, .userDeletedZone:
                forgetDeleted(recordID, scope: scope)
            case .permissionFailure:
                forgetDeleted(recordID, scope: scope)
            case .networkFailure, .networkUnavailable, .zoneBusy, .serviceUnavailable,
                 .notAuthenticated, .operationCancelled, .requestRateLimited, .batchRequestFailed:
                engine.state.add(pendingRecordZoneChanges: [.deleteRecord(recordID)])
            default:
                report(error)
            }
        }
        saveLedger()
    }

    private func forgetDeleted(_ recordID: CKRecord.ID, scope: CKDatabase.Scope) {
        let name = recordID.recordName
        let library = CloudLibrary.key(for: recordID.zoneID, scope: scope)
        // A record moved to another library keeps its entry (for the new library).
        if let entry = ledger.entries[name], entry.library == library {
            ledger.entries.removeValue(forKey: name)
        }
    }
}

// MARK: - Accounts and zones

extension CloudSync {
    fileprivate func handleAccountChange(_ change: CKSyncEngine.Event.AccountChange, scope: CKDatabase.Scope) {
        switch change.changeType {
        case .signIn:
            // Nothing is known about this account yet: compare everything afresh.
            // Records already in iCloud are matched up by the first fetch.
            if scope == .private { resetSyncState(keepEngines: true) }
        case .signOut, .switchAccounts:
            // Your own library stays on the device. Choir music you received
            // through the old account is removed, as it was shared with that account.
            for choir in joinedChoirs { removeLibraryLocally(choir.id) }
            resetSyncState(keepEngines: false)
            if isEnabled { start() }
        @unknown default:
            break
        }
        Task { await refreshAccountStatus() }
    }

    private func resetSyncState(keepEngines: Bool) {
        ledger = SyncLedger()
        saveLedger()
        inFlight = [:]
        setFetchedOnce(.private, false)
        setFetchedOnce(.shared, false)
        if !keepEngines {
            files.remove(FileNames.engine(.private))
            files.remove(FileNames.engine(.shared))
            privateEngine = nil
            sharedEngine = nil
        }
    }

    fileprivate func zoneAppeared(_ zoneID: CKRecordZone.ID, scope: CKDatabase.Scope) {
        guard let library = CloudLibrary.key(for: zoneID, scope: scope) else { return }
        if choir(library) == nil {
            upsertChoir(ChoirInfo(
                id: library,
                name: "Choir Library",
                isOwner: scope == .private,
                canEdit: scope == .private,
                ownerName: nil))
        }
        Task { await refreshChoirDetails(library) }
    }

    fileprivate func zoneDisappeared(_ zoneID: CKRecordZone.ID, scope: CKDatabase.Scope) {
        guard let library = CloudLibrary.key(for: zoneID, scope: scope) else {
            // Your own library's zone was deleted (for example "Delete Data" in
            // iCloud settings). Keep everything here; it uploads again.
            for (name, entry) in ledger.entries where entry.library == nil {
                ledger.entries.removeValue(forKey: name)
            }
            privateEngine?.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
            saveLedger()
            return
        }
        if scope == .private {
            // Your hosted Choir Library was deleted on another of your devices.
            // Keep its music in your own library (it's yours) rather than lose it.
            moveLibraryToPersonal(library)
        } else {
            removeLibraryLocally(library)
        }
    }

    /// Removes a choir's music and lists from this device (left the choir, or
    /// the choir was deleted). Your private annotations on its scores are
    /// deleted too, everywhere.
    func removeLibraryLocally(_ library: String) {
        guard let context = modelContainer?.mainContext else { return }
        let scores = ((try? context.fetch(FetchDescriptor<Score>())) ?? []).filter { $0.cloudLibrary == library }
        let setlists = ((try? context.fetch(FetchDescriptor<Setlist>())) ?? []).filter { $0.cloudLibrary == library }
        for name in ledger.entries.keys where ledger.entries[name]?.library == library {
            ledger.entries.removeValue(forKey: name)
        }
        for name in ledger.pendingScores.keys where ledger.pendingScores[name]?.library == library {
            ledger.pendingScores.removeValue(forKey: name)
            if case .score(let id) = SyncRecordName.parse(name) {
                try? FileManager.default.removeItem(at: LibraryPaths.shared.scoreFileURL(storedFileName: "\(id.uuidString).pdf"))
            }
        }
        for setlist in setlists {
            ledger.pendingOrders.removeValue(forKey: SyncRecordName.setlist(setlist.id))
            context.delete(setlist)
        }
        for score in scores {
            removeScoreLocally(score, context: context)
        }
        removeChoirInfo(library)
        saveLedger()
        try? context.save()
    }

    /// Turns a hosted Choir Library's music and lists into your own.
    func moveLibraryToPersonal(_ library: String) {
        guard let context = modelContainer?.mainContext else { return }
        for score in (try? context.fetch(FetchDescriptor<Score>())) ?? [] where score.cloudLibrary == library {
            score.cloudLibrary = nil
        }
        for setlist in (try? context.fetch(FetchDescriptor<Setlist>())) ?? [] where setlist.cloudLibrary == library {
            setlist.cloudLibrary = nil
        }
        // The zone and its records are gone: nothing to delete there.
        for name in ledger.entries.keys where ledger.entries[name]?.library == library {
            ledger.entries.removeValue(forKey: name)
        }
        removeChoirInfo(library)
        saveLedger()
        try? context.save()
    }

    func removeScoreLocally(_ score: Score, context: ModelContext) {
        let id = score.id
        let file = score.fileURL
        context.delete(score)
        try? FileManager.default.removeItem(at: file)
        // Annotation entries stay in the ledger, so their deletion reaches iCloud.
        AnnotationStore().deleteAll(for: id)
        ThumbnailCache.shared.remove(id)
    }

    /// Reads each choir's name, owner and this person's permission from its share.
    func refreshChoirDetails(_ only: String? = nil) async {
        guard let container, accountStatus == .available || accountStatus == .couldNotDetermine else { return }
        for info in choirs where only == nil || info.id == only {
            let location = CloudLibrary.location(of: info.id)
            let database = location.scope == .shared ? container.sharedCloudDatabase : container.privateCloudDatabase
            let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: location.zoneID)
            do {
                let record = try await database.record(for: shareID)
                if let share = record as? CKShare { updateChoir(info.id, from: share) }
            } catch let error as CKError where error.code == .unknownItem || error.code == .zoneNotFound {
                if location.scope == .shared {
                    removeLibraryLocally(info.id)
                }
            } catch {
                // Offline or similar: keep what we know.
            }
        }
    }

    func updateChoir(_ library: String, from share: CKShare) {
        let current = choir(library)
        let title = share[CKShare.SystemFieldKey.title] as? String
        let isOwner = share.currentUserParticipant?.role == .owner || CloudLibrary.isHosted(library)
        let permission = share.currentUserParticipant?.permission
        let ownerName = share.owner.userIdentity.nameComponents.map {
            PersonNameComponentsFormatter.localizedString(from: $0, style: .default)
        }
        upsertChoir(ChoirInfo(
            id: library,
            name: (title?.isEmpty == false ? title : nil) ?? current?.name ?? "Choir Library",
            isOwner: isOwner,
            canEdit: isOwner || permission == .readWrite,
            ownerName: ownerName ?? current?.ownerName,
            memberCount: share.participants.filter { $0.role != .owner && $0.acceptanceStatus == .accepted }.count))
    }
}
