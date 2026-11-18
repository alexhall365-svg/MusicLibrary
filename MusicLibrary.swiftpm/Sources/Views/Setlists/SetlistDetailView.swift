import SwiftUI
import SwiftData

struct SetlistDetailView: View {
    @Query private var matches: [Setlist]

    init(setlistID: UUID) {
        _matches = Query(filter: #Predicate<Setlist> { $0.id == setlistID })
    }

    var body: some View {
        if let setlist = matches.first {
            SetlistContentView(setlist: setlist)
        } else {
            ContentUnavailableView("Setlist not found", systemImage: "list.number")
        }
    }
}

private struct SetlistContentView: View {
    @Bindable var setlist: Setlist
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Environment(CloudSync.self) private var sync
    @State private var showingAddScores = false

    var body: some View {
        let entries = setlist.orderedEntries
        let canEdit = sync.canEdit(setlist)
        List {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                Button {
                    play(from: index)
                } label: {
                    HStack(spacing: 12) {
                        Text("\(index + 1)")
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 24, alignment: .trailing)
                        if let score = entry.score {
                            ScoreListRow(score: score)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .onMove(perform: canEdit ? move : nil)
            .onDelete(perform: canEdit ? delete : nil)
        }
        .overlay {
            if entries.isEmpty {
                ContentUnavailableView {
                    Label("Empty setlist", systemImage: "list.number")
                } description: {
                    Text(canEdit
                         ? "Add the scores you'll need, in performance order."
                         : "The group hasn't added any music to this list yet.")
                } actions: {
                    if canEdit {
                        Button("Add Scores") { showingAddScores = true }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
        .navigationTitle(setlist.name)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Play", systemImage: "play.fill") { play(from: 0) }
                    .disabled(entries.isEmpty)
                if canEdit {
                    Button("Add Scores", systemImage: "plus") { showingAddScores = true }
                    EditButton()
                }
                if setlist.cloudLibrary != nil {
                    Button("Copy to My Setlists", systemImage: "doc.on.doc") {
                        LibraryActions.copyToMySetlists(setlist, context: modelContext)
                        appState.alert = AppAlert(
                            title: "Copied",
                            message: "\"\(setlist.name)\" is now also in your Setlists, where you can reorder and change it.")
                    }
                }
            }
        }
        .safeAreaInset(edge: .top) {
            if let choir = sync.choir(setlist.cloudLibrary) {
                Label(canEdit
                      ? "Group list in \(choir.name). Changes reach everyone in the group."
                      : "Group list from \(choir.name). View only.",
                      systemImage: "person.3")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.vertical, 6)
                    .background(.bar)
            }
        }
        .sheet(isPresented: $showingAddScores) {
            AddScoresSheet(setlist: setlist)
        }
    }

    private func play(from index: Int) {
        let entries = setlist.orderedEntries.filter { $0.score != nil }
        let scores = entries.compactMap(\.score)
        guard !scores.isEmpty else { return }
        appState.readerRequest = ReaderRequest(scores: scores, startIndex: min(index, scores.count - 1))
    }

    private func move(from source: IndexSet, to destination: Int) {
        var entries = setlist.orderedEntries
        entries.move(fromOffsets: source, toOffset: destination)
        LibraryActions.renumber(entries)
        try? modelContext.save()
    }

    private func delete(at offsets: IndexSet) {
        var entries = setlist.orderedEntries
        let removed = offsets.map { entries[$0] }
        entries.remove(atOffsets: offsets)
        setlist.entries?.removeAll { entry in removed.contains { $0.id == entry.id } }
        removed.forEach { modelContext.delete($0) }
        LibraryActions.renumber(entries)
        try? modelContext.save()
    }
}

/// Pick scores to add to a setlist, in the order you tap them.
struct AddScoresSheet: View {
    let setlist: Setlist
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var scores: [Score]
    @State private var selected: [UUID] = []
    @State private var searchText = ""

    /// A choir list can take that choir's music, or your own (which then joins the choir).
    private var candidates: [Score] {
        guard let library = setlist.cloudLibrary else { return scores }
        return scores.filter { $0.isPersonal || $0.cloudLibrary == library }
    }

    var body: some View {
        let visible = LibraryFilter.apply(candidates, search: searchText, facet: nil, sort: .title)
        NavigationStack {
            List(visible) { score in
                Button {
                    if let index = selected.firstIndex(of: score.id) {
                        selected.remove(at: index)
                    } else {
                        selected.append(score.id)
                    }
                } label: {
                    HStack(spacing: 12) {
                        if let position = selected.firstIndex(of: score.id) {
                            Text("\(position + 1)")
                                .font(.caption.weight(.bold).monospacedDigit())
                                .foregroundStyle(.white)
                                .frame(width: 24, height: 24)
                                .background(Color.accentColor, in: Circle())
                        } else {
                            Image(systemName: "circle")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                                .frame(width: 24, height: 24)
                        }
                        ScoreListRow(score: score)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected.contains(score.id) ? .isSelected : [])
            }
            .listStyle(.plain)
            .searchable(text: $searchText, prompt: "Search scores")
            .safeAreaInset(edge: .bottom) {
                if setlist.cloudLibrary != nil {
                    Text("Your own scores you add here move into the group, so every member gets them.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(.bar)
                }
            }
            .navigationTitle("Add to \(setlist.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(selected.isEmpty ? "Add" : "Add \(selected.count)") {
                        let byID = Dictionary(scores.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                        LibraryActions.add(selected.compactMap { byID[$0] }, to: setlist, context: modelContext)
                        dismiss()
                    }
                    .disabled(selected.isEmpty)
                }
            }
        }
    }
}
