import SwiftUI
import SwiftData
import UniformTypeIdentifiers

enum LibraryScope: Hashable {
    case all, recent, needsDetails
    case facet(Facet)
    /// A Choir Library's music.
    case library(String)

    var title: String {
        switch self {
        case .all: return "All Scores"
        case .recent: return "Recently Opened"
        case .needsDetails: return "Needs Details"
        case .facet(let facet): return facet.value
        case .library: return "Choir Music"
        }
    }
}

/// A searchable, sortable grid or list of scores.
struct ScoreCollectionView: View {
    let scope: LibraryScope

    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Query(sort: \Score.dateAdded, order: .reverse) private var allScores: [Score]
    @Query(sort: \Setlist.name) private var setlists: [Setlist]
    @AppStorage("library.sort") private var sortRaw = ScoreSort.title.rawValue
    @AppStorage("library.layout") private var layoutRaw = "grid"
    @State private var searchText = ""
    @State private var isDropTargeted = false
    @State private var scoreToDelete: Score?
    @State private var showingPaywall = false
    @State private var scoreToRemoveFromChoir: Score?
    @Environment(CloudSync.self) private var sync

    private var sort: ScoreSort {
        scope == .recent ? .recentlyOpened : (ScoreSort(rawValue: sortRaw) ?? .title)
    }

    private var scores: [Score] {
        var base = allScores
        var facet: Facet?
        switch scope {
        case .all: base = base.filter(\.isPersonal)
        case .recent: base = base.filter { $0.lastOpened != nil }
        case .needsDetails: base = base.filter { $0.needsAttention && sync.canEdit($0) }
        case .facet(let value): facet = value
        case .library(let key): base = base.filter { $0.cloudLibrary == key }
        }
        return LibraryFilter.apply(base, search: searchText, facet: facet, sort: sort)
    }

    var body: some View {
        let visible = scores
        Group {
            if case .library = scope, visible.isEmpty, searchText.isEmpty {
                emptyChoir
            } else if allScores.isEmpty {
                emptyLibrary
            } else if visible.isEmpty {
                if searchText.isEmpty {
                    ContentUnavailableView(emptyTitle, systemImage: "music.note")
                } else {
                    ContentUnavailableView.search(text: searchText)
                }
            } else if layoutRaw == "list" {
                list(visible)
            } else {
                grid(visible)
            }
        }
        .navigationTitle(title)
        .searchable(text: $searchText, prompt: "Title, composer, catalogue…")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if scope != .recent { sortMenu }
                Button {
                    layoutRaw = layoutRaw == "list" ? "grid" : "list"
                } label: {
                    Label(
                        layoutRaw == "list" ? "Show as Grid" : "Show as List",
                        systemImage: layoutRaw == "list" ? "square.grid.2x2" : "list.bullet")
                }
                if canImportHere { ImportMenu() }
            }
        }
        .onDrop(of: [.pdf], isTargeted: $isDropTargeted) { providers in
            DropImporter.importPDFs(from: providers, coordinator: coordinator)
            return true
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.accentColor, lineWidth: 3)
                    .padding(8)
                    .allowsHitTesting(false)
            }
        }
        .sheet(isPresented: $showingPaywall) { PaywallView() }
        .confirmationDialog(
            "Delete \"\(scoreToDelete?.displayTitle ?? "")\"?",
            isPresented: Binding(get: { scoreToDelete != nil }, set: { if !$0 { scoreToDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete Score", role: .destructive) {
                if let score = scoreToDelete { LibraryActions.delete(score, context: modelContext) }
                scoreToDelete = nil
            }
        } message: {
            if scoreToDelete?.cloudLibrary != nil {
                Text("This removes the score from the Choir Library and from every member's devices.")
            } else {
                Text("This removes the PDF, its annotations and its place in any setlists.")
            }
        }
        .confirmationDialog(
            "Remove \"\(scoreToRemoveFromChoir?.displayTitle ?? "")\" from the choir?",
            isPresented: Binding(get: { scoreToRemoveFromChoir != nil }, set: { if !$0 { scoreToRemoveFromChoir = nil } }),
            titleVisibility: .visible
        ) {
            if let score = scoreToRemoveFromChoir, CloudLibrary.isHosted(score.cloudLibrary) {
                Button("Remove, Keep in My Library") {
                    LibraryActions.removeFromChoir(score, keepCopy: true, context: modelContext)
                    scoreToRemoveFromChoir = nil
                }
            }
            Button("Remove from Choir", role: .destructive) {
                if let score = scoreToRemoveFromChoir {
                    LibraryActions.removeFromChoir(score, keepCopy: false, context: modelContext)
                }
                scoreToRemoveFromChoir = nil
            }
        } message: {
            Text("It's removed from every member's devices, with their annotations on it.")
        }
    }

    /// Imports always go into your own library, so Import isn't offered in a choir.
    private var canImportHere: Bool {
        if case .library = scope { return false }
        return true
    }

    private var emptyChoir: some View {
        ContentUnavailableView {
            Label("No choir music yet", systemImage: "person.3")
        } description: {
            if case .library(let key) = scope, sync.canEdit(key) {
                Text("Add scores from your library with \"Add to Choir Library\" (touch and hold a score), or add them to a choir list.")
            } else {
                Text("Music the choir shares appears here and stays on this device for rehearsal.")
            }
        }
    }

    private var title: String {
        if case .library(let key) = scope, let choir = sync.choir(key) { return choir.name }
        return scope.title
    }

    private var coordinator: ImportCoordinator {
        ImportCoordinator(context: modelContext, appState: appState)
    }

    private var emptyTitle: String {
        switch scope {
        case .needsDetails: return "Every score has its details"
        case .recent: return "Nothing opened yet"
        default: return "No scores here"
        }
    }

    private var emptyLibrary: some View {
        ContentUnavailableView {
            Label("Your library is empty", systemImage: "music.note.list")
        } description: {
            Text("Import PDFs from Files, share them to \(AppConfig.displayName) from another app, or drag them here.")
        } actions: {
            ImportMenu()
                .buttonStyle(.borderedProminent)
        }
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort By", selection: $sortRaw) {
                ForEach(ScoreSort.allCases.filter { $0 != .recentlyOpened }) { option in
                    Text(option.label).tag(option.rawValue)
                }
            }
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down")
        }
    }

    private func grid(_ scores: [Score]) -> some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: sizeClass == .compact ? 140 : 170), spacing: 20)],
                alignment: .leading,
                spacing: 28
            ) {
                ForEach(scores) { score in
                    Button { open(score) } label: {
                        ScoreGridItem(score: score)
                    }
                    .buttonStyle(.plain)
                    .contextMenu { menu(for: score) }
                }
            }
            .padding()
        }
    }

    private func list(_ scores: [Score]) -> some View {
        List(scores) { score in
            Button { open(score) } label: {
                ScoreListRow(score: score)
            }
            .buttonStyle(.plain)
            .contextMenu { menu(for: score) }
            .swipeActions {
                if sync.canEdit(score) {
                    if score.isPersonal {
                        Button("Delete", systemImage: "trash", role: .destructive) { scoreToDelete = score }
                    }
                    Button("Details", systemImage: "info.circle") { appState.editingScore = score }
                }
            }
        }
        .listStyle(.plain)
    }

    @ViewBuilder
    private func menu(for score: Score) -> some View {
        let canEdit = sync.canEdit(score)
        Button("Open", systemImage: "book") { open(score) }
        if canEdit {
            Button("Edit Details", systemImage: "info.circle") { appState.editingScore = score }
        }
        if canEdit && AppleIntelligence.status.isAvailable {
            Button("Relabel with Apple Intelligence", systemImage: "sparkles") {
                if appState.pro.isPro {
                    appState.autoLabeler.start([score.id], mode: .review, context: modelContext, appState: appState)
                } else {
                    showingPaywall = true
                }
            }
            .disabled(appState.autoLabeler.isRunning)
        }
        Menu {
            ForEach(setlists.filter { $0.cloudLibrary == nil }) { setlist in
                Button(setlist.name) {
                    LibraryActions.add([score], to: setlist, context: modelContext)
                }
            }
            ForEach(choirLists(for: score)) { setlist in
                Button("\(setlist.name) (\(sync.choir(setlist.cloudLibrary)?.name ?? "Choir"))") {
                    LibraryActions.add([score], to: setlist, context: modelContext)
                }
            }
            Button("New Setlist", systemImage: "plus") {
                let setlist = LibraryActions.createSetlist(named: score.displayTitle, context: modelContext)
                LibraryActions.add([score], to: setlist, context: modelContext)
            }
        } label: {
            Label("Add to Setlist", systemImage: "text.badge.plus")
        }
        if score.isPersonal {
            ForEach(sync.editableChoirs) { choir in
                Button("Add to \(choir.name)", systemImage: "person.3") {
                    LibraryActions.moveToChoir([score], library: choir.id, context: modelContext)
                }
            }
        } else if canEdit {
            Button("Remove from Choir…", systemImage: "person.badge.minus") { scoreToRemoveFromChoir = score }
        }
        if canEdit && score.isPersonal {
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive) { scoreToDelete = score }
        }
    }

    /// Choir lists this score can go in: lists in its own choir, or (for your
    /// own scores) lists in a choir you can edit, which moves it into that choir.
    private func choirLists(for score: Score) -> [Setlist] {
        setlists.filter { list in
            guard let library = list.cloudLibrary, sync.canEdit(library) else { return false }
            return score.isPersonal || score.cloudLibrary == library
        }
    }

    private func open(_ score: Score) {
        appState.readerRequest = ReaderRequest(scores: [score], startIndex: 0)
    }
}

struct ScoreGridItem: View {
    let score: Score

    var body: some View {
        // Every card has the same layout (two title lines, composer, catalogue
        // line) so thumbnails line up whatever details a score has.
        VStack(alignment: .leading, spacing: 6) {
            Color.white
                .aspectRatio(3.0 / 4.0, contentMode: .fit)
                .overlay {
                    ScoreThumbnailView(scoreID: score.id, fileURL: score.fileURL)
                }
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
                .overlay(alignment: .topTrailing) {
                    if score.labelStatus == .autoUncertain {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.title3)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .orange)
                            .padding(6)
                            .accessibilityLabel("Check details")
                    }
                }

            Text(score.displayTitle)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.leading)
            Text(score.composer.isEmpty ? "Unknown composer" : score.composer)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(score.catalogueNumber.isEmpty ? " " : score.catalogueNumber)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the score")
    }
}

struct ScoreListRow: View {
    let score: Score
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        HStack(spacing: 12) {
            Color.white
                .frame(width: 42, height: 56)
                .overlay { ScoreThumbnailView(scoreID: score.id, fileURL: score.fileURL) }
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(score.displayTitle)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(score.subtitle.isEmpty ? "Unknown composer" : score.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if !score.scoring.isEmpty && sizeClass != .compact {
                Text(score.scoring)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

struct ScoreThumbnailView: View {
    let scoreID: UUID
    let fileURL: URL
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "music.note")
                    .font(.title)
                    .foregroundStyle(.gray.opacity(0.5))
            }
        }
        .accessibilityHidden(true)
        .task(id: scoreID) {
            image = ThumbnailCache.shared.cachedImage(for: scoreID)
            if image == nil {
                image = await ThumbnailCache.shared.thumbnail(for: scoreID, pdfURL: fileURL)
            }
        }
    }
}
