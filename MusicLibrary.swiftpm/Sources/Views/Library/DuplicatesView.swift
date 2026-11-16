import SwiftUI
import SwiftData

/// Finds scores that look like duplicates and lets you choose which to delete.
struct DuplicatesView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Query private var allScores: [Score]
    @AppStorage("duplicates.compareContents") private var compareContents = true

    @State private var groups: [DuplicateGroup] = []
    @State private var selectedForDeletion: Set<UUID> = []
    @State private var hasScanned = false
    @State private var progressText: String?
    @State private var confirmDelete = false
    @State private var annotated: Set<UUID> = []
    @State private var showingPaywall = false

    private static let ignoredKey = "duplicates.ignoredPairs"

    var body: some View {
        let byID = Dictionary(allScores.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        List {
            Section {
                Toggle("Compare page contents", isOn: $compareContents)
                Button {
                    if appState.pro.isPro {
                        Task { await scan() }
                    } else {
                        showingPaywall = true
                    }
                } label: {
                    Label(hasScanned ? "Scan Again" : "Scan Library", systemImage: "doc.on.doc")
                }
                .disabled(progressText != nil || allScores.count < 2)
                if let progressText {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(progressText).foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text("Finds scores with the same or a similar title and composer, or (with page contents on) the same text or the same-looking first page, even if the files differ. Nothing is deleted until you choose.")
            }

            if hasScanned && progressText == nil && groups.isEmpty {
                Section {
                    Label("No duplicates found.", systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                }
            }

            ForEach(groups) { group in
                Section {
                    ForEach(sortedScores(in: group, byID: byID)) { score in
                        row(score, group: group)
                    }
                } header: {
                    Text(group.reasons.map(\.label).joined(separator: " · "))
                } footer: {
                    HStack {
                        Button("Not Duplicates") { ignore(group) }
                        Spacer()
                        Text("Tap the circle next to a copy to delete it.")
                    }
                    .font(.footnote)
                }
            }
        }
        .navigationTitle("Find Duplicates")
        .sheet(isPresented: $showingPaywall) { PaywallView() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Label("Delete \(selectedForDeletion.count)", systemImage: "trash")
                }
                .disabled(selectedForDeletion.isEmpty)
            }
        }
        .confirmationDialog(
            "Delete \(selectedForDeletion.count) score\(selectedForDeletion.count == 1 ? "" : "s")?",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { deleteSelected(byID: byID) }
        } message: {
            Text("The selected copies are removed with their annotations. Setlist entries move to the copy you keep.")
        }
    }

    // MARK: Rows

    private func row(_ score: Score, group: DuplicateGroup) -> some View {
        let isSelected = selectedForDeletion.contains(score.id)
        let keptCount = group.scoreIDs.filter { !selectedForDeletion.contains($0) }.count
        return HStack(spacing: 12) {
            Button {
                if isSelected {
                    selectedForDeletion.remove(score.id)
                } else {
                    selectedForDeletion.insert(score.id)
                }
            } label: {
                Image(systemName: isSelected ? "trash.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? Color.red : Color.secondary)
            }
            .buttonStyle(.borderless)
            .disabled(!isSelected && keptCount <= 1)
            .accessibilityLabel(isSelected ? "Marked for deletion" : "Keep")
            .accessibilityHint("Toggles whether this copy is deleted")

            Color.white
                .frame(width: 42, height: 56)
                .overlay { ScoreThumbnailView(scoreID: score.id, fileURL: score.fileURL) }
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .shadow(color: .black.opacity(0.15), radius: 2, y: 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(score.displayTitle)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                if !score.subtitle.isEmpty {
                    Text(score.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text("\(score.originalFileName) · \(score.pageCount) pp · added \(score.dateAdded.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer()
            if annotated.contains(score.id) {
                Image(systemName: "pencil.tip")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Has annotations")
            }
            if !(score.setlistEntries ?? []).isEmpty {
                Image(systemName: "list.number")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("In a setlist")
            }
            Button {
                appState.readerRequest = ReaderRequest(scores: [score], startIndex: 0)
            } label: {
                Image(systemName: "book")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Open")
        }
        .opacity(isSelected ? 0.6 : 1)
        .contextMenu {
            Button("Keep Only This", systemImage: "checkmark.circle") {
                for id in group.scoreIDs where id != score.id { selectedForDeletion.insert(id) }
                selectedForDeletion.remove(score.id)
            }
        }
    }

    /// Best copy first: annotated, in a setlist, more details, then oldest.
    private func sortedScores(in group: DuplicateGroup, byID: [UUID: Score]) -> [Score] {
        group.scoreIDs.compactMap { byID[$0] }.sorted { a, b in
            func rank(_ s: Score) -> (Int, Int, Int) {
                (annotated.contains(s.id) ? 0 : 1, (s.setlistEntries ?? []).isEmpty ? 1 : 0, s.needsLabels ? 1 : 0)
            }
            let (ra, rb) = (rank(a), rank(b))
            if ra != rb { return ra < rb }
            return a.dateAdded < b.dateAdded
        }
    }

    // MARK: Actions

    private func scan() async {
        progressText = "Preparing…"
        selectedForDeletion = []
        let scores = allScores
        var texts: [UUID: String] = [:]

        if compareContents {
            for (index, score) in scores.enumerated() {
                progressText = "Reading \(index + 1) of \(scores.count)…"
                if score.pageFingerprint == nil {
                    score.pageFingerprint = await PageFingerprint.make(for: score.fileURL)
                }
                // Use cached text if there is some; otherwise read the text layer
                // quickly without OCR (and don't cache it, so labelling still runs OCR).
                if let cached = score.extractedText {
                    texts[score.id] = cached
                } else {
                    texts[score.id] = await TextExtractor.extractText(from: score.fileURL, allowOCR: false)
                }
            }
            try? modelContext.save()
        }

        progressText = "Comparing…"
        let candidates = scores.map { score in
            DuplicateCandidate(
                id: score.id,
                fileName: score.originalFileName,
                title: score.displayTitle,
                composer: score.composer,
                pageCount: score.pageCount,
                sha256: score.contentHash,
                text: compareContents ? texts[score.id] : nil,
                fingerprint: compareContents ? score.pageFingerprint : nil)
        }
        let ignored = Set(UserDefaults.standard.stringArray(forKey: Self.ignoredKey) ?? [])
        let found = await Task.detached(priority: .userInitiated) {
            DuplicateFinder.findGroups(candidates, ignoredPairs: ignored)
        }.value

        let store = AnnotationStore()
        annotated = Set(found.flatMap(\.scoreIDs).filter { store.hasAnnotations(for: $0) })
        groups = found
        hasScanned = true
        progressText = nil
    }

    private func ignore(_ group: DuplicateGroup) {
        var ignored = Set(UserDefaults.standard.stringArray(forKey: Self.ignoredKey) ?? [])
        for (i, a) in group.scoreIDs.enumerated() {
            for b in group.scoreIDs[(i + 1)...] {
                ignored.insert(DuplicateFinder.pairKey(a, b))
            }
        }
        UserDefaults.standard.set(Array(ignored), forKey: Self.ignoredKey)
        groups.removeAll { $0.id == group.id }
        group.scoreIDs.forEach { selectedForDeletion.remove($0) }
    }

    private func deleteSelected(byID: [UUID: Score]) {
        for group in groups {
            let keeper = sortedScores(in: group, byID: byID).first { !selectedForDeletion.contains($0.id) }
            for id in group.scoreIDs where selectedForDeletion.contains(id) {
                if let score = byID[id] {
                    LibraryActions.deleteDuplicate(score, keeping: keeper, context: modelContext)
                }
            }
        }
        let deleted = selectedForDeletion
        selectedForDeletion = []
        groups = groups.compactMap { group in
            let remaining = group.scoreIDs.filter { !deleted.contains($0) }
            return remaining.count > 1 ? DuplicateGroup(scoreIDs: remaining, reasons: group.reasons) : nil
        }
        try? modelContext.save()
    }
}
