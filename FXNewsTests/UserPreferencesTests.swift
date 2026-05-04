import Foundation
import Testing
@testable import FXNews

@MainActor
struct UserPreferencesTests {
    @Test
    func effectiveTimeZoneUsesManualSelection() throws {
        let preferences = UserPreferences(defaults: makeDefaults())
        preferences.manualTimeZoneIdentifier = "Asia/Tokyo"

        #expect(preferences.effectiveTimeZone.identifier == "Asia/Tokyo")
    }

    @Test
    func effectiveTimeZonePrefersUTCWhenEnabled() {
        let preferences = UserPreferences(defaults: makeDefaults())
        preferences.manualTimeZoneIdentifier = "Asia/Tokyo"
        preferences.useUTC = true

        #expect(preferences.effectiveTimeZone.secondsFromGMT() == 0)
    }

    @Test
    func settingsPersistAcrossPreferenceInstances() {
        let defaults = makeDefaults()
        let preferences = UserPreferences(defaults: defaults)
        preferences.minimumImpact = .high
        preferences.selectedCurrencyCode = "USD"
        preferences.selectedCountryCode = "US"
        preferences.selectedCategory = "labor"
        preferences.showOnlyWatchedPairs = true
        preferences.use24HourTime = true
        preferences.preferredAppearance = .light
        preferences.watchedPairSymbols = ["EURUSD", "GBPJPY"]
        preferences.highImpactNotificationLeadTimeMinutes = 45
        preferences.notificationSoundOption = .prominent
        preferences.londonSessionNotificationsEnabled = true
        preferences.londonSessionOpenNotificationsEnabled = true
        preferences.hasCompletedOnboarding = true

        let restored = UserPreferences(defaults: defaults)

        #expect(restored.minimumImpact == .high)
        #expect(restored.selectedCurrencyCode == "USD")
        #expect(restored.selectedCountryCode == "US")
        #expect(restored.selectedCategory == "labor")
        #expect(restored.showOnlyWatchedPairs)
        #expect(restored.use24HourTime)
        #expect(restored.preferredAppearance == .light)
        #expect(restored.watchedPairSymbols == ["EURUSD", "GBPJPY"])
        #expect(restored.highImpactNotificationLeadTimeMinutes == 45)
        #expect(restored.notificationSoundOption == .prominent)
        #expect(restored.londonSessionNotificationsEnabled)
        #expect(restored.londonSessionOpenNotificationsEnabled)
        #expect(restored.hasCompletedOnboarding)
    }

    @Test
    func toggleWatchMaintainsSortedUniquePairList() {
        let preferences = UserPreferences(defaults: makeDefaults())

        preferences.toggleWatch(for: "GBPJPY")
        preferences.toggleWatch(for: "EURUSD")
        preferences.toggleWatch(for: "GBPJPY")
        preferences.toggleWatch(for: "USDJPY")

        #expect(preferences.watchedPairSymbols == ["EURUSD", "USDJPY"])
        #expect(preferences.isPairWatched("EURUSD"))
        #expect(!preferences.isPairWatched("GBPJPY"))
    }

    @Test
    func watchedPairCurrencyCodesIncludeBaseAndQuoteCurrencies() {
        let preferences = UserPreferences(defaults: makeDefaults())
        preferences.watchedPairSymbols = ["AUDUSD", "EUR/JPY", "xauusd"]

        #expect(preferences.watchedPairCurrencyCodes == ["AUD", "EUR", "JPY", "USD", "XAU"])
    }

    @Test
    func watchedPairMatchingFallsBackToPairCurrenciesWhenFeedTagsAreIncomplete() throws {
        let preferences = UserPreferences(defaults: makeDefaults())
        preferences.watchedPairSymbols = ["AUDUSD"]
        let formatter = ISO8601DateFormatter()

        let usdEvent = EconomicEvent(
            id: "usd-event",
            title: "US Retail Sales",
            countryCode: "US",
            currencyCode: "USD",
            timestamp: try #require(formatter.date(from: "2026-04-14T12:30:00Z")),
            impactLevel: .high,
            relatedPairs: ["EURUSD", "GBPUSD", "USDJPY"]
        )
        let jpyEvent = EconomicEvent(
            id: "jpy-event",
            title: "Japan CPI",
            countryCode: "JP",
            currencyCode: "JPY",
            timestamp: try #require(formatter.date(from: "2026-04-15T12:30:00Z")),
            impactLevel: .medium,
            relatedPairs: ["USDJPY"]
        )

        #expect(preferences.matchesWatchedPair(usdEvent))
        #expect(!preferences.matchesWatchedPair(jpyEvent))
    }

    @Test
    func resetRestoresLaunchSafeDefaultsWithoutRepeatingOnboarding() {
        let preferences = UserPreferences(defaults: makeDefaults())
        preferences.minimumImpact = .high
        preferences.selectedCurrencyCode = "USD"
        preferences.showOnlyWatchedPairs = true
        preferences.use24HourTime = true
        preferences.useUTC = true
        preferences.manualTimeZoneIdentifier = "Asia/Tokyo"
        preferences.preferredAppearance = .light
        preferences.watchedPairSymbols = ["EURUSD"]
        preferences.highImpactNotificationLeadTimeMinutes = 60
        preferences.mediumImpactNotificationLeadTimeMinutes = 30
        preferences.lowImpactNotificationLeadTimeMinutes = 10
        preferences.notificationSoundOption = .prominent
        preferences.quietHoursEnabled = true
        preferences.asianSessionNotificationsEnabled = true
        preferences.asianSessionOpenNotificationsEnabled = true
        preferences.hasCompletedOnboarding = true

        preferences.reset()

        #expect(preferences.minimumImpact == .low)
        #expect(preferences.selectedCurrencyCode == nil)
        #expect(!preferences.showOnlyWatchedPairs)
        #expect(!preferences.use24HourTime)
        #expect(!preferences.useUTC)
        #expect(preferences.manualTimeZoneIdentifier == nil)
        #expect(preferences.preferredAppearance == .dark)
        #expect(preferences.watchedPairSymbols.isEmpty)
        #expect(preferences.highImpactNotificationLeadTimeMinutes == 30)
        #expect(preferences.mediumImpactNotificationLeadTimeMinutes == 15)
        #expect(preferences.lowImpactNotificationLeadTimeMinutes == 0)
        #expect(preferences.notificationSoundOption == .subtle)
        #expect(!preferences.quietHoursEnabled)
        #expect(!preferences.asianSessionNotificationsEnabled)
        #expect(!preferences.asianSessionOpenNotificationsEnabled)
        #expect(preferences.hasCompletedOnboarding)
    }

    @Test
    func quietHoursHandleOvernightWindows() throws {
        let preferences = UserPreferences(defaults: makeDefaults())
        preferences.quietHoursEnabled = true
        preferences.quietHoursStartMinutes = 22 * 60
        preferences.quietHoursEndMinutes = 6 * 60

        let formatter = ISO8601DateFormatter()
        let london = try #require(TimeZone(identifier: "Europe/London"))
        let lateNight = try #require(formatter.date(from: "2026-04-14T22:30:00Z"))
        let midday = try #require(formatter.date(from: "2026-04-14T12:30:00Z"))

        #expect(preferences.isWithinQuietHours(on: lateNight, timeZone: london))
        #expect(!preferences.isWithinQuietHours(on: midday, timeZone: london))
    }

    @Test
    func quietHoursIncludeAfterMidnightTimesForOvernightWindows() throws {
        let preferences = UserPreferences(defaults: makeDefaults())
        preferences.quietHoursEnabled = true
        preferences.quietHoursStartMinutes = 22 * 60
        preferences.quietHoursEndMinutes = 6 * 60

        let formatter = ISO8601DateFormatter()
        let london = try #require(TimeZone(identifier: "Europe/London"))
        let afterMidnight = try #require(formatter.date(from: "2026-01-15T00:30:00Z"))
        let justBeforeEnd = try #require(formatter.date(from: "2026-01-15T05:59:00Z"))
        let atEnd = try #require(formatter.date(from: "2026-01-15T06:00:00Z"))

        #expect(preferences.isWithinQuietHours(on: afterMidnight, timeZone: london))
        #expect(preferences.isWithinQuietHours(on: justBeforeEnd, timeZone: london))
        #expect(!preferences.isWithinQuietHours(on: atEnd, timeZone: london))
    }

    @Test
    func quietHoursHandleSameDayWindowsAndDisabledState() throws {
        let preferences = UserPreferences(defaults: makeDefaults())
        preferences.quietHoursStartMinutes = 9 * 60
        preferences.quietHoursEndMinutes = 17 * 60

        let formatter = ISO8601DateFormatter()
        let london = try #require(TimeZone(identifier: "Europe/London"))
        let businessHours = try #require(formatter.date(from: "2026-04-14T10:30:00Z"))
        let evening = try #require(formatter.date(from: "2026-04-14T18:30:00Z"))

        #expect(!preferences.isWithinQuietHours(on: businessHours, timeZone: london))

        preferences.quietHoursEnabled = true

        #expect(preferences.isWithinQuietHours(on: businessHours, timeZone: london))
        #expect(!preferences.isWithinQuietHours(on: evening, timeZone: london))
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "fxnews.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
