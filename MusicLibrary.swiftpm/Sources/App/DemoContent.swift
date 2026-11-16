import Foundation
import PencilKit
import SwiftData
import UIKit

/// Sample library for screenshots and testing. Only used when the app is
/// launched with `-demoLibrary YES` (and optionally `-demoScreen <name>`), which
/// normal users never do.
@MainActor
enum DemoContent {
    private static let pieces: [(title: String, composer: String, catalogue: String, scoring: String, key: String, genre: String, tags: [String], pages: Int)] = [
        ("Hear my prayer, O Lord", "Purcell, Henry", "Z. 15", "SSATB", "C minor", "Anthem", ["Lent"], 3),
        ("Magnificat and Nunc dimittis in G", "Stanford, Charles Villiers", "Op. 81", "SATB + organ", "G major", "Canticle", ["Evensong"], 6),
        ("Ave verum corpus", "Mozart, Wolfgang Amadeus", "K. 618", "SATB + organ", "D major", "Motet", ["Communion", "Latin"], 2),
        ("If ye love me", "Tallis, Thomas", "", "SATB", "F major", "Anthem", ["Pentecost"], 2),
        ("Jesu, meine Freude", "Bach, Johann Sebastian", "BWV 227", "SSATB", "E minor", "Motet", ["German"], 8),
        ("Locus iste", "Bruckner, Anton", "WAB 23", "SATB", "C major", "Motet", ["Dedication", "Latin"], 2),
        ("O come, O come, Emmanuel", "Traditional", "", "SATB + organ", "E minor", "Hymn", ["Advent"], 2),
        ("The Lord is my shepherd", "Goodall, Howard", "", "SATB + piano", "D major", "Anthem", ["Psalm"], 4),
        ("Preces and Responses", "Smith, William", "", "SATB", "", "Responses", ["Evensong"], 4),
        ("Lo, he comes with clouds descending", "Traditional", "", "SATB + organ", "G major", "Hymn", ["Advent"], 2),
        ("This is the record of John", "Gibbons, Orlando", "", "SATB + organ", "", "Anthem", ["Advent"], 5),
        ("Scan 0042", "", "", "", "", "", [], 3),
    ]

    static func prepareIfRequested(context: ModelContext, appState: AppState) {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: "demoLibrary") else { return }
        let existing = (try? context.fetch(FetchDescriptor<Score>())) ?? []
        let scores = existing.isEmpty ? seed(context: context) : existing
        let setlists = (try? context.fetch(FetchDescriptor<Setlist>())) ?? []

        switch defaults.string(forKey: "demoScreen") {
        case "reader":
            if let setlist = setlists.first {
                appState.readerRequest = ReaderRequest(scores: setlist.orderedScores, startIndex: 1)
            }
        case "editor":
            appState.editingScore = scores.first { $0.labelStatus == .autoUncertain } ?? scores.first
        case "paywall", "setlist", "labelling", "duplicates":
            // Handled by RootView (sidebar selection / sheets).
            break
        default:
            break
        }
    }

    /// The sidebar item to open, for `-demoScreen setlist|labelling|duplicates`.
    static func requestedSidebarItem(context: ModelContext) -> SidebarItem? {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: "demoLibrary") else { return nil }
        switch defaults.string(forKey: "demoScreen") {
        case "setlist":
            let setlists = (try? context.fetch(FetchDescriptor<Setlist>())) ?? []
            return setlists.first.map { .setlist($0.id) }
        case "labelling":
            return .labelling
        case "duplicates":
            return .duplicates
        default:
            return nil
        }
    }

    private static func seed(context: ModelContext) -> [Score] {
        let paths = LibraryPaths.shared
        try? paths.ensureDirectories()
        var created: [Score] = []
        for (index, piece) in pieces.enumerated() {
            let id = UUID()
            let storedName = "\(id.uuidString).pdf"
            let url = paths.scoreFileURL(storedFileName: storedName)
            writePDF(to: url, title: piece.title, composer: piece.composer, scoring: piece.scoring,
                     pages: piece.pages, seed: index)
            let metadata = ScoreMetadata(
                title: piece.title == "Scan 0042" ? "" : piece.title,
                composer: piece.composer, catalogueNumber: piece.catalogue, scoring: piece.scoring,
                key: piece.key, genre: piece.genre, tags: piece.tags)
            let score = Score(
                id: id, storedFileName: storedName,
                originalFileName: piece.title == "Scan 0042" ? "Scan 0042.pdf" : "\(piece.title).pdf",
                contentHash: (try? FileHasher.sha256(of: url)) ?? UUID().uuidString,
                pageCount: piece.pages, metadata: metadata)
            score.dateAdded = Date().addingTimeInterval(Double(-index) * 86_400)
            if index == 7 { score.labelStatus = .autoUncertain }
            if index < 4 { score.lastOpened = Date().addingTimeInterval(Double(-index) * 3_600) }
            context.insert(score)
            created.append(score)
        }

        let setlist = Setlist(name: "Evensong – Advent Sunday")
        context.insert(setlist)
        for (position, index) in [8, 6, 1, 10, 9].enumerated() {
            let entry = SetlistEntry(position: position)
            context.insert(entry)
            entry.score = created[index]
            entry.setlist = setlist
        }
        let second = Setlist(name: "Choral Eucharist – Christmas Day")
        context.insert(second)
        try? context.save()

        addAnnotations(to: created[1])
        return created
    }

    // MARK: - Drawing

    private static func writePDF(to url: URL, title: String, composer: String, scoring: String, pages: Int, seed: Int) {
        let bounds = CGRect(x: 0, y: 0, width: 595, height: 842)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)
        try? renderer.writePDF(to: url) { context in
            var random = SeededRandom(seed: UInt64(seed + 1))
            for page in 0..<pages {
                context.beginPage()
                var top: CGFloat = 60
                if page == 0 {
                    draw(title, font: .systemFont(ofSize: 24, weight: .semibold), centeredAt: 70, in: bounds)
                    if !composer.isEmpty {
                        let parts = composer.components(separatedBy: ", ")
                        let name = parts.count == 2 ? "\(parts[1]) \(parts[0])" : composer
                        draw(name, font: .italicSystemFont(ofSize: 13), rightAlignedAt: 110, in: bounds)
                    }
                    if !scoring.isEmpty {
                        (scoring as NSString).draw(at: CGPoint(x: 50, y: 104),
                            withAttributes: [.font: UIFont.systemFont(ofSize: 11), .foregroundColor: UIColor.darkGray])
                    }
                    top = 140
                }
                var y = top
                while y + 120 < bounds.height - 40 {
                    drawSystem(at: y, in: bounds, random: &random)
                    y += 150
                }
                draw("\(page + 1)", font: .systemFont(ofSize: 10), centeredAt: bounds.height - 30, in: bounds)
            }
        }
    }

    private static func drawSystem(at top: CGFloat, in bounds: CGRect, random: inout SeededRandom) {
        let cg = UIGraphicsGetCurrentContext()
        cg?.setStrokeColor(UIColor.black.cgColor)
        cg?.setFillColor(UIColor.black.cgColor)
        let left: CGFloat = 50
        let right = bounds.width - 40
        for staff in 0..<2 {
            let staffTop = top + CGFloat(staff) * 60
            cg?.setLineWidth(0.7)
            for line in 0..<5 {
                let y = staffTop + CGFloat(line) * 6
                cg?.move(to: CGPoint(x: left, y: y))
                cg?.addLine(to: CGPoint(x: right, y: y))
            }
            cg?.strokePath()
            // Bar lines.
            cg?.setLineWidth(1)
            for bar in 0...4 {
                let x = left + (right - left) * CGFloat(bar) / 4
                cg?.move(to: CGPoint(x: x, y: staffTop))
                cg?.addLine(to: CGPoint(x: x, y: staffTop + 24))
            }
            cg?.strokePath()
            // Notes.
            var x = left + 22
            while x < right - 12 {
                let step = CGFloat(random.next(in: 0...8))
                let y = staffTop + 24 - step * 3
                cg?.fillEllipse(in: CGRect(x: x - 4, y: y - 3, width: 8, height: 6))
                cg?.setLineWidth(0.9)
                cg?.move(to: CGPoint(x: x + 3.5, y: y))
                cg?.addLine(to: CGPoint(x: x + 3.5, y: y - 20))
                cg?.strokePath()
                x += CGFloat(random.next(in: 18...30))
            }
        }
        // Brace line joining the staves.
        cg?.setLineWidth(1.5)
        cg?.move(to: CGPoint(x: left, y: top))
        cg?.addLine(to: CGPoint(x: left, y: top + 84))
        cg?.strokePath()
    }

    private static func draw(_ text: String, font: UIFont, centeredAt y: CGFloat, in bounds: CGRect) {
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.black]
        let size = (text as NSString).size(withAttributes: attributes)
        (text as NSString).draw(at: CGPoint(x: (bounds.width - size.width) / 2, y: y), withAttributes: attributes)
    }

    private static func draw(_ text: String, font: UIFont, rightAlignedAt y: CGFloat, in bounds: CGRect) {
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.black]
        let size = (text as NSString).size(withAttributes: attributes)
        (text as NSString).draw(at: CGPoint(x: bounds.width - 40 - size.width, y: y), withAttributes: attributes)
    }

    private static func addAnnotations(to score: Score) {
        func stroke(_ points: [CGPoint], color: UIColor, width: CGFloat, ink: PKInk.InkType = .pen) -> PKStroke {
            let controlPoints = points.enumerated().map { index, point in
                PKStrokePoint(location: point, timeOffset: Double(index) * 0.01, size: CGSize(width: width, height: width),
                              opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
            }
            return PKStroke(ink: PKInk(ink, color: color), path: PKStrokePath(controlPoints: controlPoints, creationDate: Date()))
        }
        // A breath mark, a circled dynamic and a highlighted bar on page 1.
        let breath = stroke([CGPoint(x: 300, y: 150), CGPoint(x: 304, y: 138), CGPoint(x: 309, y: 130)], color: .red, width: 2.5)
        var circle: [CGPoint] = []
        for step in 0...24 {
            let angle = Double(step) / 24 * 2 * .pi
            circle.append(CGPoint(x: 150 + 16 * cos(angle), y: 235 + 11 * sin(angle)))
        }
        let ring = stroke(circle, color: .blue, width: 2)
        let highlight = stroke([CGPoint(x: 290, y: 302), CGPoint(x: 420, y: 302)], color: .systemYellow, width: 18, ink: .marker)
        let mf = stroke([CGPoint(x: 140, y: 240), CGPoint(x: 144, y: 230), CGPoint(x: 148, y: 240), CGPoint(x: 152, y: 230), CGPoint(x: 156, y: 240)], color: .blue, width: 2)
        AnnotationStore().save(PKDrawing(strokes: [breath, ring, mf, highlight]), scoreID: score.id, page: 0)
    }
}

/// Small deterministic random numbers so demo pages look the same every time.
private struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed &* 0x9E3779B97F4A7C15 }

    mutating func next(in range: ClosedRange<Int>) -> Int {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        let span = UInt64(range.upperBound - range.lowerBound + 1)
        return range.lowerBound + Int((state >> 33) % span)
    }
}
