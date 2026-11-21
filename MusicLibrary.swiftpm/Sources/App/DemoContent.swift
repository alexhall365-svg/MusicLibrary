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
        CloudSync.shared.demoMode = true
        let existing = (try? context.fetch(FetchDescriptor<Score>())) ?? []
        let scores = existing.isEmpty ? seed(context: context) : existing
        let setlist = fullestSetlist(context: context)

        switch defaults.string(forKey: "demoScreen") {
        case "reader":
            if let setlist {
                appState.readerRequest = ReaderRequest(scores: setlist.orderedScores, startIndex: 1)
            }
        case "editor":
            appState.editingScore = scores.first { $0.labelStatus == .autoUncertain } ?? scores.first
        case "aireview":
            presentDemoReview(scores: scores, context: context, appState: appState)
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
            return fullestSetlist(context: context).map { .setlist($0.id) }
        case "group":
            let lists = (try? context.fetch(FetchDescriptor<Setlist>())) ?? []
            if let list = lists.first(where: { $0.cloudLibrary == demoGroupKey }) { return .setlist(list.id) }
            return .choir(demoGroupKey)
        case "groupmusic":
            return .choir(demoGroupKey)
        case "labelling":
            return .labelling
        case "duplicates":
            return .duplicates
        default:
            return nil
        }
    }

    private static func fullestSetlist(context: ModelContext) -> Setlist? {
        let setlists = ((try? context.fetch(FetchDescriptor<Setlist>())) ?? []).filter { $0.cloudLibrary == nil }
        return setlists.max { ($0.entries?.count ?? 0) < ($1.entries?.count ?? 0) }
    }

    /// The Apple Intelligence review screen, as it looks after labelling an
    /// untitled scan. The simulators used for screenshots have no Apple
    /// Intelligence, so the suggestions are the ones it gives for these scores.
    private static func presentDemoReview(scores: [Score], context: ModelContext, appState: AppState) {
        var entries: [ExchangeEntry] = []
        if let scan = scores.first(where: { $0.originalFileName == "Scan 0042.pdf" }) {
            var metadata = scan.metadata
            metadata.title = "Ode to Joy"
            metadata.composer = "Beethoven, Ludwig van"
            metadata.catalogueNumber = "Op. 125"
            metadata.scoring = "Melody"
            metadata.key = "D major"
            metadata.genre = "Hymn"
            entries.append(ExchangeEntry(
                id: scan.id.uuidString, file: scan.originalFileName, sha256: scan.contentHash,
                metadata: ExchangeMetadata(metadata),
                confidence: ["title": 0.96, "composer": 0.94, "catalogueNumber": 0.82, "key": 0.9, "genre": 0.66]))
        }
        if let psalm = scores.first(where: { $0.title == "Psalm 23" }) {
            var metadata = psalm.metadata
            metadata.key = "A-flat major"
            metadata.tags = metadata.tags + ["Psalm"]
            entries.append(ExchangeEntry(
                id: psalm.id.uuidString, file: psalm.originalFileName, sha256: psalm.contentHash,
                metadata: ExchangeMetadata(metadata),
                confidence: ["key": 0.62],
                flags: ["Key read from the first page only"]))
        }
        guard !entries.isEmpty else { return }
        ImportCoordinator(context: context, appState: appState).presentReview(
            of: MetadataExchangeFile(scores: entries, exportedAt: nil),
            title: "Apple Intelligence", emptyMessage: nil)
    }

    // MARK: - Real music (for App Store screenshots)

    /// Real public-domain scores put in place by the Screenshots workflow:
    /// `DemoScores/manifest.json` plus the PDFs, under the library folder.
    private struct Manifest: Decodable {
        struct Entry: Decodable {
            var path: String
            var title: String
            var composer: String
            var catalogue: String
            var scoring: String
            var key: String
            var genre: String
            var tags: [String]
            var recent: Bool?
            var uncertain: Bool?
            var annotate: Bool?
            var fileName: String?
        }
        struct List: Decodable {
            var name: String
            var scores: [Int]
        }
        struct Group: Decodable {
            var name: String
            var scores: [Int]
            var list: List?
            var members: Int?
        }
        var scores: [Entry]
        var setlists: [List]
        var group: Group?
    }

    /// The sample group's library key (a group "hosted" by the demo user).
    static let demoGroupKey = CloudLibrary.hostedKey(zoneName: CloudLibrary.hostedZonePrefix + "DEMO")

    private static func seedRealMusic(context: ModelContext) -> [Score]? {
        let paths = LibraryPaths.shared
        let folder = paths.root.appendingPathComponent("DemoScores", isDirectory: true)
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("manifest.json")),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data) else { return nil }
        try? paths.ensureDirectories()
        var created: [Score] = []
        var annotated: Score?
        for (index, entry) in manifest.scores.enumerated() {
            let source = folder.appendingPathComponent((entry.path as NSString).lastPathComponent)
            let id = UUID()
            let storedName = "\(id.uuidString).pdf"
            let url = paths.scoreFileURL(storedFileName: storedName)
            guard (try? FileManager.default.copyItem(at: source, to: url)) != nil,
                  let pdf = CGPDFDocument(url as CFURL) else { continue }
            let metadata = ScoreMetadata(
                title: entry.title, composer: entry.composer, catalogueNumber: entry.catalogue,
                scoring: entry.scoring, key: entry.key, genre: entry.genre, tags: entry.tags)
            let score = Score(
                id: id, storedFileName: storedName,
                originalFileName: entry.fileName ?? "\(entry.title).pdf",
                contentHash: (try? FileHasher.sha256(of: url)) ?? UUID().uuidString,
                pageCount: pdf.numberOfPages, metadata: metadata)
            score.dateAdded = Date().addingTimeInterval(Double(-index) * 86_400)
            if entry.uncertain == true { score.labelStatus = .autoUncertain }
            if entry.recent == true { score.lastOpened = Date().addingTimeInterval(Double(-index) * 3_600) }
            context.insert(score)
            created.append(score)
            if entry.annotate == true { annotated = score }
        }
        guard !created.isEmpty else { return nil }
        for list in manifest.setlists {
            let setlist = Setlist(name: list.name)
            context.insert(setlist)
            for (position, index) in list.scores.enumerated() where created.indices.contains(index) {
                let entry = SetlistEntry(position: position)
                context.insert(entry)
                entry.score = created[index]
                entry.setlist = setlist
            }
        }
        if let group = manifest.group {
            for index in group.scores where created.indices.contains(index) {
                created[index].cloudLibrary = demoGroupKey
            }
            if let list = group.list {
                let setlist = Setlist(name: list.name, cloudLibrary: demoGroupKey)
                context.insert(setlist)
                for (position, index) in list.scores.enumerated() where created.indices.contains(index) {
                    let entry = SetlistEntry(position: position)
                    context.insert(entry)
                    entry.score = created[index]
                    entry.setlist = setlist
                }
            }
            CloudSync.shared.upsertChoir(ChoirInfo(
                id: demoGroupKey, name: group.name, isOwner: true, canEdit: true,
                ownerName: nil, memberCount: group.members ?? 0))
        }
        try? context.save()
        if let annotated { addMusicianMarkings(to: annotated) }
        return created
    }

    private static func seed(context: ModelContext) -> [Score] {
        if let real = seedRealMusic(context: context) { return real }
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

    /// Markings a singer or director might make, placed on the first page of
    /// "Es ist ein Ros' entsprungen" (A4, points from the top-left).
    private static func addMusicianMarkings(to score: Score) {
        func stroke(_ points: [CGPoint], color: UIColor, width: CGFloat, ink: PKInk.InkType = .pen) -> PKStroke {
            let controlPoints = points.enumerated().map { index, point in
                PKStrokePoint(location: point, timeOffset: Double(index) * 0.01, size: CGSize(width: width, height: width),
                              opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
            }
            return PKStroke(ink: PKInk(ink, color: color), path: PKStrokePath(controlPoints: controlPoints, creationDate: Date()))
        }
        func breath(at x: CGFloat, _ y: CGFloat) -> PKStroke {
            // A comma-shaped breath mark above the staff.
            stroke([CGPoint(x: x, y: y - 3), CGPoint(x: x + 3.5, y: y), CGPoint(x: x + 4.5, y: y + 5),
                    CGPoint(x: x + 2.5, y: y + 10.5), CGPoint(x: x - 2, y: y + 14)],
                   color: UIColor(red: 0.80, green: 0.10, blue: 0.12, alpha: 1), width: 2.8)
        }
        let red = UIColor(red: 0.80, green: 0.10, blue: 0.12, alpha: 1)
        let blue = UIColor(red: 0.10, green: 0.30, blue: 0.80, alpha: 1)
        var strokes: [PKStroke] = []
        strokes.append(breath(at: 516, 120))   // after "zart," (soprano)
        strokes.append(breath(at: 420, 494))   // after "Art" (second system)
        // Crescendo hairpin above the soprano line.
        strokes.append(stroke([CGPoint(x: 300, y: 127), CGPoint(x: 340, y: 124), CGPoint(x: 382, y: 120.5)], color: blue, width: 1.8))
        strokes.append(stroke([CGPoint(x: 300, y: 127), CGPoint(x: 340, y: 130), CGPoint(x: 382, y: 133.5)], color: blue, width: 1.8))
        // Circle round the alto's dotted rhythm.
        var circle: [CGPoint] = []
        for step in 0...32 {
            let angle = Double(step) / 32 * 2.1 * .pi - 0.3
            circle.append(CGPoint(x: 432 + 34 * cos(angle), y: 226 + 17 * sin(angle)))
        }
        strokes.append(stroke(circle, color: red, width: 2))
        // "Watch" arrow pointing at it.
        strokes.append(stroke([CGPoint(x: 492, y: 252), CGPoint(x: 476, y: 243), CGPoint(x: 466, y: 236)], color: red, width: 2))
        strokes.append(stroke([CGPoint(x: 466, y: 236), CGPoint(x: 473, y: 236.5)], color: red, width: 2))
        strokes.append(stroke([CGPoint(x: 466, y: 236), CGPoint(x: 469, y: 242)], color: red, width: 2))
        // Highlight a phrase of the text.
        strokes.append(stroke([CGPoint(x: 226, y: 545), CGPoint(x: 340, y: 545)], color: .systemYellow, width: 14, ink: .marker))
        AnnotationStore().save(PKDrawing(strokes: strokes), scoreID: score.id, page: 0)
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
