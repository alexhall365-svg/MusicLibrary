import SwiftUI
import SwiftData

struct ReaderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var session: ReaderSession
    @State private var annotation = AnnotationController()

    init(request: ReaderRequest) {
        _session = State(initialValue: ReaderSession(scores: request.scores, startIndex: request.startIndex))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            SpreadView(
                renderer: session.renderer,
                pages: session.visiblePages,
                annotating: session.isAnnotating,
                controller: annotation,
                toolKey: annotation.configurationKey
            )
            .ignoresSafeArea()
            .accessibilityElement(children: .contain)

            if !session.isAnnotating {
                TurnZones(session: session)
                    .ignoresSafeArea()
            }

            if session.chromeVisible && !session.isAnnotating {
                ReaderChrome(session: session, onClose: close)
                    .transition(.opacity)
            }

            if session.isAnnotating {
                annotationOverlay
            }
        }
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { session.setLandscape(proxy.size.width > proxy.size.height) }
                    .onChange(of: proxy.size) { _, size in
                        session.setLandscape(size.width > size.height)
                    }
            }
        )
        .statusBarHidden(!session.chromeVisible || session.isAnnotating)
        .persistentSystemOverlays(.hidden)
        .preferredColorScheme(.dark)
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            session.saveProgress()
            try? modelContext.save()
        }
    }

    private var annotationOverlay: some View {
        ZStack {
            HStack {
                Spacer()
                AnnotationToolbar(controller: annotation) {
                    withAnimation { session.isAnnotating = false }
                }
                .padding(.trailing, 12)
            }
            VStack {
                Spacer()
                HStack(spacing: 24) {
                    Button { session.previousPage() } label: {
                        Image(systemName: "chevron.left")
                            .frame(width: 44, height: 44)
                    }
                    .disabled(!session.canGoBack)
                    .accessibilityLabel("Previous page")
                    Text(session.pageLabel)
                        .font(.footnote.monospacedDigit())
                    Button { session.nextPage() } label: {
                        Image(systemName: "chevron.right")
                            .frame(width: 44, height: 44)
                    }
                    .disabled(!session.canGoForward)
                    .accessibilityLabel("Next page")
                }
                .padding(.horizontal, 12)
                .background(.regularMaterial, in: Capsule())
                .padding(.bottom, 12)
            }
        }
    }

    private func close() {
        session.saveProgress()
        try? modelContext.save()
        dismiss()
    }
}

/// Invisible tap and swipe areas: left third back, right third forward, middle
/// shows or hides the controls.
private struct TurnZones: View {
    let session: ReaderSession

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                zone(width: proxy.size.width * 0.3, label: "Previous page") {
                    session.previousPage()
                    hideChrome()
                }
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) { session.chromeVisible.toggle() }
                    }
                    .accessibilityLabel(session.chromeVisible ? "Hide controls" : "Show controls")
                    .accessibilityAddTraits(.isButton)
                zone(width: proxy.size.width * 0.3, label: "Next page") {
                    session.nextPage()
                    hideChrome()
                }
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 30).onEnded { value in
                    let horizontal = value.translation.width
                    guard abs(horizontal) > abs(value.translation.height), abs(horizontal) > 50 else { return }
                    if horizontal < 0 { session.nextPage() } else { session.previousPage() }
                    hideChrome()
                }
            )
        }
    }

    private func zone(width: CGFloat, label: String, action: @escaping () -> Void) -> some View {
        Color.clear
            .frame(width: width)
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isButton)
    }

    private func hideChrome() {
        if session.chromeVisible {
            withAnimation(.easeInOut(duration: 0.2)) { session.chromeVisible = false }
        }
    }
}

/// The top and bottom bars shown over the music.
private struct ReaderChrome: View {
    @Bindable var session: ReaderSession
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Spacer()
            if session.pageCount > 1 && !session.isPerformanceMode {
                pageScrubber
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .frame(width: 36, height: 36)
            }
            .accessibilityLabel("Close")

            VStack(alignment: .leading, spacing: 1) {
                Text(session.currentScore.displayTitle)
                    .font(.headline)
                    .lineLimit(1)
                if !session.currentScore.subtitle.isEmpty {
                    Text(session.currentScore.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            if session.isSetlist {
                setlistControls
            }

            Text(session.pageLabel)
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)

            if session.isPerformanceMode {
                Label("Performance", systemImage: "lock.fill")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.35), in: Capsule())
            }

            if session.isLandscape {
                Button { session.toggleTwoUp() } label: {
                    Image(systemName: session.twoUpEnabled ? "book.pages.fill" : "book.pages")
                        .frame(width: 36, height: 36)
                }
                .accessibilityLabel(session.twoUpEnabled ? "Show one page" : "Show two pages")
            }

            if !session.isPerformanceMode {
                Button {
                    withAnimation { session.isAnnotating = true }
                } label: {
                    Image(systemName: "pencil.tip.crop.circle")
                        .frame(width: 36, height: 36)
                }
                .accessibilityLabel("Annotate")
            }

            Button {
                withAnimation { session.isPerformanceMode.toggle() }
            } label: {
                Image(systemName: session.isPerformanceMode ? "lock.fill" : "lock.open")
                    .frame(width: 36, height: 36)
            }
            .accessibilityLabel(session.isPerformanceMode ? "Leave performance mode" : "Performance mode")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.regularMaterial)
    }

    private var setlistControls: some View {
        HStack(spacing: 4) {
            Button { session.previousScore() } label: {
                Image(systemName: "backward.end.fill")
                    .frame(width: 32, height: 32)
            }
            .disabled(!session.hasPreviousScore)
            .accessibilityLabel("Previous piece")
            Text("\(session.scoreIndex + 1)/\(session.scores.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Button { session.nextScore() } label: {
                Image(systemName: "forward.end.fill")
                    .frame(width: 32, height: 32)
            }
            .disabled(!session.hasNextScore)
            .accessibilityLabel("Next piece")
        }
        .padding(.horizontal, 6)
        .background(Color.primary.opacity(0.08), in: Capsule())
    }

    private var pageScrubber: some View {
        HStack {
            Text("1").font(.caption2).foregroundStyle(.secondary)
            Slider(
                value: Binding(
                    get: { Double(session.pageIndex) },
                    set: { session.goToPage(Int($0.rounded())) }
                ),
                in: 0...Double(max(session.pageCount - 1, 1)),
                step: 1
            )
            .accessibilityLabel("Page")
            .accessibilityValue(session.pageLabel)
            Text("\(session.pageCount)").font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.regularMaterial)
    }
}
