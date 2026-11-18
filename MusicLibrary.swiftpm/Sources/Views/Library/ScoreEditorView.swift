import SwiftUI
import SwiftData

/// Edit a score's details. Also shown straight after importing a single file,
/// so suggested details can be checked before they're relied on.
struct ScoreEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let score: Score
    @State private var metadata: ScoreMetadata
    @State private var confirmDelete = false
    @State private var isFilling = false
    @State private var showingPaywall = false
    @Environment(AppState.self) private var appState
    @State private var fillNote: String?
    @State private var aiStatus: AppleIntelligenceStatus = .unavailable("")

    init(score: Score) {
        self.score = score
        _metadata = State(initialValue: score.metadata)
    }

    /// Bumped when the form is refilled, so text fields pick up the new values.
    @State private var metadataVersion = 0

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(alignment: .top, spacing: 14) {
                        Color.white
                            .frame(width: 72, height: 96)
                            .overlay { ScoreThumbnailView(scoreID: score.id, fileURL: score.fileURL) }
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                            .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(score.originalFileName)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(3)
                            Text("\(score.pageCount) page\(score.pageCount == 1 ? "" : "s") · added \(score.dateAdded.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if score.labelStatus == .autoUncertain {
                    Section {
                        Label("Filled in automatically. Please check these details, then tap Save.", systemImage: "exclamationmark.circle")
                            .font(.callout)
                            .foregroundStyle(.orange)
                    }
                }

                if aiStatus.isAvailable {
                    Section {
                        Button {
                            if appState.pro.isPro {
                                Task { await fillWithAppleIntelligence() }
                            } else {
                                showingPaywall = true
                            }
                        } label: {
                            HStack {
                                Label(isFilling ? "Reading the score…" : "Fill In with Apple Intelligence", systemImage: "sparkles")
                                if isFilling {
                                    Spacer()
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(isFilling)
                    } footer: {
                        if let fillNote { Text(fillNote) }
                    }
                }

                MetadataFormFields(metadata: $metadata)
                    .id(metadataVersion)

                if score.isPersonal {
                    Section {
                        Button("Delete Score", role: .destructive) { confirmDelete = true }
                    }
                } else if let choir = CloudSync.shared.choir(score.cloudLibrary) {
                    Section {
                        Label("In \(choir.name). Changes to these details reach everyone in the group.", systemImage: "person.3")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Score Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        score.metadata = metadata
                        score.labelStatus = nil
                        try? modelContext.save()
                        dismiss()
                    }
                }
            }
            .onAppear { aiStatus = AppleIntelligence.status }
            .sheet(isPresented: $showingPaywall) { PaywallView() }
            .alert("Delete \u{201C}\(score.displayTitle)\u{201D}?", isPresented: $confirmDelete) {
                Button("Delete", role: .destructive) {
                    let context = modelContext
                    let target = score
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        LibraryActions.delete(target, context: context)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes the PDF from this device, with its details, annotations and place in any setlists. This can't be undone.")
            }
        }
    }

    private func fillWithAppleIntelligence() async {
        guard let suggester = AppleIntelligence.makeSuggester() else {
            fillNote = AppleIntelligence.status.message
            return
        }
        isFilling = true
        defer { isFilling = false }
        if score.extractedText == nil {
            score.extractedText = await TextExtractor.extractText(from: score.fileURL)
        }
        let input = SuggestionInput(fileName: score.originalFileName, extractedText: score.extractedText)
        guard let suggestion = await suggester.suggest(for: input) else {
            fillNote = "Apple Intelligence couldn't read this score."
            return
        }
        metadata = AutoLabelLogic.merged(suggestion.metadata, into: metadata)
        metadataVersion += 1
        var note = "Filled in by Apple Intelligence"
        if let confidence = suggestion.confidence["*"] {
            note += " (\(Int((confidence * 100).rounded()))% sure)"
        }
        note += ". Check the details, then tap Save."
        if !suggestion.flags.isEmpty { note += " Note: " + suggestion.flags.joined(separator: "; ") }
        fillNote = note
    }
}
