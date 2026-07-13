import Foundation
import Observation
import os
import StoreKit

@MainActor
@Observable
final class SubscriptionStore {
    private(set) var products: [Product] = []
    private(set) var purchasedProductIDs: Set<String> = []
    private(set) var unavailableProductIDs: [String] = []
    private(set) var isLoadingProducts = false
    private(set) var purchaseMessage: String?


    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "FXNews", category: "SubscriptionStore")
    private var updatesTask: Task<Void, Never>?
    private var storefrontUpdatesTask: Task<Void, Never>?

    var hasProAccess: Bool {
        !purchasedProductIDs.isDisjoint(with: Set(SubscriptionProduct.identifiers))
    }

    var sortedProducts: [Product] {
        products.sorted { lhs, rhs in
            let lhsIndex = SubscriptionProduct.identifiers.firstIndex(of: lhs.id) ?? Int.max
            let rhsIndex = SubscriptionProduct.identifiers.firstIndex(of: rhs.id) ?? Int.max
            return lhsIndex < rhsIndex
        }
    }

    init() {
        updatesTask = listenForTransactions()
        storefrontUpdatesTask = listenForStorefrontChanges()
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
            let fetchedProducts = try await Product.products(for: SubscriptionProduct.identifiers)
            let returnedProductIDs = Set(fetchedProducts.map(\.id))
            let missingProductIDs = SubscriptionProduct.identifiers.filter { !returnedProductIDs.contains($0) }

            products = fetchedProducts
            unavailableProductIDs = missingProductIDs
            purchaseMessage = nil

            if fetchedProducts.isEmpty {
                logger.error("StoreKit returned no subscription products. Requested: \(SubscriptionProduct.identifiers.joined(separator: ", "), privacy: .public)")
            } else if !missingProductIDs.isEmpty {
                logger.warning("StoreKit did not return subscription products: \(missingProductIDs.joined(separator: ", "), privacy: .public)")
            }
        } catch {
            products = []
            unavailableProductIDs = SubscriptionProduct.identifiers
            logger.error("Unable to load subscription products: \(error.localizedDescription, privacy: .public)")
            purchaseMessage = "Unable to load subscription options. Please try again later."
        }
    }

    func purchase(_ product: Product) async {
        do {
            let result = try await product.purchase()
            await handlePurchaseResult(result, product: product)
        } catch {
            purchaseMessage = error.localizedDescription
        }
    }

    func handleStoreKitViewPurchaseCompletion(product: Product, result: Result<Product.PurchaseResult, any Error>) async {
        do {
            let purchaseResult = try result.get()
            await handlePurchaseResult(purchaseResult, product: product)
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

    private func handlePurchaseResult(_ result: Product.PurchaseResult, product: Product) async {
        switch result {
        case let .success(.verified(transaction)):
            purchasedProductIDs.insert(transaction.productID)
            await transaction.finish()
            await refreshEntitlements()
            purchaseMessage = "\(product.displayName) is active."
        case .success(.unverified):
            purchaseMessage = "The purchase could not be verified."
        case .pending:
            purchaseMessage = "The purchase is pending approval."
        case .userCancelled:
            break
        @unknown default:
            purchaseMessage = "The purchase could not be completed."
        }
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

    private func listenForStorefrontChanges() -> Task<Void, Never> {
        Task { [weak self] in
            for await _ in Storefront.updates {
                guard let self else { return }
                await self.loadProducts()
            }
        }
    }
}
