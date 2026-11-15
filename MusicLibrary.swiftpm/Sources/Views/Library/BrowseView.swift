import SwiftUI
import SwiftData

/// Lists composers, genres, voicings or tags, each leading to its scores.
struct BrowseView: View {
    let kind: FacetKind
    @Query private var scores: [Score]

    var body: some View {
        let values = LibraryFilter.facetValues(kind, in: scores)
        List(values) { item in
            NavigationLink(value: Facet(kind: kind, value: item.value)) {
                HStack {
                    Text(item.value)
                    Spacer()
                    Text("\(item.count)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .overlay {
            if values.isEmpty {
                ContentUnavailableView(
                    "Nothing to browse yet",
                    systemImage: kind.systemImage,
                    description: Text("Add \(kind.label.lowercased()) details to your scores to browse them here.")
                )
            }
        }
        .navigationTitle(kind.pluralLabel)
        .navigationDestination(for: Facet.self) { facet in
            ScoreCollectionView(scope: .facet(facet))
        }
    }
}
