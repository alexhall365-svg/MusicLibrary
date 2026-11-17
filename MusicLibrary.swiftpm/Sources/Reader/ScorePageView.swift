import UIKit
import PencilKit

/// One PDF page with its annotation canvas on top.
final class ScorePageView: UIView, PKCanvasViewDelegate {
    enum Alignment { case center, leading, trailing }

    var alignment: Alignment = .center {
        didSet { if alignment != oldValue { setNeedsLayout() } }
    }
    weak var annotationController: AnnotationController?
    /// How far the reader is zoomed in; images are rendered sharper to match.
    var zoomScale: CGFloat = 1 {
        didSet {
            guard abs(zoomScale - oldValue) > 0.01 else { return }
            setNeedsLayout()
        }
    }

    private let imageView = UIImageView()
    private let canvasView = PKCanvasView()
    private let store = AnnotationStore()

    private var renderer: PageRenderer?
    private(set) var pageIndex = -1
    /// The drawing in PDF page coordinates.
    private var pageDrawing = PKDrawing()
    private var displayScale: CGFloat = 0
    private var isApplyingDrawing = false
    private var saveWorkItem: DispatchWorkItem?
    private var requestedImageKey: String?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear

        imageView.contentMode = .scaleToFill
        imageView.backgroundColor = .white
        addSubview(imageView)

        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false
        canvasView.delegate = self
        canvasView.isScrollEnabled = false
        canvasView.minimumZoomScale = 1
        canvasView.maximumZoomScale = 1
        canvasView.contentInsetAdjustmentBehavior = .never
        canvasView.isUserInteractionEnabled = false
        // Keep ink colours true; PencilKit would otherwise invert them in dark mode.
        canvasView.overrideUserInterfaceStyle = .light
        addSubview(canvasView)

        isAccessibilityElement = true
        accessibilityTraits = .image
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(renderer: PageRenderer, pageIndex: Int) {
        if renderer === self.renderer && pageIndex == self.pageIndex { return }
        flushSave()
        self.renderer = renderer
        self.pageIndex = pageIndex
        imageView.image = nil
        requestedImageKey = nil
        pageDrawing = store.loadDrawing(scoreID: renderer.scoreID, page: pageIndex)
        displayScale = 0
        canvasView.undoManager?.removeAllActions()
        accessibilityLabel = "Page \(pageIndex + 1) of \(renderer.pageCount)"
        setNeedsLayout()
    }

    func setAnnotating(_ annotating: Bool, tool: PKTool, fingerDrawing: Bool) {
        canvasView.isUserInteractionEnabled = annotating
        canvasView.tool = tool
        canvasView.drawingPolicy = fingerDrawing ? .anyInput : .default
    }

    // MARK: Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let renderer, pageIndex >= 0, bounds.width > 0, bounds.height > 0 else { return }
        let pageSize = renderer.pageSize(pageIndex)
        let rect = fittedRect(for: pageSize)
        imageView.frame = rect
        canvasView.frame = rect

        let scale = rect.width / max(pageSize.width, 1)
        if abs(scale - displayScale) > 0.0001 {
            displayScale = scale
            applyDrawing()
        }
        loadImage(width: rect.width)
    }

    private func fittedRect(for pageSize: CGSize) -> CGRect {
        let scale = min(bounds.width / max(pageSize.width, 1), bounds.height / max(pageSize.height, 1))
        let size = CGSize(width: pageSize.width * scale, height: pageSize.height * scale)
        let x: CGFloat
        switch alignment {
        case .center: x = (bounds.width - size.width) / 2
        case .leading: x = 0
        case .trailing: x = bounds.width - size.width
        }
        return CGRect(x: x, y: (bounds.height - size.height) / 2, width: size.width, height: size.height)
    }

    private func loadImage(width: CGFloat) {
        guard let renderer, width > 0 else { return }
        let pixelWidth = PageRenderer.bucket(min(width * traitCollection.displayScale * max(zoomScale, 1), 3072))
        let page = pageIndex
        let key = "\(page)-\(pixelWidth)"
        guard key != requestedImageKey else { return }
        requestedImageKey = key
        if let cached = renderer.cachedImage(page: page, pixelWidth: pixelWidth) {
            imageView.image = cached
            return
        }
        renderer.image(page: page, pixelWidth: pixelWidth) { [weak self] image in
            guard let self, self.pageIndex == page, self.renderer === renderer else { return }
            self.imageView.image = image
        }
    }

    // MARK: Drawing

    private func applyDrawing() {
        guard displayScale > 0 else { return }
        isApplyingDrawing = true
        canvasView.drawing = pageDrawing.transformed(using: CGAffineTransform(scaleX: displayScale, y: displayScale))
        isApplyingDrawing = false
    }

    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        guard !isApplyingDrawing, displayScale > 0 else { return }
        let inverse = 1 / displayScale
        pageDrawing = canvasView.drawing.transformed(using: CGAffineTransform(scaleX: inverse, y: inverse))
        scheduleSave()
    }

    func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
        annotationController?.activeCanvas = canvasView
    }

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: item)
    }

    func flushSave() {
        guard let item = saveWorkItem else { return }
        item.cancel()
        saveWorkItem = nil
        saveNow()
    }

    private func saveNow() {
        saveWorkItem = nil
        guard let renderer, pageIndex >= 0 else { return }
        store.save(pageDrawing, scoreID: renderer.scoreID, page: pageIndex)
    }
}
