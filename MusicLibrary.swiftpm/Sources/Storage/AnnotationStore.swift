import Foundation
import PencilKit

/// Stores PencilKit drawings per page, separately from the PDF, in PDF page
/// coordinates (points), so they line up at any display size.
///
/// Layout: Annotations/<score id>/page-<index>.drawing
/// (A future layers feature can add page-<index>.<layer>.drawing files alongside.)
struct AnnotationStore {
    var paths: LibraryPaths = .shared

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

    func deleteAll(for scoreID: UUID) {
        try? FileManager.default.removeItem(at: paths.annotationsDirectory(for: scoreID))
    }
}
