import Foundation
import PDFKit
import CoreGraphics

/// A 32 × 32 greyscale thumbnail of a PDF's first page, used to spot the same
/// page saved as different files (e.g. rescanned or re-exported).
enum PageFingerprint {
    static let side = 32

    static func make(for url: URL) async -> Data? {
        await Task.detached(priority: .utility) {
            PageFingerprint.makeSynchronously(for: url)
        }.value
    }

    static func makeSynchronously(for url: URL) -> Data? {
        guard let page = PDFDocument(url: url)?.page(at: 0) else { return nil }
        let bounds = page.bounds(for: .cropBox)
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        var pixels = [UInt8](repeating: 255, count: side * side)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8,
                bytesPerRow: side, space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }
            context.setFillColor(gray: 1, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: side, height: side))
            context.interpolationQuality = .medium
            let rotated = page.rotation % 180 != 0
            let width = rotated ? bounds.height : bounds.width
            let height = rotated ? bounds.width : bounds.height
            context.scaleBy(x: CGFloat(side) / width, y: CGFloat(side) / height)
            page.draw(with: .cropBox, to: context)
            return true
        }
        return drawn ? Data(pixels) : nil
    }

    /// Mean absolute difference between two fingerprints, 0 (same) to 1.
    static func difference(_ a: [UInt8], _ b: [UInt8]) -> Double? {
        guard a.count == b.count, !a.isEmpty else { return nil }
        var total = 0
        for index in a.indices { total += abs(Int(a[index]) - Int(b[index])) }
        return Double(total) / Double(a.count * 255)
    }
}
