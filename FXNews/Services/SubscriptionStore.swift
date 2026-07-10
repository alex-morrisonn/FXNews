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
    private(set) var productDiagnostics: ProductLoadDiagnostics?
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

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "FXNews", category: "SubscriptionStore")
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
            let fetchedProducts = try await Product.products(for: SubscriptionProduct.identifiers)
            let returnedProductIDs = Set(fetchedProducts.map(\.id))
            let missingProductIDs = SubscriptionProduct.identifiers.filter { !returnedProductIDs.contains($0) }
            let legacyResult = missingProductIDs.isEmpty ? nil : await LegacyProductLookup.fetch(productIDs: SubscriptionProduct.identifiers)

            products = fetchedProducts
            unavailableProductIDs = missingProductIDs
            productDiagnostics = ProductLoadDiagnostics(
                requestedProductIDs: SubscriptionProduct.identifiers,
                storeKitProductIDs: fetchedProducts.map(\.id),
                legacyProductIDs: legacyResult?.productIDs ?? [],
                invalidProductIDs: legacyResult?.invalidProductIDs ?? [],
                bundleIdentifier: Bundle.main.bundleIdentifier ?? "Unknown",
                storefrontCountryCode: await currentStorefrontCountryCode(),
                errorMessage: legacyResult?.errorMessage
            )
            purchaseMessage = nil

            if fetchedProducts.isEmpty {
                logger.error("StoreKit returned no subscription products. Requested: \(SubscriptionProduct.identifiers.joined(separator: ", "), privacy: .public)")
            } else if !missingProductIDs.isEmpty {
                logger.warning("StoreKit did not return subscription products: \(missingProductIDs.joined(separator: ", "), privacy: .public)")
            }
        } catch {
            let legacyResult = await LegacyProductLookup.fetch(productIDs: SubscriptionProduct.identifiers)

            products = []
            unavailableProductIDs = SubscriptionProduct.identifiers
            productDiagnostics = ProductLoadDiagnostics(
                requestedProductIDs: SubscriptionProduct.identifiers,
                storeKitProductIDs: [],
                legacyProductIDs: legacyResult.productIDs,
                invalidProductIDs: legacyResult.invalidProductIDs,
                bundleIdentifier: Bundle.main.bundleIdentifier ?? "Unknown",
                storefrontCountryCode: await currentStorefrontCountryCode(),
                errorMessage: legacyResult.errorMessage ?? error.localizedDescription
            )
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

    private func currentStorefrontCountryCode() async -> String {
        if let storefront = await Storefront.current {
            return storefront.countryCode
        }

        return "Unavailable"
    }
}

struct ProductLoadDiagnostics: Equatable {
    let requestedProductIDs: [String]
    let storeKitProductIDs: [String]
    let legacyProductIDs: [String]
    let invalidProductIDs: [String]
    let bundleIdentifier: String
    let storefrontCountryCode: String
    let errorMessage: String?
}

private struct LegacyProductLookupResult {
    let productIDs: [String]
    let invalidProductIDs: [String]
    let errorMessage: String?
}

private final class LegacyProductLookup: NSObject, SKProductsRequestDelegate {
    private let productIDs: [String]
    private var request: SKProductsRequest?
    private var continuation: CheckedContinuation<LegacyProductLookupResult, Never>?

    init(productIDs: [String]) {
        self.productIDs = productIDs
    }

    static func fetch(productIDs: [String]) async -> LegacyProductLookupResult {
        let lookup = LegacyProductLookup(productIDs: productIDs)
        return await lookup.fetch()
    }

    private func fetch() async -> LegacyProductLookupResult {
        await withCheckedContinuation { continuation in
            self.continuation = continuation

            let request = SKProductsRequest(productIdentifiers: Set(productIDs))
            self.request = request
            request.delegate = self
            request.start()
        }
    }

    func productsRequest(_ request: SKProductsRequest, didReceive response: SKProductsResponse) {
        finish(
            productIDs: response.products.map(\.productIdentifier),
            invalidProductIDs: response.invalidProductIdentifiers,
            errorMessage: nil
        )
    }

    func request(_ request: SKRequest, didFailWithError error: any Error) {
        finish(
            productIDs: [],
            invalidProductIDs: [],
            errorMessage: error.localizedDescription
        )
    }

    private func finish(productIDs: [String], invalidProductIDs: [String], errorMessage: String?) {
        let result = LegacyProductLookupResult(
            productIDs: productIDs.sorted(),
            invalidProductIDs: invalidProductIDs.sorted(),
            errorMessage: errorMessage
        )

        continuation?.resume(returning: result)
        continuation = nil
        request?.delegate = nil
        request = nil
    }
}
