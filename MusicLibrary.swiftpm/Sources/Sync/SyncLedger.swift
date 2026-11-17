import Foundation

/// What this device last exchanged with iCloud, one entry per record.
///
/// Sync works by comparing the library with the ledger: anything new or changed
/// since the last exchange is uploaded, and anything in the ledger that is no
/// longer in the library is deleted. Changes received from iCloud update the
/// ledger first, so they are never sent back.
struct SyncLedger: Codable, Equatable {
    struct Entry: Codable, Equatable {
        /// The library the record was last stored in (nil: your own library).
        var library: String?
        /// The values last sent or received (see `SyncFingerprint`).
        var fingerprint: String
        /// CloudKit's system fields (identity and change tag) of the record.
        var systemFields: Data?
    }

    var entries: [String: Entry] = [:]
    /// Setlists received before all of their scores; relinked as scores arrive.
    var pendingOrders: [String: [String]] = [:]
    /// Score details received before their PDF; the score is added once the PDF arrives.
    var pendingScores: [String: PendingScore] = [:]

    struct PendingScore: Codable, Equatable {
        var library: String?
        var values: ScoreRecordValues
        var systemFields: Data?
    }
}

/// One record as the library has it now.
struct LocalRecordState: Equatable {
    var recordName: String
    var library: String?
    var fingerprint: String
}

struct SyncPlan: Equatable {
    struct Delete: Equatable {
        var recordName: String
        var library: String?
    }

    var saves: [LocalRecordState] = []
    var deletes: [Delete] = []

    var isEmpty: Bool { saves.isEmpty && deletes.isEmpty }
}

enum SyncDiff {
    /// Works out what to upload and delete.
    ///
    /// - `readOnly`: libraries this person can't change (a choir they joined as a
    ///   member). Local differences there are never sent.
    static func plan(local: [LocalRecordState], ledger: SyncLedger, readOnly: (String?) -> Bool) -> SyncPlan {
        var plan = SyncPlan()
        var seen = Set<String>()
        for item in local {
            seen.insert(item.recordName)
            guard !readOnly(item.library) else { continue }
            if let entry = ledger.entries[item.recordName] {
                if entry.library != item.library {
                    // Moved between libraries: remove the old copy, save the new one.
                    if !readOnly(entry.library) {
                        plan.deletes.append(.init(recordName: item.recordName, library: entry.library))
                    }
                    plan.saves.append(item)
                } else if entry.fingerprint != item.fingerprint {
                    plan.saves.append(item)
                }
            } else {
                plan.saves.append(item)
            }
        }
        for (name, entry) in ledger.entries where !seen.contains(name) && !readOnly(entry.library) {
            plan.deletes.append(.init(recordName: name, library: entry.library))
        }
        plan.saves.sort { $0.recordName < $1.recordName }
        plan.deletes.sort { $0.recordName < $1.recordName }
        return plan
    }
}

/// Reads and writes small JSON files in the sync folder.
struct SyncFileStore {
    let directory: URL

    static var shared: SyncFileStore {
        SyncFileStore(directory: LibraryPaths.shared.root.appendingPathComponent("Sync", isDirectory: true))
    }

    func load<T: Decodable>(_ type: T.Type, from name: String) -> T? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(name)) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    func save<T: Encodable>(_ value: T, to name: String) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(value)
            try data.write(to: directory.appendingPathComponent(name), options: .atomic)
        } catch {
            print("Could not save \(name): \(error)")
        }
    }

    func loadData(_ name: String) -> Data? {
        try? Data(contentsOf: directory.appendingPathComponent(name))
    }

    func saveData(_ data: Data, to name: String) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: directory.appendingPathComponent(name), options: .atomic)
    }

    func remove(_ name: String) {
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
    }
}
