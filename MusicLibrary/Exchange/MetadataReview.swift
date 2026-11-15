import Foundation

struct FieldChange: Identifiable, Equatable {
    let field: MetadataField
    let oldValue: String
    let newValue: String
    let confidence: Double?
    /// Set for custom (extra) fields.
    var customName: String? = nil

    var id: String { customName.map { "extra.\($0)" } ?? field.rawValue }
    var label: String { customName ?? field.label }

    var isUncertain: Bool {
        (confidence ?? 1) < MetadataReviewBuilder.uncertaintyThreshold
    }
}

struct ReviewItem: Identifiable, Equatable {
    let id = UUID()
    let scoreID: UUID
    let fileName: String
    let before: ScoreMetadata
    var after: ScoreMetadata
    let confidence: [String: Double]
    let flags: [String]
    var include = true

    var changes: [FieldChange] {
        MetadataReviewBuilder.changes(from: before, to: after, confidence: confidence)
    }

    var needsAttention: Bool {
        !flags.isEmpty || changes.contains(where: \.isUncertain)
    }
}

struct MetadataReview: Identifiable {
    let id = UUID()
    var title: String
    var items: [ReviewItem]
    var unmatchedFiles: [String]
    var unchangedCount: Int
}

/// What the review builder needs to know about each score in the library.
struct ReviewSubject {
    let candidate: MatchCandidate
    let metadata: ScoreMetadata
}

enum MetadataReviewBuilder {
    static let uncertaintyThreshold = 0.7

    static func build(file: MetadataExchangeFile, subjects: [ReviewSubject], title: String) -> MetadataReview {
        let match = MetadataMatcher.match(file.scores, against: subjects.map(\.candidate))
        let byID = Dictionary(subjects.map { ($0.candidate.id, $0) }, uniquingKeysWith: { first, _ in first })

        var items: [ReviewItem] = []
        var unchanged = 0
        for (index, entry) in file.scores.enumerated() {
            guard let scoreID = match.matched[index], let subject = byID[scoreID] else { continue }
            let before = subject.metadata.normalized()
            let after = entry.metadata.applied(to: before)
            let flags = (entry.flags ?? []).map(\.trimmed).filter { !$0.isEmpty }
            if after == before && flags.isEmpty {
                unchanged += 1
                continue
            }
            var confidence = entry.confidence ?? [:]
            // Accept a couple of alternative names for confidence keys.
            if let value = confidence["catalogue"], confidence["catalogueNumber"] == nil {
                confidence["catalogueNumber"] = value
            }
            if let value = confidence["voicing"], confidence["scoring"] == nil {
                confidence["scoring"] = value
            }
            items.append(ReviewItem(
                scoreID: scoreID,
                fileName: subject.candidate.fileName,
                before: before,
                after: after,
                confidence: confidence,
                flags: flags
            ))
        }

        let unmatched = match.unmatched.map { index -> String in
            let entry = file.scores[index]
            return entry.file ?? entry.metadata.title ?? entry.sha256 ?? "Entry \(index + 1)"
        }
        return MetadataReview(title: title, items: items, unmatchedFiles: unmatched, unchangedCount: unchanged)
    }

    static func changes(from before: ScoreMetadata, to after: ScoreMetadata, confidence: [String: Double]) -> [FieldChange] {
        var result: [FieldChange] = MetadataField.allCases.compactMap { field in
            let old = field.value(in: before)
            let new = field.value(in: after)
            guard old != new else { return nil }
            return FieldChange(
                field: field, oldValue: old, newValue: new,
                confidence: confidence[field.rawValue] ?? confidence["*"])
        }
        let extraKeys = Set(before.extra.keys).union(after.extra.keys).sorted()
        for key in extraKeys where before.extra[key] != after.extra[key] {
            result.append(FieldChange(
                field: .notes, oldValue: before.extra[key] ?? "", newValue: after.extra[key] ?? "",
                confidence: confidence[key] ?? confidence["*"], customName: key))
        }
        return result
    }
}
