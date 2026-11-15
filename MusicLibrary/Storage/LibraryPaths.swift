import Foundation

/// Where everything is stored on the device.
///
/// Everything under `root` (database, PDFs, annotations) is the user's data and is
/// what a future backup feature needs to archive. `cachesRoot` can be rebuilt.
struct LibraryPaths: Sendable {
    let root: URL
    let cachesRoot: URL

    static let shared: LibraryPaths = {
        let fileManager = FileManager.default
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return LibraryPaths(
            root: support.appendingPathComponent("MusicLibrary", isDirectory: true),
            cachesRoot: caches.appendingPathComponent("MusicLibrary", isDirectory: true)
        )
    }()

    var databaseURL: URL { root.appendingPathComponent("Library.store") }
    var scoresDirectory: URL { root.appendingPathComponent("Scores", isDirectory: true) }
    var annotationsDirectory: URL { root.appendingPathComponent("Annotations", isDirectory: true) }
    var thumbnailsDirectory: URL { cachesRoot.appendingPathComponent("Thumbnails", isDirectory: true) }
    var exportsDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("Exports", isDirectory: true)
    }

    func scoreFileURL(storedFileName: String) -> URL {
        scoresDirectory.appendingPathComponent(storedFileName)
    }

    func annotationsDirectory(for scoreID: UUID) -> URL {
        annotationsDirectory.appendingPathComponent(scoreID.uuidString, isDirectory: true)
    }

    func thumbnailURL(for scoreID: UUID) -> URL {
        thumbnailsDirectory.appendingPathComponent("\(scoreID.uuidString).jpg")
    }

    func ensureDirectories() throws {
        let fileManager = FileManager.default
        for directory in [root, scoresDirectory, annotationsDirectory, thumbnailsDirectory] {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }
}
