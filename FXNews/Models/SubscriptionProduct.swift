import Foundation

enum SubscriptionProduct: String, CaseIterable, Identifiable {
    case monthly = "fxnews.pro.monthly.v2"
    case yearly = "fxnews.pro.yearly.v2"

    var id: String { rawValue }

    var usdDisplayPrice: String {
        switch self {
        case .monthly:
            "$4.99 USD"
        case .yearly:
            "$39.99 USD"
        }
    }

    var periodText: String {
        switch self {
        case .monthly:
            "month"
        case .yearly:
            "year"
        }
    }

    static var identifiers: [String] {
        allCases.map(\.rawValue)
    }

    static func product(for identifier: String) -> SubscriptionProduct? {
        allCases.first { $0.rawValue == identifier }
    }

}

enum ProFeature: String, CaseIterable, Identifiable {
    case customEventAlerts
    case sessionOpenAlerts
    case filterPresets
    case startupPage
    case pairImpactWorkspace
    case advancedPairImpact

    var id: String { rawValue }

    var title: String {
        switch self {
        case .customEventAlerts:
            "Custom event alerts"
        case .sessionOpenAlerts:
            "Session reminders"
        case .filterPresets:
            "Saved filter presets"
        case .startupPage:
            "Custom startup page"
        case .pairImpactWorkspace:
            "Pair impact workspace"
        case .advancedPairImpact:
            "Advanced pair impact"
        }
    }

    var description: String {
        switch self {
        case .customEventAlerts:
            "Set one-off reminders and tune event lead times by impact."
        case .sessionOpenAlerts:
            "Get 15-minute and at-open alerts for major trading sessions."
        case .filterPresets:
            "Save and reapply calendar setups for currencies, impact levels, categories, and watchlists."
        case .startupPage:
            "Choose which tab FX News opens to when you start the app."
        case .pairImpactWorkspace:
            "Turn your watchlist into priority ranking and shared-risk analysis."
        case .advancedPairImpact:
            "Rank watched pairs by upcoming macro pressure and shared currency risk."
        }
    }
}
