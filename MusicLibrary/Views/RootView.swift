import SwiftUI
import SwiftData

enum SidebarItem: Hashable {
    case allScores
    case recent
    case needsDetails
    case browse(FacetKind)
    case setlist(UUID)
    case labelling
}

struct RootView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @State private var selection: SidebarItem? = .allScores

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
            ReaderView(request: request)
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
        .overlay {
            if let message = appState.busyMessage {
                BusyOverlay(message: message)
            }
        }
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
