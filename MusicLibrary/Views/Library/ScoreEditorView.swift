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

    init(score: Score) {
        self.score = score
        _metadata = State(initialValue: score.metadata)
    }

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

                MetadataFormFields(metadata: $metadata)

                Section {
                    Button("Delete Score", role: .destructive) { confirmDelete = true }
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
                        try? modelContext.save()
                        dismiss()
                    }
                }
            }
            .confirmationDialog("Delete this score?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete Score", role: .destructive) {
                    let context = modelContext
                    let target = score
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        LibraryActions.delete(target, context: context)
                    }
                }
            } message: {
                Text("This removes the PDF, its annotations and its place in any setlists.")
            }
        }
    }
}
