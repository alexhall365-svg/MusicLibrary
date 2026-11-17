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
                toolKey: annotation.configurationKey,
                pageDescription: "Page \(session.pageLabel)",
                onGesture: handle
            )
            .ignoresSafeArea()

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
                    .onAppear { session.updateLayout(for: proxy.size) }
                    .onChange(of: proxy.size) { _, size in
                        session.updateLayout(for: size)
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

    private func handle(_ gesture: ReaderGesture) {
        switch gesture {
        case .previous:
            session.previousPage()
            hideChrome()
        case .next:
            session.nextPage()
            hideChrome()
        case .toggleControls:
            withAnimation(.easeInOut(duration: 0.2)) { session.chromeVisible.toggle() }
        }
    }

    private func hideChrome() {
        if session.chromeVisible {
            withAnimation(.easeInOut(duration: 0.2)) { session.chromeVisible = false }
        }
    }

    private func close() {
        session.saveProgress()
        try? modelContext.save()
        dismiss()
    }
}

/// The top and bottom bars shown over the music.
private struct ReaderChrome: View {
    @Bindable var session: ReaderSession
    let onClose: () -> Void
    @Environment(\.horizontalSizeClass) private var sizeClass

    /// iPhone (and narrow iPad split view): fewer, smaller controls.
    private var isCompact: Bool { sizeClass == .compact }

    @State private var showingGoTo = false
    @State private var goToText = ""

    /// The page number; tap it to jump to another page.
    private var pageButton: some View {
        Button {
            goToText = ""
            showingGoTo = true
        } label: {
            Text(session.pageLabel)
                .font((isCompact ? Font.caption : Font.footnote).monospacedDigit())
                .foregroundStyle(.secondary)
                .fixedSize()
        }
        .accessibilityLabel("Page \(session.pageLabel)")
        .accessibilityHint("Go to another page")
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Spacer()
            if session.pageCount > 1 && !session.isPerformanceMode {
                pageScrubber
            }
        }
        .alert("Go to Page", isPresented: $showingGoTo) {
            TextField("1–\(session.pageCount)", text: $goToText)
                .keyboardType(.numberPad)
            Button("Go") {
                if let number = Int(goToText.trimmed), number >= 1 {
                    session.goToPage(number - 1)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter a page number from 1 to \(session.pageCount).")
        }
    }

    private var topBar: some View {
        HStack(spacing: isCompact ? 6 : 12) {
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
                if !session.currentScore.subtitle.isEmpty && !isCompact {
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

            if !isCompact {
                pageButton
            }

            if session.isPerformanceMode && !isCompact {
                Label("Performance", systemImage: "lock.fill")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.35), in: Capsule())
            }

            if session.canShowTwoPages {
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
            if !isCompact {
                Text("\(session.scoreIndex + 1)/\(session.scores.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
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
            if isCompact {
                pageButton
            } else {
                Text("1").font(.caption2).foregroundStyle(.secondary)
            }
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
            if !isCompact {
                Text("\(session.pageCount)").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.regularMaterial)
    }
}
