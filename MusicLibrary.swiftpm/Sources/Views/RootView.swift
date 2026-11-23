import SwiftUI
import StoreKit
import SwiftData

enum SidebarItem: Hashable {
    case allScores
    case recent
    case needsDetails
    case browse(FacetKind)
    case setlist(UUID)
    /// A Choir Library's music (its library key, see `CloudLibrary`).
    case choir(String)
    case labelling
    case duplicates
}

struct RootView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @State private var selection: SidebarItem? = .allScores
    @State private var showingDemoPaywall = false
    @State private var showingDemoGroups = false
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.requestReview) private var requestReview

    /// On iPad the sidebar stays visible, so progress and busy messages are
    /// centred over the content column rather than the whole screen.
    private var overlaysInDetail: Bool { sizeClass == .regular }

    var body: some View {
        @Bindable var appState = appState
        NavigationSplitView {
            SidebarView(selection: $selection)
        } detail: {
            NavigationStack {
                detail
            }
            .id(selection)
            .modifier(StatusOverlays(enabled: overlaysInDetail))
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
        .modifier(StatusOverlays(enabled: !overlaysInDetail))
        .onChange(of: appState.readerRequest == nil) { _, closed in
            if closed { askForRatingIfDue() }
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
            if UserDefaults.standard.string(forKey: "demoScreen") == "groups"
                && UserDefaults.standard.bool(forKey: "demoLibrary") {
                showingDemoGroups = true
            }
        }
        .sheet(isPresented: $showingDemoPaywall) { PaywallView() }
        .sheet(isPresented: $showingDemoGroups) { SyncSettingsView() }
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
        case .choir(let library):
            ScoreCollectionView(scope: .library(library))
        case .labelling:
            AutoLabelView()
        case .duplicates:
            DuplicatesView()
        }
    }
}

/// Progress banners and the busy message, placed by `RootView`.
private struct StatusOverlays: ViewModifier {
    let enabled: Bool
    @Environment(AppState.self) private var appState

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if enabled {
                    VStack(spacing: 8) {
                        ImportBanner()
                        SyncProgressBanner()
                        AutoLabelBanner(labeler: appState.autoLabeler)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }
            }
    }
}

extension RootView {
    /// Asks for an App Store rating once per version, after someone has read
    /// music in the app a few times (never mid-task: only as the reader closes).
    /// iOS also limits how often the prompt can appear.
    fileprivate func askForRatingIfDue() {
        let defaults = UserDefaults.standard
        let opens = defaults.integer(forKey: "rating.readerCloses") + 1
        defaults.set(opens, forKey: "rating.readerCloses")
        let askedVersion = defaults.string(forKey: "rating.askedVersion")
        guard opens >= 8, askedVersion != AppConfig.version,
              !UserDefaults.standard.bool(forKey: "demoLibrary") else { return }
        defaults.set(AppConfig.version, forKey: "rating.askedVersion")
        Task {
            try? await Task.sleep(for: .seconds(1))
            requestReview()
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
/// Import progress and result, shown without blocking the app.
struct ImportBanner: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            if let status = appState.importStatus {
                HStack(spacing: 10) {
                    ProgressView()
                    Text(status)
                        .font(.footnote.weight(.semibold))
                        .monospacedDigit()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.regularMaterial, in: Capsule())
                .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
            } else if let summary = appState.importSummary {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(summary)
                        .font(.footnote)
                    Button {
                        appState.importSummary = nil
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
                .task(id: summary) {
                    // Clears itself after a few seconds.
                    try? await Task.sleep(for: .seconds(4))
                    if appState.importSummary == summary { appState.importSummary = nil }
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: appState.importStatus)
        .animation(.easeInOut(duration: 0.2), value: appState.importSummary)
    }
}

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
                            .lineLimit(1)
                            .fixedSize()
                        ProgressView(value: Double(labeler.done), total: Double(max(labeler.total, 1)))
                            .frame(minWidth: 180)
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
