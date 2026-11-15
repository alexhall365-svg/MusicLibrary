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
    @State private var showingAddScores = false

    var body: some View {
        let entries = setlist.orderedEntries
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
            .onMove(perform: move)
            .onDelete(perform: delete)
        }
        .overlay {
            if entries.isEmpty {
                ContentUnavailableView {
                    Label("Empty setlist", systemImage: "list.number")
                } description: {
                    Text("Add the scores you'll need, in performance order.")
                } actions: {
                    Button("Add Scores") { showingAddScores = true }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle(setlist.name)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Play", systemImage: "play.fill") { play(from: 0) }
                    .disabled(entries.isEmpty)
                Button("Add Scores", systemImage: "plus") { showingAddScores = true }
                EditButton()
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

    var body: some View {
        let visible = LibraryFilter.apply(scores, search: searchText, facet: nil, sort: .title)
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
