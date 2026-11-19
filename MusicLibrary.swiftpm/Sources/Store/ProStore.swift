import Foundation
import Observation
import StoreKit

/// The one-time "Pro" unlock (StoreKit 2, non-consumable).
///
/// Debug builds (Swift Playgrounds, local development) and TestFlight builds made
/// with "testers get Pro" (the TESTFLIGHT_PRO flag) always have Pro. Otherwise:
/// - The app's owners (iCloud IDs in the PRO_OWNERS build setting) always have Pro.
/// - In TestFlight, purchases are free test purchases, so they are blocked and
///   ignored: only owners have Pro there.
/// - App Store builds use the real one-time purchase.
@MainActor
@Observable
final class ProStore {
    nonisolated static let productID = "pro_unlock"
    nonisolated private static let cacheKey = "pro.unlocked"

    private(set) var isPro: Bool
    private(set) var product: Product?
    private(set) var isPurchasing = false
    /// True in TestFlight (and other test environments), where Pro can't be bought.
    private(set) var isBeta = false
    var message: String?

    @ObservationIgnored private var updatesTask: Task<Void, Never>?

    init() {
        #if DEBUG || TESTFLIGHT_PRO
        isPro = true
        #else
        isPro = UserDefaults.standard.bool(forKey: ProStore.cacheKey)
        #endif
    }

    /// The price as the App Store shows it, e.g. "£4.99".
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
        #if !DEBUG && !TESTFLIGHT_PRO
        isBeta = Self.blocksTestPurchases ? await Self.isTestEnvironment() : false
        let owner = await Self.isOwner()
        if isBeta {
            // Ignore free test purchases: in a beta only the owners have Pro.
            setPro(owner)
            return
        }
        var owned = owner
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
        guard !isBeta else {
            message = Self.betaMessage
            return
        }
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
        guard !isBeta else {
            message = Self.betaMessage
            return
        }
        do {
            try await AppStore.sync()
        } catch {
            message = error.localizedDescription
            return
        }
        await refreshEntitlement()
        message = isPro ? nil : "No previous Pro purchase was found for this Apple Account."
    }

    static let betaMessage = "Pro isn't available in the test version."

    /// YES in normal TestFlight builds. NO in the build submitted for App Review,
    /// whose reviewers must be able to make a test purchase.
    private static var blocksTestPurchases: Bool {
        (Bundle.main.object(forInfoDictionaryKey: "QuireBlockTestPurchases") as? String)?.uppercased() == "YES"
    }

    /// TestFlight and Xcode builds run against the App Store's test ("sandbox") environment.
    private static func isTestEnvironment() async -> Bool {
        if let result = try? await AppTransaction.shared, case .verified(let transaction) = result {
            return transaction.environment != .production
        }
        return Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
    }

    /// Whether the signed-in iCloud account is one of the app's owners.
    private static func isOwner() async -> Bool {
        let raw = Bundle.main.object(forInfoDictionaryKey: "QuireProOwners") as? String ?? ""
        let owners = Set(raw.split(whereSeparator: { $0 == "," || $0 == " " }).map(String.init))
        guard !owners.isEmpty, let id = await CloudSync.shared.currentUserID() else { return false }
        return owners.contains(id)
    }

    private func setPro(_ value: Bool) {
        isPro = value
        UserDefaults.standard.set(value, forKey: ProStore.cacheKey)
    }
}
