import SwiftUI
import SwiftData

/// Shows every proposed change from an imported metadata file. Nothing is saved
/// until Apply is tapped; each score can be skipped or edited first.
struct MetadataReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var review: MetadataReview
    @State private var showOnlyAttention = false
    @State private var editingIndex: Int?

    init(review: MetadataReview) {
        _review = State(initialValue: review)
    }

    private var includedCount: Int { review.items.filter(\.include).count }
    private var attentionCount: Int { review.items.filter(\.needsAttention).count }

    private var visibleIndices: [Int] {
        review.items.indices.filter { !showOnlyAttention || review.items[$0].needsAttention }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(summary)
                        .font(.callout)
                    if attentionCount > 0 {
                        Picker("Show", selection: $showOnlyAttention) {
                            Text("All (\(review.items.count))").tag(false)
                            Text("Needs Checking (\(attentionCount))").tag(true)
                        }
                        .pickerStyle(.segmented)
                    }
                }

                Section {
                    ForEach(visibleIndices, id: \.self) { index in
                        ReviewItemRow(item: $review.items[index]) {
                            editingIndex = index
                        }
                    }
                }

                if !review.unmatchedFiles.isEmpty {
                    Section {
                        ForEach(review.unmatchedFiles, id: \.self) { name in
                            Text(name).foregroundStyle(.secondary)
                        }
                    } header: {
                        Text("Not Found in Your Library (\(review.unmatchedFiles.count))")
                    } footer: {
                        Text("Import these PDFs first, then import the details again.")
                    }
                }
            }
            .navigationTitle(review.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply \(includedCount)") { apply() }
                        .disabled(includedCount == 0)
                }
                ToolbarItem(placement: .bottomBar) {
                    HStack {
                        Button("Select All") { setAll(true) }
                        Spacer()
                        Button("Select None") { setAll(false) }
                    }
                }
            }
            .sheet(isPresented: Binding(get: { editingIndex != nil }, set: { if !$0 { editingIndex = nil } })) {
                if let index = editingIndex, review.items.indices.contains(index) {
                    ReviewEditSheet(item: $review.items[index])
                }
            }
        }
        .interactiveDismissDisabled()
    }

    private var summary: String {
        var parts = ["\(review.items.count) score\(review.items.count == 1 ? "" : "s") with changes."]
        if attentionCount > 0 { parts.append("\(attentionCount) need checking.") }
        if review.unchangedCount > 0 { parts.append("\(review.unchangedCount) already up to date.") }
        return parts.joined(separator: " ")
    }

    private func setAll(_ include: Bool) {
        for index in visibleIndices { review.items[index].include = include }
    }

    private func apply() {
        let scores = (try? modelContext.fetch(FetchDescriptor<Score>())) ?? []
        let byID = Dictionary(scores.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for item in review.items where item.include {
            byID[item.scoreID]?.metadata = item.after
        }
        try? modelContext.save()
        dismiss()
    }
}

private struct ReviewItemRow: View {
    @Binding var item: ReviewItem
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $item.include) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.after.title.isEmpty ? item.fileName : item.after.title)
                        .font(.headline)
                    Text(item.fileName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            ForEach(item.changes) { change in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(change.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 80, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        if !change.oldValue.isEmpty {
                            Text(change.oldValue)
                                .font(.caption)
                                .strikethrough()
                                .foregroundStyle(.secondary)
                        }
                        Text(change.newValue.isEmpty ? "(cleared)" : change.newValue)
                            .font(.callout)
                    }
                    Spacer(minLength: 4)
                    if let confidence = change.confidence {
                        ConfidenceBadge(value: confidence)
                    }
                }
            }

            ForEach(item.flags, id: \.self) { flag in
                Label(flag, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Button("Edit", systemImage: "pencil", action: onEdit)
                .font(.caption)
                .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
        .listRowBackground(item.needsAttention ? Color.orange.opacity(0.10) : nil)
        .opacity(item.include ? 1 : 0.55)
    }
}

private struct ConfidenceBadge: View {
    let value: Double

    var body: some View {
        Text("\(Int((value * 100).rounded()))%")
            .font(.caption2.weight(.semibold).monospacedDigit())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
            .accessibilityLabel("Confidence \(Int((value * 100).rounded())) percent")
    }

    private var color: Color {
        if value >= 0.85 { return .green }
        if value >= MetadataReviewBuilder.uncertaintyThreshold { return .blue }
        return .orange
    }
}

private struct ReviewEditSheet: View {
    @Binding var item: ReviewItem
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                MetadataFormFields(metadata: $item.after)
            }
            .navigationTitle(item.fileName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        item.after = item.after.normalized()
                        item.include = true
                        dismiss()
                    }
                }
            }
        }
    }
}
