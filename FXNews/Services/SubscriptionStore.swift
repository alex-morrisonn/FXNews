import Foundation
import Observation
import StoreKit

@MainActor
@Observable
final class SubscriptionStore {
    private(set) var products: [Product] = []
    private(set) var purchasedProductIDs: Set<String> = []
    private(set) var isLoadingProducts = false
    private(set) var purchaseMessage: String?

    #if DEBUG
    var debugOverridesProAccess: Bool {
        didSet { UserDefaults.standard.set(debugOverridesProAccess, forKey: Self.debugOverridesProAccessKey) }
    }
    #endif

    #if DEBUG
    private static let debugOverridesProAccessKey = "debug.subscription.overridesProAccess"
    #endif

    private var updatesTask: Task<Void, Never>?

    var hasProAccess: Bool {
        #if DEBUG
        if debugOverridesProAccess {
            return true
        }
        #endif

        return !purchasedProductIDs.isDisjoint(with: Set(SubscriptionProduct.identifiers))
    }

    var sortedProducts: [Product] {
        products.sorted { lhs, rhs in
            let lhsIndex = SubscriptionProduct.identifiers.firstIndex(of: lhs.id) ?? Int.max
            let rhsIndex = SubscriptionProduct.identifiers.firstIndex(of: rhs.id) ?? Int.max
            return lhsIndex < rhsIndex
        }
    }

    init() {
        #if DEBUG
        self.debugOverridesProAccess = UserDefaults.standard.bool(forKey: Self.debugOverridesProAccessKey)
        #endif
        updatesTask = listenForTransactions()
    }

    func load() async {
        await refreshEntitlements()
        await loadProducts()
    }

    func loadProducts() async {
        guard !isLoadingProducts else { return }

        isLoadingProducts = true
        defer { isLoadingProducts = false }

        do {
            products = try await Product.products(for: SubscriptionProduct.identifiers)
            purchaseMessage = nil
        } catch {
            purchaseMessage = "Unable to load subscription options. Please try again later."
        }
    }

    func purchase(_ product: Product) async {
        do {
            let result = try await product.purchase()

            switch result {
            case let .success(.verified(transaction)):
                purchasedProductIDs.insert(transaction.productID)
                await transaction.finish()
                await refreshEntitlements()
                purchaseMessage = "FXNews Pro is active."
            case .success(.unverified):
                purchaseMessage = "The purchase could not be verified."
            case .pending:
                purchaseMessage = "The purchase is pending approval."
            case .userCancelled:
                break
            @unknown default:
                purchaseMessage = "The purchase could not be completed."
            }
        } catch {
            purchaseMessage = error.localizedDescription
        }
    }

    func restorePurchases() async {
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            purchaseMessage = hasProAccess ? "FXNews Pro restored." : "No active FXNews Pro subscription was found."
        } catch {
            purchaseMessage = error.localizedDescription
        }
    }

    func clearMessage() {
        purchaseMessage = nil
    }

    func refreshEntitlements() async {
        var activeProductIDs: Set<String> = []

        for await result in Transaction.currentEntitlements {
            guard case let .verified(transaction) = result else {
                continue
            }

            if SubscriptionProduct.identifiers.contains(transaction.productID),
               transaction.revocationDate == nil {
                activeProductIDs.insert(transaction.productID)
            }
        }

        purchasedProductIDs = activeProductIDs
    }

    private func listenForTransactions() -> Task<Void, Never> {
        Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }

                if case let .verified(transaction) = result {
                    await transaction.finish()
                }

                await self.refreshEntitlements()
            }
        }
    }
}
