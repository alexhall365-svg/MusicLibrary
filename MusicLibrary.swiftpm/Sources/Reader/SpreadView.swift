import SwiftUI
import UIKit

enum ReaderGesture {
    case previous, next, toggleControls
}

/// Shows one page, or two side by side, with pinch-to-zoom, and reports page
/// turn taps and swipes. Pre-renders the pages around the current ones.
struct SpreadView: UIViewRepresentable {
    let renderer: PageRenderer
    let pages: [Int]
    let annotating: Bool
    let controller: AnnotationController
    /// Passed so SwiftUI updates the view when the tool changes.
    let toolKey: String
    let pageDescription: String
    let onGesture: (ReaderGesture) -> Void

    func makeUIView(context: Context) -> ZoomableSpreadView {
        ZoomableSpreadView()
    }

    func updateUIView(_ view: ZoomableSpreadView, context: Context) {
        view.onGesture = onGesture
        view.accessibilityValue = pageDescription
        view.configure(renderer: renderer, pages: pages, annotating: annotating, controller: controller)
    }

    static func dismantleUIView(_ view: ZoomableSpreadView, coordinator: ()) {
        view.flushAll()
    }
}

/// A zoomable host for the pages. Taps on the left or right third turn the page,
/// the middle shows or hides the controls; swipes turn pages when not zoomed.
/// When zoomed, one finger pans (two while annotating, so the pen can draw).
final class ZoomableSpreadView: UIView, UIScrollViewDelegate {
    var onGesture: ((ReaderGesture) -> Void)?

    private let scrollView = UIScrollView()
    private let container = SpreadContainerView()
    private var renderer: PageRenderer?
    private var pages: [Int] = []
    private var annotating = false
    private var lastSize: CGSize = .zero

    private lazy var tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
    private lazy var swipeLeft: UISwipeGestureRecognizer = {
        let swipe = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipe(_:)))
        swipe.direction = .left
        return swipe
    }()
    private lazy var swipeRight: UISwipeGestureRecognizer = {
        let swipe = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipe(_:)))
        swipe.direction = .right
        return swipe
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        scrollView.delegate = self
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 4
        scrollView.bouncesZoom = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.isScrollEnabled = false
        scrollView.backgroundColor = .clear
        addSubview(scrollView)
        scrollView.addSubview(container)
        addGestureRecognizer(tap)
        addGestureRecognizer(swipeLeft)
        addGestureRecognizer(swipeRight)

        isAccessibilityElement = true
        accessibilityLabel = "Score"
        accessibilityHint = "Swipe up or down with one finger for page actions."
        accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: "Next page") { [weak self] _ in self?.onGesture?(.next); return true },
            UIAccessibilityCustomAction(name: "Previous page") { [weak self] _ in self?.onGesture?(.previous); return true },
            UIAccessibilityCustomAction(name: "Show or hide controls") { [weak self] _ in self?.onGesture?(.toggleControls); return true },
        ]
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(renderer: PageRenderer, pages: [Int], annotating: Bool, controller: AnnotationController) {
        if renderer !== self.renderer || pages != self.pages {
            resetZoom()
        }
        self.renderer = renderer
        self.pages = pages
        self.annotating = annotating
        container.configure(renderer: renderer, pages: pages, annotating: annotating, controller: controller)
        tap.isEnabled = !annotating
        scrollView.panGestureRecognizer.minimumNumberOfTouches = annotating ? 2 : 1
        updateGestures()
    }

    func flushAll() {
        container.flushAll()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        scrollView.frame = bounds
        if bounds.size != lastSize {
            lastSize = bounds.size
            resetZoom()
            container.frame = CGRect(origin: .zero, size: bounds.size)
            scrollView.contentSize = bounds.size
        }
    }

    // MARK: Zoom

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        container
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        updateGestures()
    }

    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        container.setZoomScale(scale)
        updateGestures()
    }

    private func resetZoom() {
        if scrollView.zoomScale != 1 {
            scrollView.setZoomScale(1, animated: false)
        }
        container.setZoomScale(1)
        updateGestures()
    }

    private var isZoomed: Bool { scrollView.zoomScale > 1.01 }

    private func updateGestures() {
        scrollView.isScrollEnabled = isZoomed
        swipeLeft.isEnabled = !isZoomed && !annotating
        swipeRight.isEnabled = !isZoomed && !annotating
    }

    // MARK: Page turns

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard bounds.width > 0 else { return }
        let x = gesture.location(in: self).x / bounds.width
        if x < 0.3 {
            onGesture?(.previous)
        } else if x > 0.7 {
            onGesture?(.next)
        } else {
            onGesture?(.toggleControls)
        }
    }

    @objc private func handleSwipe(_ gesture: UISwipeGestureRecognizer) {
        onGesture?(gesture.direction == .left ? .next : .previous)
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

    /// Lets the pages render sharper images while zoomed in.
    func setZoomScale(_ scale: CGFloat) {
        pageViews.forEach { $0.zoomScale = scale }
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
