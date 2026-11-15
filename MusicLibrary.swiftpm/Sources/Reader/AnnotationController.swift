import SwiftUI
import PencilKit
import Observation

enum AnnotationTool: String, CaseIterable, Identifiable {
    case pen, highlighter, eraser

    var id: String { rawValue }

    var label: String {
        switch self {
        case .pen: return "Pen"
        case .highlighter: return "Highlighter"
        case .eraser: return "Eraser"
        }
    }

    var systemImage: String {
        switch self {
        case .pen: return "pencil.tip"
        case .highlighter: return "highlighter"
        case .eraser: return "eraser"
        }
    }
}

enum InkColor: String, CaseIterable, Identifiable {
    case black, red, blue, green, yellow, pink, mint

    var id: String { rawValue }

    static let penColors: [InkColor] = [.black, .red, .blue, .green]
    static let highlighterColors: [InkColor] = [.yellow, .pink, .mint]

    var uiColor: UIColor {
        switch self {
        case .black: return .black
        case .red: return UIColor(red: 0.80, green: 0.10, blue: 0.10, alpha: 1)
        case .blue: return UIColor(red: 0.10, green: 0.30, blue: 0.85, alpha: 1)
        case .green: return UIColor(red: 0.10, green: 0.55, blue: 0.25, alpha: 1)
        case .yellow: return UIColor(red: 1.00, green: 0.85, blue: 0.10, alpha: 1)
        case .pink: return UIColor(red: 1.00, green: 0.45, blue: 0.70, alpha: 1)
        case .mint: return UIColor(red: 0.40, green: 0.90, blue: 0.60, alpha: 1)
        }
    }

    var color: Color { Color(uiColor: uiColor) }

    var label: String { rawValue.capitalized }
}

/// The current annotation tool, shared by the toolbar and the page views.
@Observable
final class AnnotationController {
    var tool: AnnotationTool = .pen
    var penColor: InkColor = .black
    var highlighterColor: InkColor = .yellow
    /// When off, the system setting decides (usually Apple Pencil only on iPad).
    var fingerDrawing = false

    /// The canvas used most recently, for undo and redo.
    @ObservationIgnored weak var activeCanvas: PKCanvasView?

    var pkTool: PKTool {
        switch tool {
        case .pen:
            return PKInkingTool(.pen, color: penColor.uiColor, width: 2.5)
        case .highlighter:
            return PKInkingTool(.marker, color: highlighterColor.uiColor, width: 18)
        case .eraser:
            return PKEraserTool(.vector)
        }
    }

    /// Changes whenever anything affecting the page views changes.
    var configurationKey: String {
        "\(tool.rawValue)-\(penColor.rawValue)-\(highlighterColor.rawValue)-\(fingerDrawing)"
    }

    func undo() { activeCanvas?.undoManager?.undo() }
    func redo() { activeCanvas?.undoManager?.redo() }
}
