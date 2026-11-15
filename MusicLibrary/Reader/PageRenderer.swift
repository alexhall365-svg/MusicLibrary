import UIKit
import PDFKit

/// Renders PDF pages to images, caching them and rendering upcoming pages ahead
/// of time so page turns are instant even in 100+ page scores.
final class PageRenderer: @unchecked Sendable {
    let scoreID: UUID
    let pageCount: Int
    private let pageSizes: [CGSize]

    // Separate documents per queue so PDFKit is never used from two threads at once.
    private let onDemandDocument: PDFDocument?
    private let prefetchDocument: PDFDocument?
    private let onDemandQueue = DispatchQueue(label: "PageRenderer.onDemand", qos: .userInteractive)
    private let prefetchQueue = DispatchQueue(label: "PageRenderer.prefetch", qos: .utility)
    private let cache = NSCache<NSString, UIImage>()

    init(scoreID: UUID, url: URL) {
        self.scoreID = scoreID
        let document = PDFDocument(url: url)
        onDemandDocument = document
        prefetchDocument = PDFDocument(url: url)
        pageCount = document?.pageCount ?? 0
        var sizes: [CGSize] = []
        for index in 0..<pageCount {
            sizes.append(document?.page(at: index).map(PageRenderer.displaySize(of:)) ?? CGSize(width: 595, height: 842))
        }
        pageSizes = sizes
        cache.totalCostLimit = 300 * 1024 * 1024
    }

    /// Page size in points, accounting for rotation.
    func pageSize(_ index: Int) -> CGSize {
        pageSizes.indices.contains(index) ? pageSizes[index] : CGSize(width: 595, height: 842)
    }

    /// Rounds widths up to steps of 256 px so nearby sizes share cached images.
    static func bucket(_ pixelWidth: CGFloat) -> Int {
        max(256, Int((pixelWidth / 256).rounded(.up)) * 256)
    }

    func cachedImage(page: Int, pixelWidth: Int) -> UIImage? {
        cache.object(forKey: Self.key(page, pixelWidth))
    }

    func image(page: Int, pixelWidth: Int, completion: @escaping (UIImage?) -> Void) {
        onDemandQueue.async { [weak self] in
            guard let self else { return }
            let image = self.cachedImage(page: page, pixelWidth: pixelWidth)
                ?? self.renderAndCache(self.onDemandDocument, page: page, pixelWidth: pixelWidth)
            DispatchQueue.main.async { completion(image) }
        }
    }

    func prefetch(page: Int, pixelWidth: Int) {
        guard page >= 0, page < pageCount else { return }
        prefetchQueue.async { [weak self] in
            guard let self, self.cachedImage(page: page, pixelWidth: pixelWidth) == nil else { return }
            _ = self.renderAndCache(self.prefetchDocument, page: page, pixelWidth: pixelWidth)
        }
    }

    private func renderAndCache(_ document: PDFDocument?, page index: Int, pixelWidth: Int) -> UIImage? {
        guard let page = document?.page(at: index) else { return nil }
        let size = Self.displaySize(of: page)
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = CGFloat(pixelWidth) / size.width
        let pixelSize = CGSize(width: CGFloat(pixelWidth), height: (size.height * scale).rounded())

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: pixelSize, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: pixelSize))
            let cg = context.cgContext
            cg.interpolationQuality = .high
            cg.translateBy(x: 0, y: pixelSize.height)
            cg.scaleBy(x: scale, y: -scale)
            page.draw(with: .cropBox, to: cg)
        }
        let cost = Int(pixelSize.width * pixelSize.height * 4)
        cache.setObject(image, forKey: Self.key(index, pixelWidth), cost: cost)
        return image
    }

    private static func key(_ page: Int, _ pixelWidth: Int) -> NSString {
        "\(page)-\(pixelWidth)" as NSString
    }

    static func displaySize(of page: PDFPage) -> CGSize {
        let bounds = page.bounds(for: .cropBox)
        return page.rotation % 180 == 0
            ? bounds.size
            : CGSize(width: bounds.height, height: bounds.width)
    }
}
