import SwiftUI

/// The metadata form sections, shared by the score editor and the review screen.
struct MetadataFormFields: View {
    @Binding var metadata: ScoreMetadata
    @State private var newFieldName = ""
    @State private var showingAddField = false

    var body: some View {
        Section("Piece") {
            TextField("Title", text: $metadata.title)
            TextField("Composer", text: $metadata.composer, prompt: Text("e.g. Stanford, Charles Villiers"))
                .textInputAutocapitalization(.words)
            TextField("Catalogue number", text: $metadata.catalogueNumber, prompt: Text("e.g. BWV 227, K. 618, Op. 51 No. 1"))
                .autocorrectionDisabled()
        }
        Section("Performance") {
            TextField("Voicing / instrumentation", text: $metadata.scoring, prompt: Text("e.g. SATB + organ"))
                .autocorrectionDisabled()
            TextField("Key", text: $metadata.key, prompt: Text("e.g. G major"))
            TextField("Genre", text: $metadata.genre, prompt: Text("e.g. Anthem, Canticle, Motet"))
        }
        Section {
            TagsField(tags: $metadata.tags)
        } header: {
            Text("Tags")
        } footer: {
            Text("Separate tags with commas, e.g. Advent, Evensong, Latin.")
        }
        Section("Notes") {
            TextField("Notes", text: $metadata.notes, axis: .vertical)
                .lineLimit(2...8)
        }
        Section {
            ForEach(metadata.extra.keys.sorted(), id: \.self) { name in
                LabeledContent(name) {
                    TextField(name, text: Binding(
                        get: { metadata.extra[name] ?? "" },
                        set: { metadata.extra[name] = $0 }
                    ))
                    .multilineTextAlignment(.trailing)
                }
            }
            .onDelete { offsets in
                let names = metadata.extra.keys.sorted()
                for index in offsets { metadata.extra[names[index]] = nil }
            }
            Button("Add Custom Field", systemImage: "plus") {
                newFieldName = ""
                showingAddField = true
            }
        } header: {
            Text("Custom Fields")
        } footer: {
            Text("Add your own fields, such as Publisher or Copies Owned. Empty fields are removed when you save.")
        }
        .alert("Add Custom Field", isPresented: $showingAddField) {
            TextField("Field name", text: $newFieldName)
            Button("Add") {
                let name = newFieldName.trimmed
                if !name.isEmpty && metadata.extra[name] == nil {
                    metadata.extra[name] = ""
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

/// A comma-separated text field bound to a tag list.
struct TagsField: View {
    @Binding var tags: [String]
    @State private var text = ""

    var body: some View {
        TextField("Tags", text: $text, prompt: Text("Advent, Evensong"))
            .onAppear { text = tags.joined(separator: ", ") }
            .onChange(of: text) { _, newValue in
                tags = ScoreMetadata.parseTags(newValue)
            }
    }
}
