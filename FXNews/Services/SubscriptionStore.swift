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
    private(set) var subscriptionStatusMessage: String?
    private(set) var hasSubscriptionBillingIssue = false


    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "FXNews", category: "SubscriptionStore")
    private var updatesTask: Task<Void, Never>?

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
            await refreshSubscriptionStatus()

            if fetchedProducts.isEmpty {
                logger.error("StoreKit returned no subscription products. Requested: \(SubscriptionProduct.identifiers.joined(separator: ", "), privacy: .public)")
            } else if !missingProductIDs.isEmpty {
                logger.warning("StoreKit did not return subscription products: \(missingProductIDs.joined(separator: ", "), privacy: .public)")
            }
        } catch {
            products = []
            unavailableProductIDs = SubscriptionProduct.identifiers
            logger.error("Unable to load subscription products: \(error.localizedDescription, privacy: .public)")
            purchaseMessage = message(for: error, fallback: "Unable to load subscription options. Please try again later.")
        }
    }

    func purchase(_ product: Product) async {
        do {
            let result = try await product.purchase()
            await handlePurchaseResult(result, product: product)
        } catch {
            purchaseMessage = message(for: error, fallback: "The purchase could not be completed. Please try again.")
        }
    }

    func handleStoreKitViewPurchaseCompletion(product: Product, result: Result<Product.PurchaseResult, any Error>) async {
        do {
            let purchaseResult = try result.get()
            await handlePurchaseResult(purchaseResult, product: product)
        } catch {
            purchaseMessage = message(for: error, fallback: "The purchase could not be completed. Please try again.")
        }
    }

    func restorePurchases() async {
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            await refreshSubscriptionStatus()
            purchaseMessage = hasProAccess ? "FXNews Pro restored." : "No active FXNews Pro subscription was found."
        } catch {
            purchaseMessage = message(for: error, fallback: "Unable to restore purchases. Please try again.")
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
        await refreshSubscriptionStatus()
    }

    private func handlePurchaseResult(_ result: Product.PurchaseResult, product: Product) async {
        switch result {
        case let .success(.verified(transaction)):
            purchasedProductIDs.insert(transaction.productID)
            await transaction.finish()
            await refreshEntitlements()
            purchaseMessage = "\(product.displayName) is active."
        case let .success(.unverified(transaction, verificationError)):
            logger.error("Unverified transaction for \(transaction.productID, privacy: .public): \(String(describing: verificationError), privacy: .public)")
            await refreshEntitlements()
            purchaseMessage = "The purchase could not be verified."
        case .pending:
            await refreshEntitlements()
            purchaseMessage = "The purchase is pending approval."
        case .userCancelled:
            break
        @unknown default:
            await refreshEntitlements()
            purchaseMessage = "The purchase could not be completed."
        }
    }

    private func listenForTransactions() -> Task<Void, Never> {
        Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }

                if case let .verified(transaction) = result {
                    await transaction.finish()
                } else if case let .unverified(transaction, verificationError) = result {
                    self.logger.error("Unverified transaction update for \(transaction.productID, privacy: .public): \(String(describing: verificationError), privacy: .public)")
                }

                await self.refreshEntitlements()
            }
        }
    }

    private func refreshSubscriptionStatus() async {
        var statusMessage: String?
        var billingIssue = false

        for product in products {
            guard let subscription = product.subscription else {
                continue
            }

            do {
                let statuses = try await subscription.status
                for status in statuses {
                    switch status.state {
                    case .subscribed:
                        if statusMessage == nil, let renewalInfo = verifiedRenewalInfo(from: status), !renewalInfo.willAutoRenew {
                            statusMessage = "Your Pro plan remains active until the current period ends."
                        }
                    case .inGracePeriod:
                        billingIssue = true
                        statusMessage = "There is a billing issue, but Pro remains active during the grace period. Update payment details to avoid losing access."
                    case .inBillingRetryPeriod:
                        billingIssue = true
                        statusMessage = "There is a billing issue with your Pro subscription. Update payment details to restore access."
                    case .expired:
                        statusMessage = statusMessage ?? "Your previous Pro subscription has expired."
                    case .revoked:
                        statusMessage = "Your Pro subscription was refunded or revoked, so Pro access is no longer active."
                    default:
                        break
                    }
                }
            } catch {
                logger.warning("Unable to refresh subscription status for \(product.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }

        subscriptionStatusMessage = statusMessage
        hasSubscriptionBillingIssue = billingIssue
    }

    private func verifiedRenewalInfo(from status: Product.SubscriptionInfo.Status) -> Product.SubscriptionInfo.RenewalInfo? {
        guard case let .verified(renewalInfo) = status.renewalInfo else {
            return nil
        }

        return renewalInfo
    }

    private func message(for error: any Error, fallback: String) -> String? {
        if let storeKitError = error as? StoreKitError {
            return message(for: storeKitError, fallback: fallback)
        }

        let nsError = error as NSError
        if nsError.domain == SKErrorDomain, let skErrorCode = SKError.Code(rawValue: nsError.code) {
            return message(for: skErrorCode, fallback: fallback)
        }

        if let localizedError = error as? LocalizedError,
           let errorDescription = localizedError.errorDescription,
           !errorDescription.isEmpty {
            return errorDescription
        }

        return fallback
    }

    private func message(for error: StoreKitError, fallback: String) -> String? {
        switch error {
        case .userCancelled:
            return nil
        case .networkError:
            return "Check your internet connection and try again."
        case .notAvailableInStorefront:
            return "FXNews Pro is not available in your current App Store region."
        case .notEntitled:
            return "This app build is not entitled to make purchases."
        case .unsupported:
            return "Purchases are not supported on this device or platform."
        case .systemError, .unknown:
            return fallback
        @unknown default:
            return fallback
        }
    }

    private func message(for code: SKError.Code, fallback: String) -> String? {
        switch code {
        case .paymentCancelled, .overlayCancelled:
            return nil
        case .cloudServiceNetworkConnectionFailed:
            return "Check your internet connection and try again."
        case .paymentNotAllowed:
            return "Purchases are not allowed for this Apple ID or device."
        case .storeProductNotAvailable:
            return "FXNews Pro is not available in your current App Store region."
        case .clientInvalid, .paymentInvalid, .unauthorizedRequestData:
            return "This purchase could not be started for this app build."
        default:
            return fallback
        }
    }

}
