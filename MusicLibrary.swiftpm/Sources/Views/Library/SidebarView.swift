import SwiftUI
import SwiftData

struct SidebarView: View {
    @Binding var selection: SidebarItem?
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Setlist.name) private var setlists: [Setlist]
    @Query private var scores: [Score]

    @State private var showingNewSetlist = false
    @State private var newSetlistName = ""
    @State private var setlistToRename: Setlist?
    @State private var renameText = ""
    @State private var setlistToDelete: Setlist?
    @State private var showingPaywall = false
    @State private var showingSync = false
    @State private var newListLibrary: String?
    @Environment(AppState.self) private var appState
    @Environment(CloudSync.self) private var sync

    private var personalSetlists: [Setlist] { setlists.filter { $0.cloudLibrary == nil } }

    var body: some View {
        List(selection: $selection) {
            Section("Library") {
                NavigationLink(value: SidebarItem.allScores) {
                    Label("All Scores", systemImage: "music.note.list")
                        .badge(scores.filter(\.isPersonal).count)
                }
                NavigationLink(value: SidebarItem.recent) {
                    Label("Recently Opened", systemImage: "clock")
                }
                NavigationLink(value: SidebarItem.needsDetails) {
                    Label("Needs Details", systemImage: "questionmark.square.dashed")
                        .badge(scores.filter { $0.needsAttention && sync.canEdit($0) }.count)
                }
            }

            Section("Browse By") {
                ForEach(FacetKind.allCases) { kind in
                    NavigationLink(value: SidebarItem.browse(kind)) {
                        Label(kind.pluralLabel, systemImage: kind.systemImage)
                    }
                }
            }

            if sync.isSupported && sync.isEnabled && !sync.choirs.isEmpty {
                ForEach(sync.choirs) { choir in
                    choirSection(choir)
                }
            }

            Section("Setlists") {
                ForEach(personalSetlists) { setlist in
                    NavigationLink(value: SidebarItem.setlist(setlist.id)) {
                        Label(setlist.name, systemImage: "list.number")
                            .badge(setlist.entries?.count ?? 0)
                    }
                    .contextMenu {
                        Button("Rename…", systemImage: "pencil") {
                            renameText = setlist.name
                            setlistToRename = setlist
                        }
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            setlistToDelete = setlist
                        }
                    }
                }
                Button {
                    newSetlistName = ""
                    showingNewSetlist = true
                } label: {
                    Label("New Setlist", systemImage: "plus")
                }
            }

            Section("Tools") {
                Button {
                    showingSync = true
                } label: {
                    Label {
                        Text("iCloud & Groups")
                    } icon: {
                        SyncStatusIcon()
                    }
                }
                NavigationLink(value: SidebarItem.labelling) {
                    Label("Auto-Label", systemImage: "sparkles")
                }
                NavigationLink(value: SidebarItem.duplicates) {
                    Label("Find Duplicates", systemImage: "doc.on.doc")
                }
                Button {
                    showingPaywall = true
                } label: {
                    Label(appState.pro.isPro ? "Pro Unlocked" : "Unlock Pro",
                          systemImage: appState.pro.isPro ? "checkmark.seal" : "star.circle")
                }
            }
        }
        .navigationTitle(AppConfig.displayName)
        .sheet(isPresented: $showingPaywall) { PaywallView() }
        .sheet(isPresented: $showingSync) { SyncSettingsView() }
        .refreshable { await sync.syncNow() }
        .alert("New Group List", isPresented: Binding(
            get: { newListLibrary != nil }, set: { if !$0 { newListLibrary = nil } })
        ) {
            TextField("Name", text: $newSetlistName)
            Button("Create") {
                if let library = newListLibrary {
                    let setlist = LibraryActions.createSetlist(named: newSetlistName, in: library, context: modelContext)
                    selection = .setlist(setlist.id)
                }
                newListLibrary = nil
            }
            Button("Cancel", role: .cancel) { newListLibrary = nil }
        } message: {
            Text("For example \"Evensong – Advent Sunday\" or \"Christmas season 2026\". Everyone in the group gets it.")
        }
        .alert("New Setlist", isPresented: $showingNewSetlist) {
            TextField("Name", text: $newSetlistName)
            Button("Create") {
                let setlist = LibraryActions.createSetlist(named: newSetlistName, context: modelContext)
                selection = .setlist(setlist.id)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("For example \"Evensong 21 December\".")
        }
        .alert(
            "Rename Setlist",
            isPresented: Binding(get: { setlistToRename != nil }, set: { if !$0 { setlistToRename = nil } })
        ) {
            TextField("Name", text: $renameText)
            Button("Rename") {
                if let setlist = setlistToRename, !renameText.trimmed.isEmpty {
                    setlist.name = renameText.trimmed
                    try? modelContext.save()
                }
                setlistToRename = nil
            }
            Button("Cancel", role: .cancel) { setlistToRename = nil }
        }
        .alert(
            "Delete \u{201C}\(setlistToDelete?.name ?? "")\u{201D}?",
            isPresented: Binding(get: { setlistToDelete != nil }, set: { if !$0 { setlistToDelete = nil } })
        ) {
            Button("Delete Setlist", role: .destructive) {
                if let setlist = setlistToDelete {
                    if selection == .setlist(setlist.id) { selection = .allScores }
                    modelContext.delete(setlist)
                    try? modelContext.save()
                }
                setlistToDelete = nil
            }
            Button("Cancel", role: .cancel) { setlistToDelete = nil }
        } message: {
            if setlistToDelete?.cloudLibrary != nil {
                Text("The list is removed for everyone in the group. The music stays in the group.")
            } else {
                Text("The scores stay in your library.")
            }
        }
    }

    @ViewBuilder
    private func choirSection(_ choir: ChoirInfo) -> some View {
        let canEdit = sync.canEdit(choir.id)
        Section {
            NavigationLink(value: SidebarItem.choir(choir.id)) {
                Label("Group Music", systemImage: "person.3")
                    .badge(scores.filter { $0.cloudLibrary == choir.id }.count)
            }
            ForEach(setlists.filter { $0.cloudLibrary == choir.id }) { setlist in
                NavigationLink(value: SidebarItem.setlist(setlist.id)) {
                    Label(setlist.name, systemImage: "music.note.list")
                        .badge(setlist.entries?.count ?? 0)
                }
                .contextMenu {
                    Button("Copy to My Setlists", systemImage: "doc.on.doc") {
                        let copy = LibraryActions.copyToMySetlists(setlist, context: modelContext)
                        selection = .setlist(copy.id)
                    }
                    if canEdit {
                        Button("Rename…", systemImage: "pencil") {
                            renameText = setlist.name
                            setlistToRename = setlist
                        }
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            setlistToDelete = setlist
                        }
                    }
                }
            }
            if canEdit {
                Button {
                    newSetlistName = ""
                    newListLibrary = choir.id
                } label: {
                    Label("New Group List", systemImage: "plus")
                }
            }
        } header: {
            Text(choir.name)
        } footer: {
            if !canEdit {
                Text("Shared with you\(choir.ownerName.map { " by \($0)" } ?? ""). View only.")
            }
        }
    }
}
