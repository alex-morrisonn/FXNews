import StoreKit
import SwiftUI

@MainActor
struct ProUpgradeView: View {
    @Bindable var subscriptionStore: SubscriptionStore

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var isShowingManageSubscriptions = false
    @State private var purchasingProductID: String?
    @State private var isRestoringPurchases = false

    var body: some View {
        ScrollView {
            FXNewsScreen {
                VStack(alignment: .leading, spacing: 16) {
                    heroSection
                    essentialsCard
                    subscriptionOptionsCard
                }
            }
        }
        .background(FXNewsPalette.backgroundTop.ignoresSafeArea())
        .navigationTitle("FXNews Pro")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") {
                    dismiss()
                }
            }
        }
        .task {
            await subscriptionStore.load()
        }
        .manageSubscriptionsSheet(isPresented: $isShowingManageSubscriptions)
        .onChange(of: isShowingManageSubscriptions) { _, isPresented in
            guard !isPresented else { return }

            Task {
                await subscriptionStore.refreshEntitlements()
            }
        }
        .alert("FXNews Pro", isPresented: purchaseMessageBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(subscriptionStore.purchaseMessage ?? "")
        }
    }

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                Text("FXNEWS PRO")
                    .font(.caption.weight(.semibold))
                    .tracking(1.1)
                    .foregroundStyle(FXNewsPalette.accent)

                if subscriptionStore.hasProAccess {
                    ProBadge()
                }
            }

            Text(subscriptionStore.hasProAccess ? "Pro is active" : "Upgrade for smarter alerts")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(FXNewsPalette.text)
                .fixedSize(horizontal: false, vertical: true)

            Text(subscriptionStore.hasProAccess
                ? "Your alerts, saved workflows, and pair tools are unlocked on this Apple ID."
                : "Keep the free calendar. Add Pro when you want custom reminders, saved setups, and clearer pair impact.")
                .font(.subheadline)
                .foregroundStyle(FXNewsPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(FXNewsPalette.surface)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(FXNewsPalette.stroke, lineWidth: 1)
                }
        )
    }

    private var essentialsCard: some View {
        FXNewsCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("What Pro adds")
                    .font(.headline)
                    .foregroundStyle(FXNewsPalette.text)

                VStack(alignment: .leading, spacing: 12) {
                    essentialBenefit(
                        icon: "bell.badge.fill",
                        title: "Custom alerts",
                        detail: "Choose the events, impact levels, and reminder timing you care about."
                    )
                    essentialBenefit(
                        icon: "line.3.horizontal.decrease.circle.fill",
                        title: "Saved setups",
                        detail: "Save your preferred filters and startup page for faster daily checks."
                    )
                    essentialBenefit(
                        icon: "chart.line.uptrend.xyaxis",
                        title: "Pair impact",
                        detail: "See which watched pairs have the most upcoming macro pressure."
                    )
                }
            }
        }
    }

    private var subscriptionOptionsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(subscriptionStore.hasProAccess ? "Subscription" : "Choose your plan")
                    .font(.headline)
                    .foregroundStyle(FXNewsPalette.text)

                Spacer()

                if subscriptionStore.hasProAccess {
                    Text("Active")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(FXNewsPalette.success)
                }
            }

            if let statusMessage = subscriptionStore.subscriptionStatusMessage {
                subscriptionStatusBanner(statusMessage)
            }

            if subscriptionStore.hasProAccess {
                activeSubscriptionActions
            } else {
                storeKitSubscriptionStore
                subscriptionLegalFooter
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(FXNewsPalette.surface)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(FXNewsPalette.stroke, lineWidth: 1)
                }
        )
    }

    private func subscriptionStatusBanner(_ message: String) -> some View {
        Label {
            Text(message)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: subscriptionStore.hasSubscriptionBillingIssue ? "exclamationmark.triangle.fill" : "info.circle.fill")
        }
        .foregroundStyle(subscriptionStore.hasSubscriptionBillingIssue ? Color.orange.opacity(0.9) : FXNewsPalette.muted)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(subscriptionStore.hasSubscriptionBillingIssue ? Color.orange.opacity(0.12) : FXNewsPalette.surfaceStrong)
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(subscriptionStore.hasSubscriptionBillingIssue ? Color.orange.opacity(0.25) : FXNewsPalette.stroke, lineWidth: 1)
                }
        )
    }

    private var activeSubscriptionActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("FXNews Pro is unlocked on this Apple ID", systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(FXNewsPalette.success)

            Button {
                isShowingManageSubscriptions = true
            } label: {
                Label("Manage Subscription", systemImage: "person.crop.circle.badge.checkmark")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(FXNewsPalette.accent)
        }
    }

    private var unavailablePlansMessage: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Plans are not available right now.")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(FXNewsPalette.text)

            Text("StoreKit did not return the FXNews Pro monthly or yearly subscription products for this build. Please make sure the subscriptions are added to this app version in App Store Connect.")
                .font(.caption)
                .foregroundStyle(FXNewsPalette.muted)
                .fixedSize(horizontal: false, vertical: true)

            if !subscriptionStore.unavailableProductIDs.isEmpty {
                Text("Requested: \(subscriptionStore.unavailableProductIDs.joined(separator: ", "))")
                    .font(.caption2)
                    .foregroundStyle(FXNewsPalette.muted)
                    .textSelection(.enabled)
            }

            Button {
                Task {
                    await subscriptionStore.loadProducts()
                }
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .tint(FXNewsPalette.accent)
            .disabled(subscriptionStore.isLoadingProducts)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(FXNewsPalette.surfaceStrong)
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(FXNewsPalette.stroke, lineWidth: 1)
                }
        )
    }

    @ViewBuilder
    private var storeKitSubscriptionStore: some View {
        if subscriptionStore.isLoadingProducts && subscriptionStore.sortedProducts.isEmpty {
            loadingPlansMessage
        } else if subscriptionStore.sortedProducts.isEmpty {
            unavailablePlansMessage
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text("Select a plan")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(FXNewsPalette.muted)

                VStack(spacing: 8) {
                    ForEach(subscriptionStore.sortedProducts) { product in
                        subscriptionPlanButton(for: product)
                    }
                }

                restorePurchasesButton
            }
        }
    }

    private var loadingPlansMessage: some View {
        HStack(spacing: 10) {
            ProgressView()
                .tint(FXNewsPalette.accent)

            Text("Loading plans...")
                .font(.caption.weight(.semibold))
                .foregroundStyle(FXNewsPalette.muted)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(FXNewsPalette.surfaceStrong)
        )
    }

    private func subscriptionPlanButton(for product: Product) -> some View {
        Button {
            Task {
                purchasingProductID = product.id
                await subscriptionStore.purchase(product)
                purchasingProductID = nil
            }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(planTitle(for: product))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(FXNewsPalette.text)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(planPriceText(for: product))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(FXNewsPalette.muted)
                }

                Spacer(minLength: 12)

                if purchasingProductID == product.id {
                    ProgressView()
                        .tint(.white)
                        .frame(width: 22, height: 22)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(FXNewsPalette.surfaceStrong)
                    .overlay(alignment: .trailing) {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(FXNewsPalette.accent)
                            .frame(width: 46)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(FXNewsPalette.stroke, lineWidth: 1)
                    }
            )
        }
        .buttonStyle(.plain)
        .disabled(purchasingProductID != nil || isRestoringPurchases)
    }

    private var restorePurchasesButton: some View {
        Button {
            Task {
                isRestoringPurchases = true
                await subscriptionStore.restorePurchases()
                isRestoringPurchases = false
            }
        } label: {
            HStack(spacing: 8) {
                if isRestoringPurchases {
                    ProgressView()
                        .tint(FXNewsPalette.accent)
                } else {
                    Image(systemName: "arrow.clockwise")
                }

                Text("Restore purchases")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(FXNewsPalette.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(FXNewsPalette.stroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(purchasingProductID != nil || isRestoringPurchases)
    }

    private func planTitle(for product: Product) -> String {
        product.displayName
    }

    private func planPriceText(for product: Product) -> String {
        guard let subscriptionProduct = SubscriptionProduct.product(for: product.id) else {
            return "USD pricing shown at checkout"
        }

        return "\(subscriptionProduct.usdDisplayPrice) / \(subscriptionProduct.periodText)"
    }

    private func essentialBenefit(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(FXNewsPalette.accent)
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(FXNewsPalette.accentSoft)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(FXNewsPalette.text)
                    .fixedSize(horizontal: false, vertical: true)

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(FXNewsPalette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var subscriptionLegalFooter: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Subscriptions auto-renew until canceled. Your Apple ID is charged at confirmation of purchase and renewal. You can manage or cancel your subscription in App Store account settings at least 24 hours before the end of the current period.")
                .font(.caption2)
                .foregroundStyle(FXNewsPalette.muted)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button("Terms of Service") {
                    openExternalLink(AppExternalLinks.termsOfServiceURL)
                }

                Button("Privacy Policy") {
                    openExternalLink(AppExternalLinks.privacyPolicyURL)
                }
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(FXNewsPalette.accent)
        }
    }

    private func openExternalLink(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        openURL(url)
    }

    private var purchaseMessageBinding: Binding<Bool> {
        Binding(
            get: { subscriptionStore.purchaseMessage != nil },
            set: { isPresented in
                if !isPresented {
                    subscriptionStore.clearMessage()
                }
            }
        )
    }
}

struct ProBadge: View {
    var body: some View {
        Text("PRO")
            .font(.caption2.weight(.bold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(FXNewsPalette.accent)
            )
    }
}

struct ProLockedRow: View {
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "lock.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(FXNewsPalette.accent)
                    .frame(width: 18, height: 18)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(FXNewsPalette.text)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(FXNewsPalette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Text("Pro")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(FXNewsPalette.accent)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(FXNewsPalette.accentSoft.opacity(0.55))
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview("FXNews Pro") {
    NavigationStack {
        ProUpgradeView(subscriptionStore: SubscriptionStore())
    }
}
