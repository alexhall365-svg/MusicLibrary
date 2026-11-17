import SwiftUI
import SwiftData
import UniformTypeIdentifiers

enum LibraryScope: Hashable {
    case all, recent, needsDetails
    case facet(Facet)

    var title: String {
        switch self {
        case .all: return "All Scores"
        case .recent: return "Recently Opened"
        case .needsDetails: return "Needs Details"
        case .facet(let facet): return facet.value
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
    @State private var showingPaywall = false
    /// Scores waiting for the user to confirm deletion.
    @State private var pendingDeletion: [Score] = []
    @State private var isSelecting = false
    @State private var selection: Set<UUID> = []

    private var sort: ScoreSort {
        scope == .recent ? .recentlyOpened : (ScoreSort(rawValue: sortRaw) ?? .title)
    }

    private var scores: [Score] {
        var base = allScores
        var facet: Facet?
        switch scope {
        case .all: break
        case .recent: base = base.filter { $0.lastOpened != nil }
        case .needsDetails: base = base.filter(\.needsAttention)
        case .facet(let value): facet = value
        }
        return LibraryFilter.apply(base, search: searchText, facet: facet, sort: sort)
    }

    var body: some View {
        let visible = scores
        Group {
            if allScores.isEmpty {
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
        .navigationTitle(isSelecting ? selectionTitle : scope.title)
        .navigationBarTitleDisplayMode(isSelecting ? .inline : .automatic)
        .searchable(text: $searchText, prompt: "Title, composer, catalogue…")
        .toolbar {
            if isSelecting {
                ToolbarItem(placement: .cancellationAction) {
                    let allSelected = !visible.isEmpty && visible.allSatisfy { selection.contains($0.id) }
                    Button(allSelected ? "Deselect All" : "Select All") {
                        selection = allSelected ? [] : Set(visible.map(\.id))
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { endSelecting() }
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    addToSetlistMenu(for: selectedScores(in: visible))
                        .disabled(selection.isEmpty)
                    Spacer()
                    Button(role: .destructive) {
                        pendingDeletion = selectedScores(in: visible)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .disabled(selection.isEmpty)
                }
            } else {
                ToolbarItemGroup(placement: .primaryAction) {
                    if scope != .recent { sortMenu }
                    Button {
                        layoutRaw = layoutRaw == "list" ? "grid" : "list"
                    } label: {
                        Label(
                            layoutRaw == "list" ? "Show as Grid" : "Show as List",
                            systemImage: layoutRaw == "list" ? "square.grid.2x2" : "list.bullet")
                    }
                    if !visible.isEmpty {
                        Button {
                            isSelecting = true
                        } label: {
                            Label("Select", systemImage: "checkmark.circle")
                        }
                    }
                    ImportMenu()
                }
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
        .deleteConfirmation(for: $pendingDeletion) { scores in
            LibraryActions.delete(scores, context: modelContext)
            selection.subtract(scores.map(\.id))
            if isSelecting && selection.isEmpty { endSelecting() }
        }
        .onChange(of: scope) { _, _ in endSelecting() }
        .task {
            if UserDefaults.standard.bool(forKey: "demoLibrary") {
                let demo = UserDefaults.standard.string(forKey: "demoScreen")
                if demo == "select" || demo == "delete" {
                    isSelecting = true
                    selection = Set(visible.prefix(3).map(\.id))
                    if demo == "delete" { pendingDeletion = selectedScores(in: visible) }
                }
            }
        }
    }

    // MARK: Selection

    private var selectionTitle: String {
        selection.isEmpty ? "Select Scores" : "\(selection.count) Selected"
    }

    private func selectedScores(in visible: [Score]) -> [Score] {
        visible.filter { selection.contains($0.id) }
    }

    private func endSelecting() {
        isSelecting = false
        selection = []
    }

    private func toggleSelection(_ score: Score) {
        if selection.contains(score.id) {
            selection.remove(score.id)
        } else {
            selection.insert(score.id)
        }
    }

    private func tapped(_ score: Score) {
        if isSelecting {
            toggleSelection(score)
        } else {
            open(score)
        }
    }

    private func addToSetlistMenu(for scores: [Score]) -> some View {
        Menu {
            ForEach(setlists) { setlist in
                Button(setlist.name) {
                    LibraryActions.add(scores, to: setlist, context: modelContext)
                    if isSelecting { endSelecting() }
                }
            }
            Button("New Setlist", systemImage: "plus") {
                let name = scores.count == 1 ? scores[0].displayTitle : "New Setlist"
                let setlist = LibraryActions.createSetlist(named: name, context: modelContext)
                LibraryActions.add(scores, to: setlist, context: modelContext)
                if isSelecting { endSelecting() }
            }
        } label: {
            Label("Add to Setlist", systemImage: "text.badge.plus")
        }
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
                    Button { tapped(score) } label: {
                        ScoreGridItem(score: score)
                            .overlay(alignment: .topLeading) {
                                if isSelecting { SelectionMark(isSelected: selection.contains(score.id)).padding(6) }
                            }
                            .opacity(isSelecting && !selection.contains(score.id) ? 0.75 : 1)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelecting && selection.contains(score.id) ? .isSelected : [])
                    .contextMenu { if !isSelecting { menu(for: score) } }
                }
            }
            .padding()
        }
    }

    private func list(_ scores: [Score]) -> some View {
        List(scores) { score in
            Button { tapped(score) } label: {
                HStack(spacing: 12) {
                    if isSelecting { SelectionMark(isSelected: selection.contains(score.id)) }
                    ScoreListRow(score: score)
                }
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelecting && selection.contains(score.id) ? .isSelected : [])
            .contextMenu { if !isSelecting { menu(for: score) } }
            .swipeActions {
                if !isSelecting {
                    Button("Delete", systemImage: "trash", role: .destructive) { pendingDeletion = [score] }
                    Button("Details", systemImage: "info.circle") { appState.editingScore = score }
                }
            }
        }
        .listStyle(.plain)
    }

    @ViewBuilder
    private func menu(for score: Score) -> some View {
        Button("Open", systemImage: "book") { open(score) }
        Button("Edit Details", systemImage: "info.circle") { appState.editingScore = score }
        if AppleIntelligence.status.isAvailable {
            Button("Relabel with Apple Intelligence", systemImage: "sparkles") {
                if appState.pro.isPro {
                    appState.autoLabeler.start([score.id], mode: .review, context: modelContext, appState: appState)
                } else {
                    showingPaywall = true
                }
            }
            .disabled(appState.autoLabeler.isRunning)
        }
        addToSetlistMenu(for: [score])
        Button("Select", systemImage: "checkmark.circle") {
            isSelecting = true
            selection = [score.id]
        }
        Divider()
        Button("Delete", systemImage: "trash", role: .destructive) { pendingDeletion = [score] }
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

/// The tick circle shown on scores while selecting.
struct SelectionMark: View {
    let isSelected: Bool

    var body: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.title2)
            .symbolRenderingMode(.palette)
            .foregroundStyle(isSelected ? Color.white : Color.secondary, isSelected ? Color.accentColor : Color.clear)
            .background(Circle().fill(.background.opacity(isSelected ? 0 : 0.8)))
            .accessibilityHidden(true)
    }
}
