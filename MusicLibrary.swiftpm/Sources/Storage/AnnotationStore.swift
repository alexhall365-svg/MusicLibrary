import Foundation
import PencilKit

/// Stores PencilKit drawings per page, separately from the PDF, in PDF page
/// coordinates (points), so they line up at any display size.
///
/// Layout: Annotations/<score id>/page-<index>.drawing
/// (A future layers feature can add page-<index>.<layer>.drawing files alongside.)
struct AnnotationStore {
    var paths: LibraryPaths = .shared

    /// Posted after annotations are saved or deleted on this device (for sync).
    static let didChange = Notification.Name("AnnotationStore.didChange")
    /// Posted after annotations arrive from another device. `object` is the score ID.
    static let remoteDidChange = Notification.Name("AnnotationStore.remoteDidChange")

    static func postRemoteChange(scoreID: UUID, page: Int) {
        NotificationCenter.default.post(name: remoteDidChange, object: scoreID, userInfo: ["page": page])
    }

    struct Page {
        let scoreID: UUID
        let page: Int
        let url: URL
    }

    /// Every annotated page on the device.
    func allPages() -> [Page] {
        let fileManager = FileManager.default
        let folders = (try? fileManager.contentsOfDirectory(
            at: paths.annotationsDirectory, includingPropertiesForKeys: nil)) ?? []
        var pages: [Page] = []
        for folder in folders {
            guard let scoreID = UUID(uuidString: folder.lastPathComponent) else { continue }
            let files = (try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            for file in files where file.pathExtension == "drawing" {
                let name = file.deletingPathExtension().lastPathComponent
                guard name.hasPrefix("page-"), let page = Int(name.dropFirst(5)) else { continue }
                pages.append(Page(scoreID: scoreID, page: page, url: file))
            }
        }
        return pages
    }

    /// Deletes one page's annotations without announcing a local change.
    func removeFile(scoreID: UUID, page: Int) {
        try? FileManager.default.removeItem(at: fileURL(scoreID: scoreID, page: page))
        Self.postRemoteChange(scoreID: scoreID, page: page)
    }

    func fileURL(scoreID: UUID, page: Int) -> URL {
        paths.annotationsDirectory(for: scoreID).appendingPathComponent("page-\(page).drawing")
    }

    func loadDrawing(scoreID: UUID, page: Int) -> PKDrawing {
        guard let data = try? Data(contentsOf: fileURL(scoreID: scoreID, page: page)),
              let drawing = try? PKDrawing(data: data) else {
            return PKDrawing()
        }
        return drawing
    }

    func save(_ drawing: PKDrawing, scoreID: UUID, page: Int) {
        let url = fileURL(scoreID: scoreID, page: page)
        defer { NotificationCenter.default.post(name: Self.didChange, object: scoreID) }
        if drawing.strokes.isEmpty {
            try? FileManager.default.removeItem(at: url)
            return
        }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try drawing.dataRepresentation().write(to: url, options: .atomic)
        } catch {
            print("Could not save annotations: \(error)")
        }
    }

    func hasAnnotations(for scoreID: UUID) -> Bool {
        let contents = try? FileManager.default.contentsOfDirectory(
            at: paths.annotationsDirectory(for: scoreID), includingPropertiesForKeys: nil)
        return !(contents ?? []).isEmpty
    }

    func deleteAll(for scoreID: UUID) {
        try? FileManager.default.removeItem(at: paths.annotationsDirectory(for: scoreID))
        NotificationCenter.default.post(name: Self.didChange, object: scoreID)
    }
}
