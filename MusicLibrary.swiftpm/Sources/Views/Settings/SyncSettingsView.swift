import SwiftUI
import CloudKit

/// "iCloud & Groups": sync with your own devices, and the Choir Library.
struct SyncSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Environment(CloudSync.self) private var sync
    @State private var bytesUsed: Int64 = 0
    @State private var counts: (here: Int, inICloud: Int) = (0, 0)
    @AppStorage(AnnotationStore.showDirectorKey) private var showDirectorMarkings = true
    @State private var showingCreate = false
    @State private var newChoirName = ""
    @State private var isWorking = false
    @State private var showingPaywall = false
    @State private var choirToRename: ChoirInfo?
    @State private var renameText = ""
    @State private var choirToDelete: ChoirInfo?
    @State private var choirToLeave: ChoirInfo?
    @State private var errorMessage: String?

    var body: some View {
        @Bindable var sync = sync
        NavigationStack {
            Form {
                if sync.demoMode {
                    // Screenshots: the group section only (the simulator has no iCloud).
                    Section {
                        Label("Sync with iCloud: up to date", systemImage: "checkmark.icloud")
                    } footer: {
                        Text("Your scores, details, setlists and annotations sync between your own iPad and iPhone. Every device keeps a full copy, so everything works offline.")
                    }
                    hostedSection
                } else if !sync.isSupported {
                    Section {
                        Label("iCloud sync and shared groups work in the TestFlight and App Store versions of \(AppConfig.displayName). This build (for example from Swift Playgrounds) keeps everything on this device.", systemImage: "icloud.slash")
                            .font(.callout)
                    }
                } else {
                    Section {
                        Toggle(isOn: $sync.isEnabled) {
                            Label("Sync with iCloud", systemImage: "icloud")
                        }
                        if sync.isEnabled {
                            statusRow
                            Button {
                                Task { await sync.syncNow() }
                            } label: {
                                Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                            }
                            .disabled(sync.isFetching || sync.isSending)
                        }
                    } footer: {
                        Text("Your scores, details, setlists and annotations sync between your own iPad and iPhone. Every device keeps a full copy, so everything works offline; changes sync when you're next online.")
                    }

                    if let problem = sync.problem {
                        Section {
                            Label(problem, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                            Button("Dismiss") { sync.clearProblem() }
                        }
                    }

                    Section {
                        LabeledContent("Your iCloud storage used", value: ByteCountFormatter.string(fromByteCount: bytesUsed, countStyle: .file))
                    } footer: {
                        Text("Your library and any group you host count against your iCloud storage (5 GB free). Groups you join use their owner's storage, not yours.")
                    }

                    if sync.isEnabled {
                        detailsSection
                        hostedSection
                        if !sync.joinedChoirs.isEmpty { joinedSection }
                    }
                }
            }
            .navigationTitle("iCloud & Groups")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                _ = await sync.currentUserID()
                bytesUsed = sync.iCloudBytesUsed()
                counts = sync.personalScoreCounts()
            }
            .onChange(of: sync.pendingChanges) { _, _ in counts = sync.personalScoreCounts() }
            .onChange(of: sync.isFetching) { _, _ in counts = sync.personalScoreCounts() }
            .sheet(isPresented: $showingPaywall) { PaywallView() }
            .alert("New Shared Group", isPresented: $showingCreate) {
                TextField("Group name", text: $newChoirName)
                Button("Create") { createChoir() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("For example \"St Mary's Choir\" or \"City Brass Band\". You can then add music and lists, and share the link.")
            }
            .alert("Rename Group", isPresented: Binding(
                get: { choirToRename != nil }, set: { if !$0 { choirToRename = nil } })
            ) {
                TextField("Group name", text: $renameText)
                Button("Rename") {
                    if let choir = choirToRename { run { try await sync.renameChoir(choir.id, to: renameText) } }
                    choirToRename = nil
                }
                Button("Cancel", role: .cancel) { choirToRename = nil }
            }
            .confirmationDialog(
                "Delete \"\(choirToDelete?.name ?? "")\"?",
                isPresented: Binding(get: { choirToDelete != nil }, set: { if !$0 { choirToDelete = nil } }),
                titleVisibility: .visible
            ) {
                Button("Delete Group", role: .destructive) {
                    if let choir = choirToDelete { sync.deleteHostedChoir(choir.id) }
                    choirToDelete = nil
                }
            } message: {
                Text("The group's music and lists are removed from every member's devices. You keep them: they move into your own library.")
            }
            .confirmationDialog(
                "Leave \"\(choirToLeave?.name ?? "")\"?",
                isPresented: Binding(get: { choirToLeave != nil }, set: { if !$0 { choirToLeave = nil } }),
                titleVisibility: .visible
            ) {
                Button("Leave Group", role: .destructive) {
                    if let choir = choirToLeave { run { try await sync.leaveChoir(choir.id) } }
                    choirToLeave = nil
                }
            } message: {
                Text("The group's music and your annotations on it are removed from your devices. Your own library isn't affected.")
            }
            .alert("Couldn't Complete", isPresented: Binding(
                get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
            ) {
                Button("OK") {}
            } message: {
                Text(errorMessage ?? "")
            }
            .overlay {
                if isWorking { BusyOverlay(message: "Talking to iCloud…") }
            }
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        HStack {
            Text(statusText)
            Spacer()
            if sync.isFetching || sync.isSending {
                ProgressView()
            } else if isUpToDate {
                Image(systemName: "checkmark.icloud")
                    .foregroundStyle(.green)
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }

    private var statusText: String {
        switch sync.accountStatus {
        case .noAccount: return "Not signed in to iCloud"
        case .restricted: return "iCloud is restricted on this device"
        case .temporarilyUnavailable: return "iCloud is temporarily unavailable"
        default: break
        }
        if sync.isFetching { return "Checking iCloud for changes…" }
        if sync.problem != nil { return "Not syncing: see the message below" }
        if sync.pendingChanges > 0 {
            return "\(sync.pendingChanges) change\(sync.pendingChanges == 1 ? "" : "s") to upload"
        }
        if !sync.hasDownloadedOnce { return "Waiting for the first check with iCloud" }
        if counts.inICloud < counts.here {
            return "\(counts.here - counts.inICloud) scores not uploaded yet. Tap Sync Now"
        }
        if let last = sync.lastSync {
            return "Up to date · \(last.formatted(.relative(presentation: .named)))"
        }
        return "Waiting to sync"
    }

    private var isUpToDate: Bool {
        sync.pendingChanges == 0 && sync.accountStatus == .available && sync.problem == nil
            && sync.hasDownloadedOnce && counts.inICloud >= counts.here
    }

    private var detailsSection: some View {
        Section("Sync Details") {
            LabeledContent("Your scores on this device", value: "\(counts.here)")
            LabeledContent("Of those, in iCloud", value: "\(counts.inICloud)")
            if counts.here > 0 && counts.inICloud < counts.here {
                ProgressView(value: Double(counts.inICloud), total: Double(counts.here))
            }
            LabeledContent("Waiting to upload", value: "\(sync.pendingChanges)")
            NavigationLink("Sync Log") { SyncLogView() }
            if let id = sync.userID {
                LabeledContent("Your iCloud ID") {
                    Button {
                        UIPasteboard.general.string = id
                    } label: {
                        Label(String(id.prefix(12)) + "…", systemImage: "doc.on.doc")
                            .labelStyle(.titleAndIcon)
                            .font(.caption.monospaced())
                    }
                    .accessibilityLabel("Copy your iCloud ID")
                }
            }
        }
    }

    /// Each group you run, then a button to create another.
    @ViewBuilder
    private var hostedSection: some View {
        ForEach(sync.hostedChoirs) { choir in
            Section {
                LabeledContent(choir.name) {
                    Text(choir.memberCount == 1 ? "1 member" : "\(choir.memberCount) members")
                }
                Button {
                    Task { await ChoirSharingPresenter.shared.present(library: choir.id) }
                } label: {
                    Label("Share Link and Manage People", systemImage: "person.crop.circle.badge.plus")
                }
                Button {
                    renameText = choir.name
                    choirToRename = choir
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    choirToDelete = choir
                } label: {
                    Label("Delete Group", systemImage: "trash")
                }
            } header: {
                if choir.id == sync.hostedChoirs.first?.id {
                    Text(sync.hostedChoirs.count == 1 ? "Your Shared Group" : "Your Shared Groups")
                }
            }
        }
        Section {
            Button {
                if appState.pro.isPro {
                    newChoirName = ""
                    showingCreate = true
                } else {
                    showingPaywall = true
                }
            } label: {
                Label(appState.pro.isPro ? "Create Shared Group" : "Create Shared Group (Pro)",
                      systemImage: "person.3")
            }
            .disabled(!sync.demoMode && sync.accountStatus != .available)
        } header: {
            if sync.hostedChoirs.isEmpty { Text("Your Shared Groups") }
        } footer: {
            Text("Share music and lists such as \"Evensong – Advent Sunday\" or \"Spring Concert\" with a choir, band or orchestra. You can run several groups, each with its own music, lists and link. Everyone keeps a full copy for rehearsal. Anyone you send a group's link to can join and view; only you can change its music and lists. Your markings on group music are shared with everyone as the director's markings; members' own markings stay private. Hosting needs Pro; joining is free.")
        }
    }

    private var joinedSection: some View {
        Section {
            Toggle("Show Director's Markings", isOn: $showDirectorMarkings)
            ForEach(sync.joinedChoirs) { choir in
                VStack(alignment: .leading, spacing: 2) {
                    Text(choir.name)
                    Text([choir.canEdit ? "Editor" : "Member", choir.ownerName.map { "run by \($0)" }]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .swipeActions {
                    Button("Leave", role: .destructive) { choirToLeave = choir }
                }
                .contextMenu {
                    Button("Leave Group", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                        choirToLeave = choir
                    }
                }
            }
        } header: {
            Text("Groups You've Joined")
        } footer: {
            Text("The group's director (its owner) can mark up the music for everyone. Their markings appear under yours and can't be changed here. Your own markings stay private.")
        }
    }

    private func createChoir() {
        let name = newChoirName.trimmed.isEmpty ? "Shared Group" : newChoirName.trimmed
        run {
            let choir = try await sync.createChoir(named: name)
            await ChoirSharingPresenter.shared.present(library: choir.id)
        }
    }

    private func run(_ work: @escaping () async throws -> Void) {
        isWorking = true
        Task {
            do {
                try await work()
            } catch {
                errorMessage = error.localizedDescription
            }
            isWorking = false
        }
    }
}

/// A small cloud icon in the sidebar showing sync activity.
struct SyncStatusIcon: View {
    @Environment(CloudSync.self) private var sync

    var body: some View {
        Group {
            if !sync.isSupported || !sync.isEnabled {
                Image(systemName: "icloud.slash")
            } else if sync.problem != nil || sync.accountStatus == .noAccount {
                Image(systemName: "exclamationmark.icloud")
                    .foregroundStyle(.orange)
            } else if sync.isFetching || sync.isSending || sync.pendingChanges > 0 {
                Image(systemName: "arrow.triangle.2.circlepath.icloud")
            } else {
                Image(systemName: "checkmark.icloud")
            }
        }
        .accessibilityLabel("iCloud and Groups")
    }
}

/// Recent sync activity, to copy and send when something isn't syncing.
struct SyncLogView: View {
    @Environment(CloudSync.self) private var sync

    var body: some View {
        let text = sync.log.joined(separator: "\n")
        ScrollView {
            Text(text.isEmpty ? "Nothing logged yet." : text)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .navigationTitle("Sync Log")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Copy", systemImage: "doc.on.doc") {
                    UIPasteboard.general.string = "\(AppConfig.displayName) \(AppConfig.version) on \(UIDevice.current.model)\n" + text
                }
                ShareLink(item: text)
                Button("Clear", systemImage: "trash", role: .destructive) { sync.clearLog() }
            }
        }
    }
}

/// A small banner showing uploads and downloads while they run, so a long
/// first sync doesn't look stuck.
struct SyncProgressBanner: View {
    @Environment(CloudSync.self) private var sync

    private var uploading: Bool {
        sync.isEnabled && sync.hasDownloadedOnce && sync.pendingChanges > 0
            && sync.scoresInICloud < sync.scoresHere
    }

    private var downloading: Bool {
        sync.isEnabled && sync.isFetching && sync.pdfsReceived > 0
    }

    var body: some View {
        Group {
            if uploading {
                banner(icon: "icloud.and.arrow.up") {
                    Text("Uploading to iCloud: \(sync.scoresInICloud) of \(sync.scoresHere) scores")
                        .font(.footnote.weight(.semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .fixedSize()
                    ProgressView(value: Double(sync.scoresInICloud), total: Double(max(sync.scoresHere, 1)))
                        .frame(width: 200)
                }
            } else if downloading {
                banner(icon: "icloud.and.arrow.down") {
                    Text("Downloading from iCloud: \(sync.pdfsReceived) score\(sync.pdfsReceived == 1 ? "" : "s") received")
                        .font(.footnote.weight(.semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .fixedSize()
                    ProgressView()
                        .progressViewStyle(.linear)
                        .frame(width: 200)
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: uploading)
        .animation(.easeInOut(duration: 0.2), value: downloading)
    }

    private func banner<Content: View>(icon: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 4) { content() }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
        .accessibilityElement(children: .combine)
    }
}
