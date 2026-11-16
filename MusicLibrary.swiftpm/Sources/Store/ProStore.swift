import Foundation
import Observation
import StoreKit

/// The one-time "Pro" unlock (StoreKit 2, non-consumable).
///
/// Debug builds (Swift Playgrounds, local development) always have Pro, so the
/// developer can use everything. TestFlight and App Store builds use the real
/// purchase; on TestFlight purchases are free test purchases.
@MainActor
@Observable
final class ProStore {
    nonisolated static let productID = "pro_unlock"
    nonisolated private static let cacheKey = "pro.unlocked"

    private(set) var isPro: Bool
    private(set) var product: Product?
    private(set) var isPurchasing = false
    var message: String?

    @ObservationIgnored private var updatesTask: Task<Void, Never>?

    nonisolated init() {
        #if DEBUG
        isPro = true
        #else
        isPro = UserDefaults.standard.bool(forKey: ProStore.cacheKey)
        #endif
    }

    /// The price as the App Store shows it, e.g. "£3.99".
    var displayPrice: String? { product?.displayPrice }

    func start() {
        guard updatesTask == nil else { return }
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                if case .verified(let transaction) = update {
                    await transaction.finish()
                    await self?.refreshEntitlement()
                }
            }
        }
        Task {
            await loadProduct()
            await refreshEntitlement()
        }
    }

    func loadProduct() async {
        do {
            product = try await Product.products(for: [ProStore.productID]).first
        } catch {
            product = nil
        }
    }

    func refreshEntitlement() async {
        #if !DEBUG
        var owned = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == ProStore.productID,
               transaction.revocationDate == nil {
                owned = true
            }
        }
        setPro(owned)
        #endif
    }

    func purchase() async {
        if product == nil { await loadProduct() }
        guard let product else {
            message = "The App Store isn't available right now. Check your connection and try again."
            return
        }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await transaction.finish()
                    setPro(true)
                    message = nil
                } else {
                    message = "The purchase couldn't be verified. Please try Restore Purchase."
                }
            case .pending:
                message = "Your purchase is waiting for approval (for example, Ask to Buy)."
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            message = error.localizedDescription
        }
    }

    /// Called after the App Store's code redemption sheet closes.
    func codeRedemptionFinished(_ result: Result<Void, Error>) async {
        switch result {
        case .success:
            await refreshEntitlement()
            if isPro {
                message = "Code redeemed. Pro is unlocked."
            }
        case .failure(let error):
            message = error.localizedDescription
        }
    }

    func restore() async {
        do {
            try await AppStore.sync()
        } catch {
            message = error.localizedDescription
            return
        }
        await refreshEntitlement()
        message = isPro ? nil : "No previous Pro purchase was found for this Apple Account."
    }

    private func setPro(_ value: Bool) {
        isPro = value
        UserDefaults.standard.set(value, forKey: ProStore.cacheKey)
    }
}
