import SwiftUI

extension View {
    /// A centred "are you sure?" alert for deleting one or more scores. Shows
    /// while `scores` is not empty; clears it when dismissed.
    func deleteConfirmation(for scores: Binding<[Score]>, onConfirm: @escaping ([Score]) -> Void) -> some View {
        modifier(DeleteScoresAlert(scores: scores, onConfirm: onConfirm))
    }
}

private struct DeleteScoresAlert: ViewModifier {
    @Binding var scores: [Score]
    let onConfirm: ([Score]) -> Void

    private var title: String {
        if scores.count == 1 {
            return "Delete \u{201C}\(scores[0].displayTitle)\u{201D}?"
        }
        return "Delete \(scores.count) Scores?"
    }

    private var message: String {
        let annotated = scores.filter { AnnotationStore().hasAnnotations(for: $0.id) }.count
        var text = scores.count == 1
            ? "This removes the PDF from this device, with its details and its place in any setlists."
            : "This removes these PDFs from this device, with their details and their places in any setlists."
        if annotated > 0 {
            text += annotated == 1 && scores.count == 1
                ? " Its annotations will be lost."
                : " Annotations on \(annotated) of them will be lost."
        }
        return text + " This can't be undone."
    }

    func body(content: Content) -> some View {
        content.alert(
            title,
            isPresented: Binding(get: { !scores.isEmpty }, set: { if !$0 { scores = [] } })
        ) {
            Button(scores.count == 1 ? "Delete" : "Delete \(scores.count)", role: .destructive) {
                let toDelete = scores
                scores = []
                onConfirm(toDelete)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(message)
        }
    }
}
