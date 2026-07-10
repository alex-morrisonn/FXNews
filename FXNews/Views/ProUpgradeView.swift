import StoreKit
import SwiftUI

@MainActor
struct ProUpgradeView: View {
    @Bindable var subscriptionStore: SubscriptionStore

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var isShowingManageSubscriptions = false

    var body: some View {
        ScrollView {
            FXNewsScreen {
                VStack(alignment: .leading, spacing: 16) {
                    heroSection
                    workflowHighlights
                    allProFeatures
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
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 10) {
                Text("FXNEWS PRO")
                    .font(.caption.weight(.semibold))
                    .tracking(1.1)
                    .foregroundStyle(FXNewsPalette.accent)

                if subscriptionStore.hasProAccess {
                    ProBadge()
                }
            }

            Text(subscriptionStore.hasProAccess ? "Your trading desk is unlocked" : "Turn the calendar into a trading desk")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(FXNewsPalette.text)
                .fixedSize(horizontal: false, vertical: true)

            Text(subscriptionStore.hasProAccess
                ? "Manage your subscription, keep alerts synced, and use every Pro workflow across FX News."
                : "Keep the core calendar free. Upgrade when you want tailored alerts, session reminders, pair prioritisation, and saved workflows.")
                .font(.subheadline)
                .foregroundStyle(FXNewsPalette.muted)
                .fixedSize(horizontal: false, vertical: true)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    proMetric(title: "Features", value: "6")
                    proMetric(title: "Alerts", value: "Custom")
                    proMetric(title: "Pairs", value: "Ranked")
                }

                VStack(spacing: 8) {
                    proMetric(title: "Features", value: "6")
                    proMetric(title: "Alerts", value: "Custom")
                    proMetric(title: "Pairs", value: "Ranked")
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(FXNewsPalette.surface)
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 42, weight: .semibold))
                        .foregroundStyle(FXNewsPalette.accent.opacity(0.20))
                        .padding(20)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(FXNewsPalette.stroke, lineWidth: 1)
                }
        )
    }

    private var workflowHighlights: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Built for repeatable trading routines")
                .font(.headline)
                .foregroundStyle(FXNewsPalette.text)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    workflowPillar(
                        icon: "bell.badge.fill",
                        title: "Alert only what matters",
                        subtitle: "Tune lead times, quiet hours, and one-off reminders."
                    )
                    workflowPillar(
                        icon: "clock.badge.checkmark.fill",
                        title: "Never miss a session",
                        subtitle: "Get warnings before major market opens."
                    )
                    workflowPillar(
                        icon: "chart.line.uptrend.xyaxis",
                        title: "Rank your pairs",
                        subtitle: "Spot shared-currency risk and priority setups."
                    )
                }

                VStack(spacing: 10) {
                    workflowPillar(
                        icon: "bell.badge.fill",
                        title: "Alert only what matters",
                        subtitle: "Tune lead times, quiet hours, and one-off reminders."
                    )
                    workflowPillar(
                        icon: "clock.badge.checkmark.fill",
                        title: "Never miss a session",
                        subtitle: "Get warnings before major market opens."
                    )
                    workflowPillar(
                        icon: "chart.line.uptrend.xyaxis",
                        title: "Rank your pairs",
                        subtitle: "Spot shared-currency risk and priority setups."
                    )
                }
            }
        }
    }

    private var allProFeatures: some View {
        FXNewsCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Everything in Pro")
                        .font(.headline)
                        .foregroundStyle(FXNewsPalette.text)

                    Spacer()

                    Text("6 tools")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(FXNewsPalette.accent)
                }

                VStack(alignment: .leading, spacing: 14) {
                    ForEach(ProFeature.allCases) { feature in
                        proFeatureTile(feature)
                    }
                }
            }
        }
    }

    private var subscriptionOptionsCard: some View {
        FXNewsCard {
            VStack(alignment: .leading, spacing: 14) {
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

                if subscriptionStore.hasProAccess {
                    activeSubscriptionActions
                } else {
                    subscriptionReviewSummary
                    subscriptionPlanButtons
                    subscriptionLegalFooter
                }
            }
        }
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

    private var subscriptionReviewSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Auto-renewable subscription")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(FXNewsPalette.text)

            VStack(alignment: .leading, spacing: 8) {
                reviewSummaryRow("Choose FXNews Pro Monthly or FXNews Pro Yearly below.")
                reviewSummaryRow("The StoreKit plan buttons show the current App Store price and renewal period before purchase.")
                reviewSummaryRow("Pro unlocks custom event alerts, session reminders, saved filter presets, startup page selection, and advanced pair impact tools.")
            }
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

    private func reviewSummaryRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(FXNewsPalette.success)
                .padding(.top, 1)

            Text(text)
                .font(.caption)
                .foregroundStyle(FXNewsPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var subscriptionPlanButtons: some View {
        if subscriptionStore.isLoadingProducts {
            planLoadingMessage
        } else if subscriptionStore.sortedProducts.isEmpty {
            unavailablePlansMessage
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text("Select a plan")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(FXNewsPalette.text)

                ForEach(subscriptionStore.sortedProducts, id: \.id) { product in
                    subscriptionButton(for: product)
                }
            }
        }
    }

    private var planLoadingMessage: some View {
        HStack(spacing: 10) {
            ProgressView()
                .tint(FXNewsPalette.accent)

            Text("Loading current App Store plans...")
                .font(.caption)
                .foregroundStyle(FXNewsPalette.muted)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(FXNewsPalette.surfaceStrong)
        )
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

            if let diagnostics = subscriptionStore.productDiagnostics {
                productDiagnosticsPanel(diagnostics)
            }
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

    private func productDiagnosticsPanel(_ diagnostics: ProductLoadDiagnostics) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Store diagnostics")
                .font(.caption.weight(.semibold))
                .foregroundStyle(FXNewsPalette.text)

            diagnosticRow(title: "Bundle", value: diagnostics.bundleIdentifier)
            diagnosticRow(title: "Storefront", value: diagnostics.storefrontCountryCode)
            diagnosticRow(title: "Requested", value: diagnostics.requestedProductIDs.joined(separator: ", "))
            diagnosticRow(title: "StoreKit 2 returned", value: diagnosticListText(diagnostics.storeKitProductIDs))
            diagnosticRow(title: "Legacy returned", value: diagnosticListText(diagnostics.legacyProductIDs))
            diagnosticRow(title: "Legacy invalid", value: diagnosticListText(diagnostics.invalidProductIDs))

            if let errorMessage = diagnostics.errorMessage {
                diagnosticRow(title: "Error", value: errorMessage)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(FXNewsPalette.backgroundBottom.opacity(0.55))
        )
    }

    private func diagnosticRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(FXNewsPalette.muted)

            Text(value)
                .font(.caption2)
                .foregroundStyle(FXNewsPalette.text)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func diagnosticListText(_ values: [String]) -> String {
        values.isEmpty ? "None" : values.joined(separator: ", ")
    }

    @ViewBuilder
    private var storeKitSubscriptionStore: some View {
        if let termsURL = URL(string: AppExternalLinks.termsOfServiceURL),
           let privacyURL = URL(string: AppExternalLinks.privacyPolicyURL) {
            SubscriptionStoreView(productIDs: SubscriptionProduct.identifiers) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Select a plan")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(FXNewsPalette.text)

                    Text("Prices and renewal periods are loaded from the App Store and shown on each plan before you subscribe.")
                        .font(.caption)
                        .foregroundStyle(FXNewsPalette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .subscriptionStorePolicyDestination(url: termsURL, for: .termsOfService)
            .subscriptionStorePolicyDestination(url: privacyURL, for: .privacyPolicy)
            .subscriptionStorePolicyForegroundStyle(FXNewsPalette.accent, FXNewsPalette.muted)
            .storeButton(.visible, for: .restorePurchases, .policies)
            .storeButton(.hidden, for: .cancellation)
            .productDescription(.visible)
            .subscriptionStoreButtonLabel(.multiline)
            .onInAppPurchaseCompletion { product, result in
                await subscriptionStore.handleStoreKitViewPurchaseCompletion(product: product, result: result)
            }
        } else {
            unavailablePlansMessage
        }
    }

    private func proMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .tracking(0.8)
                .foregroundStyle(FXNewsPalette.muted)

            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(FXNewsPalette.text)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(FXNewsPalette.surfaceStrong)
        )
    }

    private func workflowPillar(icon: String, title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(FXNewsPalette.accent)
                .frame(width: 30, height: 30)
                .background(
                    Circle()
                        .fill(FXNewsPalette.accentSoft)
                )

            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(FXNewsPalette.text)
                .fixedSize(horizontal: false, vertical: true)

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(FXNewsPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(FXNewsPalette.surface)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(FXNewsPalette.stroke, lineWidth: 1)
                }
        )
    }

    private func proFeatureTile(_ feature: ProFeature) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: feature.iconName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(FXNewsPalette.accent)
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(FXNewsPalette.accentSoft)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(feature.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(FXNewsPalette.text)
                    .fixedSize(horizontal: false, vertical: true)

                Text(feature.description)
                    .font(.caption)
                    .foregroundStyle(FXNewsPalette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func subscriptionButton(for product: Product) -> some View {
        Button {
            Task {
                await subscriptionStore.purchase(product)
            }
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(product.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)

                    Text(product.description)
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.82))
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(product.displayPrice)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.80)

                    if let renewalPeriod = renewalPeriodText(for: product) {
                        Text(renewalPeriod)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.white.opacity(0.82))
                            .lineLimit(1)
                    }
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(FXNewsPalette.accent)
            )
        }
        .buttonStyle(.plain)
    }

    private var subscriptionLegalFooter: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Subscriptions auto-renew until canceled. Your Apple ID is charged at confirmation of purchase and renewal. You can manage or cancel your subscription in App Store account settings at least 24 hours before the end of the current period.")
                .font(.caption)
                .foregroundStyle(FXNewsPalette.muted)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                Button("Terms of Service") {
                    openExternalLink(AppExternalLinks.termsOfServiceURL)
                }

                Button("Privacy Policy") {
                    openExternalLink(AppExternalLinks.privacyPolicyURL)
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(FXNewsPalette.accent)
        }
        .padding(.top, 2)
    }

    private func renewalPeriodText(for product: Product) -> String? {
        guard let subscriptionPeriod = product.subscription?.subscriptionPeriod else {
            return nil
        }

        return "per \(periodDescription(subscriptionPeriod))"
    }

    private func periodDescription(_ period: Product.SubscriptionPeriod) -> String {
        let unitText: String

        switch period.unit {
        case .day:
            unitText = period.value == 1 ? "day" : "days"
        case .week:
            unitText = period.value == 1 ? "week" : "weeks"
        case .month:
            unitText = period.value == 1 ? "month" : "months"
        case .year:
            unitText = period.value == 1 ? "year" : "years"
        @unknown default:
            unitText = "period"
        }

        return period.value == 1 ? unitText : "\(period.value) \(unitText)"
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

private extension ProFeature {
    var iconName: String {
        switch self {
        case .customEventAlerts:
            "bell.badge.fill"
        case .sessionOpenAlerts:
            "clock.badge.checkmark.fill"
        case .filterPresets:
            "line.3.horizontal.decrease.circle.fill"
        case .startupPage:
            "rectangle.stack.badge.play.fill"
        case .pairImpactWorkspace:
            "rectangle.3.group.fill"
        case .advancedPairImpact:
            "chart.line.uptrend.xyaxis"
        }
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
