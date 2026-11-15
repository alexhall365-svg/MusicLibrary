import Foundation

struct MatchCandidate: Equatable, Sendable {
    let id: UUID
    let sha256: String
    let fileName: String
}

struct MatchResult: Equatable {
    /// Entry index → matched score id.
    var matched: [Int: UUID] = [:]
    /// Indices of entries with no match.
    var unmatched: [Int] = []
}

/// Matches exchange entries to scores: by content hash, then by app id, then by
/// file name (only when exactly one score has that name).
enum MetadataMatcher {
    static func match(_ entries: [ExchangeEntry], against candidates: [MatchCandidate]) -> MatchResult {
        var byHash: [String: UUID] = [:]
        var byName: [String: [UUID]] = [:]
        let ids = Set(candidates.map(\.id))
        for candidate in candidates {
            let hash = candidate.sha256.lowercased()
            if !hash.isEmpty && byHash[hash] == nil { byHash[hash] = candidate.id }
            byName[normalizedName(candidate.fileName), default: []].append(candidate.id)
        }

        var result = MatchResult()
        for (index, entry) in entries.enumerated() {
            if let hash = entry.sha256?.trimmed.lowercased(), !hash.isEmpty, let id = byHash[hash] {
                result.matched[index] = id
            } else if let text = entry.id?.trimmed, let id = UUID(uuidString: text), ids.contains(id) {
                result.matched[index] = id
            } else if let file = entry.file, let found = byName[normalizedName(file)], found.count == 1 {
                result.matched[index] = found[0]
            } else {
                result.unmatched.append(index)
            }
        }
        return result
    }

    static func normalizedName(_ fileName: String) -> String {
        var name = (fileName.trimmed as NSString).lastPathComponent.lowercased()
        if name.hasSuffix(".pdf") { name.removeLast(4) }
        return name.trimmed
    }
}
