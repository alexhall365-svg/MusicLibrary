import SwiftUI
import SwiftData

enum SidebarItem: Hashable {
    case allScores
    case recent
    case needsDetails
    case browse(FacetKind)
    case setlist(UUID)
    case labelling
    case duplicates
}

struct RootView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @State private var selection: SidebarItem? = .allScores
    @State private var showingDemoPaywall = false

    var body: some View {
        @Bindable var appState = appState
        NavigationSplitView {
            SidebarView(selection: $selection)
        } detail: {
            NavigationStack {
                detail
            }
            .id(selection)
        }
        .fullScreenCover(item: $appState.readerRequest) { request in
            if request.scores.isEmpty {
                // Nothing to show (e.g. an empty setlist): close straight away.
                Color.clear.onAppear { appState.readerRequest = nil }
            } else {
                ReaderView(request: request)
            }
        }
        .sheet(item: $appState.review) { review in
            MetadataReviewView(review: review)
        }
        .sheet(item: $appState.editingScore) { score in
            ScoreEditorView(score: score)
        }
        .alert(
            appState.alert?.title ?? "",
            isPresented: Binding(
                get: { appState.alert != nil },
                set: { if !$0 { appState.alert = nil } }
            ),
            presenting: appState.alert
        ) { _ in
            Button("OK") {}
        } message: { alert in
            Text(alert.message)
        }
        .overlay(alignment: .bottom) {
            AutoLabelBanner(labeler: appState.autoLabeler)
                .padding(.bottom, 12)
        }
        .overlay {
            if let message = appState.busyMessage {
                BusyOverlay(message: message)
            }
        }
        .task {
            LibraryMaintenance.runIfNeeded(context: modelContext)
            DemoContent.prepareIfRequested(context: modelContext, appState: appState)
            if let item = DemoContent.requestedSidebarItem(context: modelContext) {
                selection = item
            }
            if UserDefaults.standard.string(forKey: "demoScreen") == "paywall"
                && UserDefaults.standard.bool(forKey: "demoLibrary") {
                showingDemoPaywall = true
            }
        }
        .sheet(isPresented: $showingDemoPaywall) { PaywallView() }
        .onOpenURL { url in
            Task { await ImportCoordinator(context: modelContext, appState: appState).handleOpenedURL(url) }
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .allScores, .none:
            ScoreCollectionView(scope: .all)
        case .recent:
            ScoreCollectionView(scope: .recent)
        case .needsDetails:
            ScoreCollectionView(scope: .needsDetails)
        case .browse(let kind):
            BrowseView(kind: kind)
        case .setlist(let id):
            SetlistDetailView(setlistID: id)
        case .labelling:
            ClaudeLabellingView()
        case .duplicates:
            DuplicatesView()
        }
    }
}

struct BusyOverlay: View {
    let message: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView()
                Text(message)
                    .font(.callout)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .accessibilityElement(children: .combine)
    }
}

/// Shows Apple Intelligence progress without blocking the app.
struct AutoLabelBanner: View {
    let labeler: AutoLabeler

    var body: some View {
        Group {
            if labeler.isRunning && labeler.total > 0 {
                HStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Apple Intelligence: \(min(labeler.done + 1, labeler.total)) of \(labeler.total)")
                            .font(.footnote.weight(.semibold))
                            .monospacedDigit()
                        ProgressView(value: Double(labeler.done), total: Double(max(labeler.total, 1)))
                            .frame(width: 180)
                    }
                    Button("Stop") { labeler.stop() }
                        .font(.footnote)
                        .buttonStyle(.bordered)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.regularMaterial, in: Capsule())
                .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
            } else if let summary = labeler.summary {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(Color.accentColor)
                    Text(summary)
                        .font(.footnote)
                    Button {
                        labeler.summary = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Dismiss")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.regularMaterial, in: Capsule())
                .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
                .padding(.horizontal, 16)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: labeler.isRunning)
    }
}
