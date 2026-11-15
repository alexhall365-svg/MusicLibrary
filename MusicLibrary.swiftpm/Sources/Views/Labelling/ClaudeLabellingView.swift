import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Bulk labelling: export scores (with text from their first pages), ask Claude
/// to fill in the details, then import and review Claude's answer.
struct ClaudeLabellingView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Score.dateAdded) private var scores: [Score]
    @AppStorage("labelling.onlyMissing") private var onlyMissing = true
    @AppStorage("labelling.batchSize") private var batchSize = 50
    @State private var exportedFiles: [URL] = []
    @State private var progressText: String?
    @State private var showingFileImporter = false
    @State private var copied = false

    private var targetScores: [Score] {
        onlyMissing ? scores.filter(\.needsLabels) : scores
    }

    var body: some View {
        Form {
            Section {
                Text("Label hundreds of scores at once. Export them, let Claude identify each piece from its first pages, then review Claude's suggestions before anything is saved.")
                    .font(.callout)
            }

            exportSection
            askSection
            importSection

            Section {
                Button("Export All Library Details", systemImage: "square.and.arrow.up.on.square") {
                    Task { await export(scores, includeText: false, stem: "Library details") }
                }
                .disabled(scores.isEmpty || progressText != nil)
            } header: {
                Text("Edit Existing Details")
            } footer: {
                Text("Exports every score's details in the same format, without page text, so you or Claude can correct or enrich them and import the file back here.")
            }
        }
        .navigationTitle("Label with Claude")
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.json, .plainText],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                coordinator.importMetadataFile(at: url)
            }
        }
    }

    private var coordinator: ImportCoordinator {
        ImportCoordinator(context: modelContext, appState: appState)
    }

    private var exportSection: some View {
        Section {
            Toggle("Only scores missing details", isOn: $onlyMissing)
            Picker("Scores per file", selection: $batchSize) {
                Text("25").tag(25)
                Text("50").tag(50)
                Text("100").tag(100)
                Text("All in one").tag(0)
            }
            LabeledContent("Scores to export", value: "\(targetScores.count)")
            Button {
                Task { await export(targetScores, includeText: true, stem: "For Claude") }
            } label: {
                Label("Prepare Export", systemImage: "square.and.arrow.up")
            }
            .disabled(targetScores.isEmpty || progressText != nil)

            if let progressText {
                HStack(spacing: 10) {
                    ProgressView()
                    Text(progressText).foregroundStyle(.secondary)
                }
            }
            ForEach(exportedFiles, id: \.self) { url in
                ShareLink(item: url) {
                    Label(url.lastPathComponent, systemImage: "doc.text")
                }
            }
        } header: {
            Text("1. Export")
        } footer: {
            Text("Text from the first two pages of each score is included so Claude can identify it. Scanned pages are read with on-device text recognition, which can take a few seconds per score the first time. Tap a file to send it to the Claude app or save it to Files.")
        }
    }

    private var askSection: some View {
        Section {
            Text(ClaudeInstructions.chatMessage)
                .font(.callout)
                .textSelection(.enabled)
            Button(copied ? "Copied" : "Copy Message", systemImage: copied ? "checkmark" : "doc.on.doc") {
                UIPasteboard.general.string = ClaudeInstructions.chatMessage
                copied = true
            }
        } header: {
            Text("2. Ask Claude")
        } footer: {
            Text("In the Claude app, start a new chat, attach one exported file, paste this message and send. Use a new chat for each file. The detailed instructions travel inside the file.")
        }
    }

    private var importSection: some View {
        Section {
            Button("Paste Claude's Reply", systemImage: "doc.on.clipboard") {
                guard let text = UIPasteboard.general.string, !text.trimmed.isEmpty else {
                    appState.alert = AppAlert(
                        title: "Nothing to Paste",
                        message: "Copy Claude's reply first (use the copy button under the reply or code block), then try again.")
                    return
                }
                coordinator.importMetadata(Data(text.utf8), title: "Claude's Suggestions")
            }
            Button("Choose a JSON File…", systemImage: "folder") {
                showingFileImporter = true
            }
        } header: {
            Text("3. Review and Import")
        } footer: {
            Text("You'll see every change before it's saved. Anything Claude was unsure about is highlighted.")
        }
    }

    private func export(_ list: [Score], includeText: Bool, stem: String) async {
        exportedFiles = []
        if includeText {
            let needingText = list.filter { $0.extractedText == nil }
            for (index, score) in needingText.enumerated() {
                progressText = "Reading score \(index + 1) of \(needingText.count)…"
                score.extractedText = await TextExtractor.extractText(from: score.fileURL)
                if index % 20 == 19 { try? modelContext.save() }
            }
            try? modelContext.save()
        }
        progressText = "Writing files…"
        do {
            exportedFiles = try MetadataExporter.writeFiles(
                for: list,
                includeText: includeText,
                batchSize: batchSize > 0 ? batchSize : nil,
                fileStem: stem)
        } catch {
            appState.alert = AppAlert(title: "Export Failed", message: error.localizedDescription)
        }
        progressText = nil
    }
}
