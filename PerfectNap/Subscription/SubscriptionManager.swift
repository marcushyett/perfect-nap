import Foundation
import StoreKit

/// Owns the StoreKit 2 subscription state. `isPremium` reflects this user's *own* entitlement plus a
/// complimentary unlock for TestFlight / sandbox / DEBUG builds, so testers and developers are never
/// gated. Partner-of-a-subscriber access (one subscription per household) is layered on top in
/// `SleepStore` via the shared baby's `ownerHasPremium` flag — StoreKit entitlements can't cross
/// Apple IDs, so that signal travels through CloudKit instead.
@MainActor
@Observable
final class SubscriptionManager {
    static let shared = SubscriptionManager()

    static let monthlyID = "com.marcushyett.perfectnap.premium.monthly"
    static let annualID = "com.marcushyett.perfectnap.premium.annual"
    static let productIDs = [monthlyID, annualID]

    private(set) var products: [Product] = []
    private(set) var hasActiveEntitlement = false
    private(set) var isLoading = false

    private var updatesTask: Task<Void, Never>?

    /// TestFlight, sandbox, and DEBUG builds unlock Premium for free (testers/devs aren't charged).
    static let isComplimentary: Bool = {
        #if DEBUG
        return true
        #else
        if let url = Bundle.main.appStoreReceiptURL, url.lastPathComponent == "sandboxReceipt" { return true }
        return false
        #endif
    }()

    /// This user's own Premium access (their purchase, or a complimentary tester/dev build).
    var isPremium: Bool { Self.isComplimentary || hasActiveEntitlement }

    var monthly: Product? { products.first { $0.id == Self.monthlyID } }
    var annual: Product? { products.first { $0.id == Self.annualID } }

    private init() {
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                if case .verified(let txn) = update { await txn.finish() }
                await self?.refreshEntitlements()
            }
        }
        Task { await loadProducts(); await refreshEntitlements() }
    }

    func loadProducts() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let loaded = try await Product.products(for: Self.productIDs)
            products = loaded.sorted { $0.price < $1.price }
        } catch {
            #if DEBUG
            print("StoreKit product load failed: \(error)")
            #endif
        }
    }

    func refreshEntitlements() async {
        var active = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let txn) = result else { continue }
            if Self.productIDs.contains(txn.productID), txn.revocationDate == nil { active = true }
        }
        if hasActiveEntitlement != active { hasActiveEntitlement = active }
    }

    /// Returns true if the purchase completed and Premium is now active.
    @discardableResult
    func purchase(_ product: Product) async -> Bool {
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let txn) = verification {
                    await txn.finish()
                    await refreshEntitlements()
                    return isPremium
                }
                return false
            case .userCancelled, .pending:
                return false
            @unknown default:
                return false
            }
        } catch {
            return false
        }
    }

    func restore() async {
        try? await AppStore.sync()
        await refreshEntitlements()
    }
}
