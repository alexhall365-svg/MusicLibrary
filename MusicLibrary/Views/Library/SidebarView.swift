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

    var body: some View {
        List(selection: $selection) {
            Section("Library") {
                NavigationLink(value: SidebarItem.allScores) {
                    Label("All Scores", systemImage: "music.note.list")
                        .badge(scores.count)
                }
                NavigationLink(value: SidebarItem.recent) {
                    Label("Recently Opened", systemImage: "clock")
                }
                NavigationLink(value: SidebarItem.needsDetails) {
                    Label("Needs Details", systemImage: "questionmark.square.dashed")
                        .badge(scores.filter(\.needsLabels).count)
                }
            }

            Section("Browse By") {
                ForEach(FacetKind.allCases) { kind in
                    NavigationLink(value: SidebarItem.browse(kind)) {
                        Label(kind.pluralLabel, systemImage: kind.systemImage)
                    }
                }
            }

            Section("Setlists") {
                ForEach(setlists) { setlist in
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
                NavigationLink(value: SidebarItem.labelling) {
                    Label("Label with Claude", systemImage: "sparkles")
                }
            }
        }
        .navigationTitle(AppConfig.displayName)
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
        .confirmationDialog(
            "Delete \"\(setlistToDelete?.name ?? "")\"?",
            isPresented: Binding(get: { setlistToDelete != nil }, set: { if !$0 { setlistToDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete Setlist", role: .destructive) {
                if let setlist = setlistToDelete {
                    if selection == .setlist(setlist.id) { selection = .allScores }
                    modelContext.delete(setlist)
                    try? modelContext.save()
                }
                setlistToDelete = nil
            }
        } message: {
            Text("The scores stay in your library.")
        }
    }
}
