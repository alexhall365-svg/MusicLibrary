import SwiftUI
import UIKit

/// Shows one page, or two side by side, and pre-renders the pages around them.
struct SpreadView: UIViewRepresentable {
    let renderer: PageRenderer
    let pages: [Int]
    let annotating: Bool
    let controller: AnnotationController
    /// Passed so SwiftUI updates the view when the tool changes.
    let toolKey: String

    func makeUIView(context: Context) -> SpreadContainerView {
        SpreadContainerView()
    }

    func updateUIView(_ view: SpreadContainerView, context: Context) {
        view.configure(renderer: renderer, pages: pages, annotating: annotating, controller: controller)
    }

    static func dismantleUIView(_ view: SpreadContainerView, coordinator: ()) {
        view.flushAll()
    }
}

final class SpreadContainerView: UIView {
    private var pageViews: [ScorePageView] = []
    private var renderer: PageRenderer?
    private var pages: [Int] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(renderer: PageRenderer, pages: [Int], annotating: Bool, controller: AnnotationController) {
        while pageViews.count < pages.count {
            let view = ScorePageView()
            addSubview(view)
            pageViews.append(view)
        }
        while pageViews.count > pages.count {
            let view = pageViews.removeLast()
            view.flushSave()
            view.removeFromSuperview()
        }
        for (index, (view, page)) in zip(pageViews, pages).enumerated() {
            view.annotationController = controller
            if pages.count == 2 {
                view.alignment = index == 0 ? .trailing : .leading
            } else {
                view.alignment = .center
            }
            view.configure(renderer: renderer, pageIndex: page)
            view.setAnnotating(annotating, tool: controller.pkTool, fingerDrawing: controller.fingerDrawing)
        }
        let changed = renderer !== self.renderer || pages != self.pages
        self.renderer = renderer
        self.pages = pages
        setNeedsLayout()
        if changed { prefetchNeighbours() }
    }

    func flushAll() {
        pageViews.forEach { $0.flushSave() }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let count = max(pageViews.count, 1)
        let width = bounds.width / CGFloat(count)
        for (index, view) in pageViews.enumerated() {
            view.frame = CGRect(x: CGFloat(index) * width, y: 0, width: width, height: bounds.height)
        }
        prefetchNeighbours()
    }

    private var lastPrefetchKey: String?

    /// Renders the next two spreads and the previous one in the background.
    private func prefetchNeighbours() {
        guard let renderer, let first = pages.first, bounds.width > 0, bounds.height > 0 else { return }
        let perSpread = max(pages.count, 1)
        let key = "\(ObjectIdentifier(renderer).hashValue)-\(first)-\(perSpread)-\(bounds.size)"
        guard key != lastPrefetchKey else { return }
        lastPrefetchKey = key

        let slot = CGSize(width: bounds.width / CGFloat(perSpread), height: bounds.height)
        let scale = traitCollection.displayScale
        let ahead = Array((first + perSpread)..<(first + perSpread * 3))
        let behind = Array(max(0, first - perSpread)..<first)
        for page in ahead + behind where page < renderer.pageCount {
            let size = renderer.pageSize(page)
            let fit = min(slot.width / max(size.width, 1), slot.height / max(size.height, 1))
            renderer.prefetch(page: page, pixelWidth: PageRenderer.bucket(size.width * fit * scale))
        }
    }
}
