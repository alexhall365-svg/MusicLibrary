import SwiftUI
import CloudKit

/// "iCloud & Choir": sync with your own devices, and the Choir Library.
struct SyncSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Environment(CloudSync.self) private var sync
    @State private var bytesUsed: Int64 = 0
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
                if !sync.isSupported {
                    Section {
                        Label("iCloud sync and the Choir Library work in the TestFlight and App Store versions of \(AppConfig.displayName). This build (for example from Swift Playgrounds) keeps everything on this device.", systemImage: "icloud.slash")
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
                        Text("Your library and any Choir Library you host count against your iCloud storage (5 GB free). Choirs you join use their owner's storage, not yours.")
                    }

                    if sync.isEnabled {
                        hostedSection
                        if !sync.joinedChoirs.isEmpty { joinedSection }
                    }
                }
            }
            .navigationTitle("iCloud & Choir")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { bytesUsed = sync.iCloudBytesUsed() }
            .sheet(isPresented: $showingPaywall) { PaywallView() }
            .alert("New Choir Library", isPresented: $showingCreate) {
                TextField("Choir name", text: $newChoirName)
                Button("Create") { createChoir() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("For example \"St Mary's Choir\". You can then add music and lists, and invite the choir.")
            }
            .alert("Rename Choir Library", isPresented: Binding(
                get: { choirToRename != nil }, set: { if !$0 { choirToRename = nil } })
            ) {
                TextField("Choir name", text: $renameText)
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
                Button("Delete Choir Library", role: .destructive) {
                    if let choir = choirToDelete { sync.deleteHostedChoir(choir.id) }
                    choirToDelete = nil
                }
            } message: {
                Text("The choir's music and lists are removed from every member's devices. You keep them: they move into your own library.")
            }
            .confirmationDialog(
                "Leave \"\(choirToLeave?.name ?? "")\"?",
                isPresented: Binding(get: { choirToLeave != nil }, set: { if !$0 { choirToLeave = nil } }),
                titleVisibility: .visible
            ) {
                Button("Leave Choir", role: .destructive) {
                    if let choir = choirToLeave { run { try await sync.leaveChoir(choir.id) } }
                    choirToLeave = nil
                }
            } message: {
                Text("The choir's music and your annotations on it are removed from your devices. Your own library isn't affected.")
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
            } else if sync.pendingChanges == 0 && sync.accountStatus == .available {
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
        if sync.isFetching { return "Checking for changes…" }
        if sync.pendingChanges > 0 {
            return "\(sync.pendingChanges) change\(sync.pendingChanges == 1 ? "" : "s") to upload"
        }
        if let last = sync.lastSync {
            return "Up to date · \(last.formatted(.relative(presentation: .named)))"
        }
        return "Waiting to sync"
    }

    @ViewBuilder
    private var hostedSection: some View {
        Section {
            if let choir = sync.hostedChoir {
                LabeledContent(choir.name) {
                    Text(choir.memberCount == 1 ? "1 member" : "\(choir.memberCount) members")
                }
                Button {
                    Task { await ChoirSharingPresenter.shared.present(library: choir.id) }
                } label: {
                    Label("Invite and Manage People", systemImage: "person.crop.circle.badge.plus")
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
                    Label("Delete Choir Library", systemImage: "trash")
                }
            } else {
                Button {
                    if appState.pro.isPro {
                        newChoirName = ""
                        showingCreate = true
                    } else {
                        showingPaywall = true
                    }
                } label: {
                    Label(appState.pro.isPro ? "Create Choir Library" : "Create Choir Library (Pro)",
                          systemImage: "person.3")
                }
                .disabled(sync.accountStatus != .available)
            }
        } header: {
            Text("Your Choir Library")
        } footer: {
            Text("Share music and lists such as \"Evensong – Advent Sunday\" with your choir. Everyone keeps a full copy for rehearsal. In \"Invite and Manage People\", choose \"Can make changes\" for editors (for example a deputy); everyone else can only view. Annotations always stay private to each person. Hosting needs Pro; joining is free.")
        }
    }

    private var joinedSection: some View {
        Section("Choirs You've Joined") {
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
                    Button("Leave Choir", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                        choirToLeave = choir
                    }
                }
            }
        }
    }

    private func createChoir() {
        let name = newChoirName.trimmed.isEmpty ? "Choir Library" : newChoirName.trimmed
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
        .accessibilityLabel("iCloud and Choir")
    }
}
