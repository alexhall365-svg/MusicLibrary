import UIKit
import PDFKit

/// First-page thumbnails, cached in memory and on disk.
final class ThumbnailCache: @unchecked Sendable {
    static let shared = ThumbnailCache()

    private let memory = NSCache<NSString, UIImage>()
    private let queue = DispatchQueue(label: "ThumbnailCache", qos: .utility, attributes: .concurrent)
    private let paths = LibraryPaths.shared

    func cachedImage(for scoreID: UUID) -> UIImage? {
        memory.object(forKey: scoreID.uuidString as NSString)
    }

    func thumbnail(for scoreID: UUID, pdfURL: URL) async -> UIImage? {
        if let image = cachedImage(for: scoreID) { return image }
        return await withCheckedContinuation { continuation in
            queue.async {
                let image = self.loadOrRender(scoreID: scoreID, pdfURL: pdfURL)
                if let image {
                    self.memory.setObject(image, forKey: scoreID.uuidString as NSString)
                }
                continuation.resume(returning: image)
            }
        }
    }

    func remove(_ scoreID: UUID) {
        memory.removeObject(forKey: scoreID.uuidString as NSString)
        try? FileManager.default.removeItem(at: paths.thumbnailURL(for: scoreID))
    }

    private func loadOrRender(scoreID: UUID, pdfURL: URL) -> UIImage? {
        let url = paths.thumbnailURL(for: scoreID)
        if let data = try? Data(contentsOf: url), let image = UIImage(data: data) {
            return image
        }
        guard let document = PDFDocument(url: pdfURL), let page = document.page(at: 0) else {
            return nil
        }
        let bounds = page.bounds(for: .cropBox)
        let width: CGFloat = 400
        let height = width * bounds.height / max(bounds.width, 1)
        let image = page.thumbnail(of: CGSize(width: width, height: height), for: .cropBox)
        if let data = image.jpegData(compressionQuality: 0.8) {
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
        }
        return image
    }
}
