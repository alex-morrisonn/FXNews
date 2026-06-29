import StoreKit
import SwiftUI

@MainActor
struct ProUpgradeView: View {
    @Bindable var subscriptionStore: SubscriptionStore

    @Environment(\.dismiss) private var dismiss
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
                } else if subscriptionStore.isLoadingProducts {
                    ProgressView("Loading plans...")
                        .tint(FXNewsPalette.accent)
                } else if subscriptionStore.sortedProducts.isEmpty {
                    unavailablePlansMessage
                } else {
                    VStack(spacing: 10) {
                        ForEach(subscriptionStore.sortedProducts, id: \.id) { product in
                            subscriptionButton(for: product)
                        }
                    }
                }

                Button("Restore Purchases") {
                    Task {
                        await subscriptionStore.restorePurchases()
                    }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(FXNewsPalette.accent)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 2)
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

    private var unavailablePlansMessage: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Plans are not available right now.")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(FXNewsPalette.text)

            Text("StoreKit did not return the monthly or yearly subscription products for this build.")
                .font(.caption)
                .foregroundStyle(FXNewsPalette.muted)
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

                Text(product.displayPrice)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.80)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(FXNewsPalette.accent)
            )
        }
        .buttonStyle(.plain)
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
