import SwiftUI
import SwiftData

/// Fill in titles, composers and more for many scores at once with Apple
/// Intelligence, on the device. Every suggestion is reviewed before it's saved.
struct AutoLabelView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Score.dateAdded) private var allScores: [Score]
    @AppStorage("labelling.onlyMissing") private var onlyMissing = true
    @AppStorage(AppleIntelligence.autoLabelOnImportKey) private var autoLabelOnImport = true
    @State private var aiStatus: AppleIntelligenceStatus = .unavailable("Checking…")
    @State private var showingPaywall = false

    /// Scores this person can change (not music in a group they only view).
    private var scores: [Score] { allScores.filter { CloudSync.shared.canEdit($0) } }

    private var targetScores: [Score] {
        onlyMissing ? scores.filter(\.needsAttention) : scores
    }

    var body: some View {
        let labeler = appState.autoLabeler
        Form {
            Section {
                Text("Fill in titles, composers and more for many scores at once. Apple Intelligence works on this \(UIDevice.current.model), privately and offline, and you review every suggestion before it's saved.")
                    .font(.callout)
                Toggle("Only scores that need details", isOn: $onlyMissing)
                LabeledContent("Scores", value: "\(targetScores.count)")
            }

            if !appState.pro.isPro {
                Section {
                    Button {
                        showingPaywall = true
                    } label: {
                        Label("Auto-labelling is part of Pro: a one-time unlock. Tap to see what's included.", systemImage: "sparkles")
                    }
                }
            }

            Section {
                HStack {
                    Text("Status")
                    Spacer()
                    Image(systemName: aiStatus.isAvailable ? "checkmark.circle.fill" : "xmark.circle")
                        .foregroundStyle(aiStatus.isAvailable ? Color.green : Color.secondary)
                        .accessibilityHidden(true)
                    Text(aiStatus.isAvailable ? "Ready" : "Unavailable")
                        .foregroundStyle(aiStatus.isAvailable ? Color.green : Color.secondary)
                }
                .accessibilityElement(children: .combine)
                if !aiStatus.isAvailable {
                    Text(aiStatus.message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Toggle("Fill in details when importing", isOn: $autoLabelOnImport)
                    .disabled(!aiStatus.isAvailable)
                Button {
                    if appState.pro.isPro {
                        labeler.start(targetScores.map(\.id), mode: .review, context: modelContext, appState: appState)
                    } else {
                        showingPaywall = true
                    }
                } label: {
                    Label("Label \(targetScores.count) Score\(targetScores.count == 1 ? "" : "s") on This \(UIDevice.current.model)", systemImage: "sparkles")
                }
                .disabled(!aiStatus.isAvailable || labeler.isRunning || targetScores.isEmpty)
                if labeler.isRunning {
                    Text("Working… \(labeler.done) of \(labeler.total) done. You can leave this screen; the review opens when it's finished.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Apple Intelligence")
            } footer: {
                Text("New imports are filled in automatically; anything uncertain appears under Needs Details. Use the button to relabel scores you imported earlier. It takes a few seconds per score.")
            }
        }
        .navigationTitle("Auto-Label")
        .sheet(isPresented: $showingPaywall) { PaywallView() }
        .onAppear { aiStatus = AppleIntelligence.status }
    }
}
