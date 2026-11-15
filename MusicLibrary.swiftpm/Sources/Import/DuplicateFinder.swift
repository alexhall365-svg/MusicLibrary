import Foundation

/// What the duplicate finder needs to know about each score.
struct DuplicateCandidate: Sendable, Equatable {
    let id: UUID
    let fileName: String
    let title: String
    let composer: String
    let pageCount: Int
    let sha256: String
    /// Text from the first pages, if known.
    let text: String?
    /// A tiny greyscale image of the first page (see `PageFingerprint`).
    let fingerprint: Data?
}

enum DuplicateReason: Int, CaseIterable, Comparable, Sendable {
    case identicalFile, sameName, similarName, sameText, samePage

    var label: String {
        switch self {
        case .identicalFile: return "Identical file"
        case .sameName: return "Same title"
        case .similarName: return "Similar title"
        case .sameText: return "Same text on first pages"
        case .samePage: return "First page looks the same"
        }
    }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

struct DuplicateGroup: Identifiable, Equatable, Sendable {
    let scoreIDs: [UUID]
    let reasons: [DuplicateReason]
    var id: String { scoreIDs.map(\.uuidString).sorted().joined(separator: "|") }
}

/// Finds groups of scores that are probably the same piece or file.
enum DuplicateFinder {
    static let textSimilarityThreshold = 0.75
    static let nameSimilarityThreshold = 0.8
    static let pageDifferenceThreshold = 0.04

    static func findGroups(_ candidates: [DuplicateCandidate], ignoredPairs: Set<String> = []) -> [DuplicateGroup] {
        let prepared = candidates.map(Prepared.init)
        var parent = Array(prepared.indices)
        func root(_ index: Int) -> Int {
            var index = index
            while parent[index] != index {
                parent[index] = parent[parent[index]]
                index = parent[index]
            }
            return index
        }

        var pairReasons: [(Int, Int, [DuplicateReason])] = []
        for i in prepared.indices {
            for j in (i + 1)..<prepared.count {
                if ignoredPairs.contains(pairKey(prepared[i].id, prepared[j].id)) { continue }
                let found = reasons(prepared[i], prepared[j])
                if !found.isEmpty {
                    pairReasons.append((i, j, found))
                    let (a, b) = (root(i), root(j))
                    if a != b { parent[b] = a }
                }
            }
        }

        var members: [Int: [Int]] = [:]
        for index in prepared.indices { members[root(index), default: []].append(index) }
        var reasonsByRoot: [Int: Set<DuplicateReason>] = [:]
        for (i, _, found) in pairReasons { reasonsByRoot[root(i), default: []].formUnion(found) }

        return members.values
            .filter { $0.count > 1 }
            .map { indices in
                DuplicateGroup(
                    scoreIDs: indices.map { prepared[$0].id },
                    reasons: (reasonsByRoot[root(indices[0])] ?? []).sorted())
            }
            .sorted { a, b in
                if a.reasons.first != b.reasons.first {
                    return (a.reasons.first ?? .samePage) < (b.reasons.first ?? .samePage)
                }
                return a.id < b.id
            }
    }

    static func pairKey(_ a: UUID, _ b: UUID) -> String {
        [a.uuidString, b.uuidString].sorted().joined(separator: "|")
    }

    // MARK: - Comparison

    private struct Prepared {
        let id: UUID
        let sha256: String
        let fileName: String
        let title: String
        let composer: String
        let titleTokens: Set<String>
        let numbers: Set<String>
        let pageCount: Int
        let words: Set<String>
        let fingerprint: [UInt8]?

        init(_ candidate: DuplicateCandidate) {
            id = candidate.id
            sha256 = candidate.sha256.lowercased()
            fileName = DuplicateFinder.normalizedName(candidate.fileName)
            title = DuplicateFinder.normalizedName(candidate.title)
            composer = DuplicateFinder.normalizedName(candidate.composer)
            let tokens = title.split(separator: " ").map(String.init)
            titleTokens = Set(tokens)
            numbers = Set(tokens.filter { $0.allSatisfy(\.isNumber) })
            pageCount = candidate.pageCount
            words = DuplicateFinder.words(in: candidate.text ?? "")
            fingerprint = candidate.fingerprint.map { Array($0) }
        }
    }

    private static func reasons(_ a: Prepared, _ b: Prepared) -> [DuplicateReason] {
        var result: [DuplicateReason] = []
        if !a.sha256.isEmpty && a.sha256 == b.sha256 {
            result.append(.identicalFile)
        }

        let composersMatch = a.composer.isEmpty || b.composer.isEmpty || a.composer == b.composer
        let sameFileName = !a.fileName.isEmpty && a.fileName == b.fileName
        let sameTitle = a.title.count >= 3 && a.title == b.title && composersMatch
        if sameFileName || sameTitle {
            result.append(.sameName)
        } else if composersMatch && a.titleTokens.count >= 2 && b.titleTokens.count >= 2
                    && a.numbers == b.numbers
                    && jaccard(a.titleTokens, b.titleTokens) >= nameSimilarityThreshold {
            result.append(.similarName)
        }

        let pagesClose = abs(a.pageCount - b.pageCount) <= 2
        if pagesClose && a.words.count >= 15 && b.words.count >= 15 {
            let smaller = Double(min(a.words.count, b.words.count))
            let larger = Double(max(a.words.count, b.words.count))
            if smaller / larger >= textSimilarityThreshold && jaccard(a.words, b.words) >= textSimilarityThreshold {
                result.append(.sameText)
            }
        }

        if a.pageCount == b.pageCount, let fa = a.fingerprint, let fb = b.fingerprint,
           let difference = PageFingerprint.difference(fa, fb), difference <= pageDifferenceThreshold {
            result.append(.samePage)
        }
        return result
    }

    // MARK: - Normalisation

    private static let copyMarkers: NSRegularExpression = {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: #"(\s*\(\d+\)|\s+copy(\s*\d+)?|\s*-\s*copy)+$"#, options: [.caseInsensitive])
    }()

    /// Lowercase, no accents, no ".pdf", no "copy"/"(1)" endings, punctuation as spaces.
    static func normalizedName(_ text: String) -> String {
        var name = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).trimmed
        if name.hasSuffix(".pdf") { name.removeLast(4) }
        name = copyMarkers.stringByReplacingMatches(
            in: name, options: [], range: NSRange(name.startIndex..., in: name), withTemplate: "")
        let cleaned = name.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
        return String(cleaned).split(separator: " ").joined(separator: " ")
    }

    static func words(in text: String) -> Set<String> {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        return Set(folded.split(whereSeparator: { !$0.isLetter }).map(String.init).filter { $0.count >= 3 })
    }

    static func jaccard(_ a: Set<String>, _ b: Set<String>) -> Double {
        guard !a.isEmpty || !b.isEmpty else { return 0 }
        return Double(a.intersection(b).count) / Double(a.union(b).count)
    }
}
