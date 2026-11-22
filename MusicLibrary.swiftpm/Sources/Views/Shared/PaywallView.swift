import SwiftUI
import StoreKit

/// Explains Pro and sells the one-time unlock.
struct PaywallView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var showingRedeem = false

    var body: some View {
        let pro = appState.pro
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    Image(systemName: pro.isPro ? "checkmark.seal.fill" : "sparkles")
                        .font(.system(size: 52))
                        .foregroundStyle(Color.accentColor)
                        .padding(.top, 12)
                        .accessibilityHidden(true)

                    VStack(spacing: 6) {
                        Text("\(AppConfig.displayName) Pro")
                            .font(.largeTitle.bold())
                            .multilineTextAlignment(.center)
                        Text(pro.isPro ? "Pro is unlocked. Thank you!" : "One payment. Yours for life. No subscription.")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        feature("sparkles", "Auto-label with Apple Intelligence",
                                "New imports fill in their own titles, composers and more, privately on your device.")
                        feature("person.3", "Host a shared group",
                                "Share music, lists and your markings with a choir, band or orchestra. Joining a group is always free.")
                        feature("doc.on.doc", "Find duplicates",
                                "Spot copies by name, text or how the page looks, and tidy up safely.")
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                    if !pro.isPro && pro.isBeta {
                        Text("Pro isn't available in the test version. Everything else works as normal.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    } else if !pro.isPro {
                        Button {
                            Task { await pro.purchase() }
                        } label: {
                            HStack {
                                if pro.isPurchasing { ProgressView().tint(.white) }
                                Text(pro.displayPrice.map { "Unlock Pro for \($0)" } ?? "Unlock Pro")
                                    .font(.headline)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(pro.isPurchasing)

                        HStack(spacing: 24) {
                            Button("Redeem Code") { showingRedeem = true }
                            Button("Restore Purchase") {
                                Task { await pro.restore() }
                            }
                        }
                        .font(.callout)
                    }

                    if let message = pro.message {
                        Text(message)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    Text("Reading, annotating, setlists and everything you need for rehearsals are free. Pro adds tools for managing large collections. Family Sharing is supported.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(24)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { if pro.product == nil { await pro.loadProduct() } } // retried each time Pro opens
            .offerCodeRedemption(isPresented: $showingRedeem) { result in
                Task { await pro.codeRedemptionFinished(result) }
            }
        }
    }

    private func feature(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 30)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
