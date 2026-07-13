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
        preferences.selectedCurrencyCodes = ["EUR", "USD"]
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
        #expect(restored.selectedCurrencyCodes == ["EUR", "USD"])
        #expect(restored.selectedCurrencyCode == "EUR")
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
    func invalidStoredEnumValuesFallBackToLaunchSafeDefaults() {
        let defaults = makeDefaults()
        defaults.set("severe", forKey: "preferences.minimumImpact")
        defaults.set("sepia", forKey: "preferences.preferredAppearance")
        defaults.set("analytics", forKey: "preferences.startupTab")
        defaults.set("critical", forKey: "preferences.notificationSoundOption")

        let preferences = UserPreferences(defaults: defaults)

        #expect(preferences.minimumImpact == .low)
        #expect(preferences.preferredAppearance == .dark)
        #expect(preferences.startupTab == .today)
        #expect(preferences.notificationSoundOption == .subtle)
    }

    @Test
    func legacySingleCurrencyFilterMigratesWhenMultiCurrencyFilterIsMissing() {
        let defaults = makeDefaults()
        defaults.set("USD", forKey: "preferences.selectedCurrencyCode")

        let preferences = UserPreferences(defaults: defaults)

        #expect(preferences.selectedCurrencyCodes == ["USD"])
        #expect(preferences.selectedCurrencyCode == "USD")
    }

    @Test
    func multiCurrencyFilterTakesPrecedenceOverLegacySingleCurrencyFilter() {
        let defaults = makeDefaults()
        defaults.set("USD", forKey: "preferences.selectedCurrencyCode")
        defaults.set(["JPY", "EUR"], forKey: "preferences.selectedCurrencyCodes")

        let preferences = UserPreferences(defaults: defaults)

        #expect(preferences.selectedCurrencyCodes == ["EUR", "JPY"])
        #expect(preferences.selectedCurrencyCode == "EUR")
    }

    @Test
    func calendarFilterPresetsPersistApplyAndDelete() throws {
        let defaults = makeDefaults()
        let preferences = UserPreferences(defaults: defaults)
        preferences.minimumImpact = .high
        preferences.selectedCurrencyCodes = ["EUR", "USD"]
        preferences.selectedCountryCode = "US"
        preferences.selectedCategory = "Labor"
        preferences.showOnlyWatchedPairs = true

        preferences.saveCurrentCalendarFilterPreset(named: "Currency risk")

        let restored = UserPreferences(defaults: defaults)
        let preset = try #require(restored.calendarFilterPresets.first)
        #expect(restored.calendarFilterPresets.count == 1)
        #expect(preset.name == "Currency risk")
        #expect(preset.summary.contains("High impact"))
        #expect(preset.summary.contains("EUR"))
        #expect(preset.summary.contains("USD"))
        #expect(preset.summary.contains("United States"))
        #expect(preset.summary.contains("Labor"))
        #expect(preset.summary.contains("Watchlist"))

        restored.minimumImpact = .low
        restored.selectedCurrencyCodes = []
        restored.selectedCountryCode = nil
        restored.selectedCategory = nil
        restored.showOnlyWatchedPairs = false
        restored.applyCalendarFilterPreset(preset)

        #expect(restored.minimumImpact == .high)
        #expect(restored.selectedCurrencyCodes == ["EUR", "USD"])
        #expect(restored.selectedCountryCode == "US")
        #expect(restored.selectedCategory == "Labor")
        #expect(restored.showOnlyWatchedPairs)

        restored.deleteCalendarFilterPreset(preset)
        #expect(restored.calendarFilterPresets.isEmpty)
    }

    @Test
    func calendarFilterPresetWithSameNameReplacesCurrencySelection() throws {
        let defaults = makeDefaults()
        let preferences = UserPreferences(defaults: defaults)
        preferences.selectedCurrencyCodes = ["USD"]
        preferences.saveCurrentCalendarFilterPreset(named: "Major currency")

        preferences.selectedCurrencyCodes = ["EUR"]
        preferences.saveCurrentCalendarFilterPreset(named: "Major currency")

        let restored = UserPreferences(defaults: defaults)
        let preset = try #require(restored.calendarFilterPresets.first)
        #expect(restored.calendarFilterPresets.count == 1)
        #expect(preset.name == "Major currency")
        #expect(preset.selectedCurrencyCodes == ["EUR"])

        restored.selectedCurrencyCodes = ["USD"]
        restored.applyCalendarFilterPreset(preset)
        #expect(restored.selectedCurrencyCodes == ["EUR"])
    }

    @Test
    func calendarFilterPresetNamesAreTrimmedRejectedWhenBlankAndCappedAtTwelve() throws {
        let preferences = UserPreferences(defaults: makeDefaults())

        #expect(preferences.saveCurrentCalendarFilterPreset(named: "   ") == nil)

        for index in 1...13 {
            preferences.selectedCurrencyCodes = ["USD"]
            preferences.saveCurrentCalendarFilterPreset(named: " Preset \(index) ")
        }

        #expect(preferences.calendarFilterPresets.count == 12)
        #expect(preferences.calendarFilterPresets.first?.name == "Preset 13")
        #expect(preferences.calendarFilterPresets.last?.name == "Preset 2")
        #expect(!preferences.calendarFilterPresets.contains { $0.name == "Preset 1" })
    }

    @Test
    func legacyCalendarFilterPresetDecodesSingleCurrencyCode() throws {
        let id = UUID()
        let data = try #require(
            """
            [
              {
                "id": "\(id.uuidString)",
                "name": "Legacy USD",
                "minimumImpact": "high",
                "selectedCurrencyCode": "USD",
                "selectedCountryCode": "US",
                "selectedCategory": "Labor",
                "showOnlyWatchedPairs": true
              }
            ]
            """.data(using: .utf8)
        )
        let defaults = makeDefaults()
        defaults.set(data, forKey: "preferences.calendarFilterPresets")

        let preferences = UserPreferences(defaults: defaults)
        let preset = try #require(preferences.calendarFilterPresets.first)

        #expect(preset.id == id)
        #expect(preset.selectedCurrencyCodes == ["USD"])
        #expect(preset.summary.contains("USD"))
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
        preferences.selectedCurrencyCodes = ["EUR", "USD"]
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
        preferences.sydneySessionNotificationsEnabled = true
        preferences.tokyoSessionNotificationsEnabled = true
        preferences.sydneySessionOpenNotificationsEnabled = true
        preferences.tokyoSessionOpenNotificationsEnabled = true
        preferences.hasCompletedOnboarding = true

        preferences.reset()

        #expect(preferences.minimumImpact == .low)
        #expect(preferences.selectedCurrencyCodes.isEmpty)
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
        #expect(!preferences.sydneySessionNotificationsEnabled)
        #expect(!preferences.tokyoSessionNotificationsEnabled)
        #expect(!preferences.sydneySessionOpenNotificationsEnabled)
        #expect(!preferences.tokyoSessionOpenNotificationsEnabled)
        #expect(preferences.hasCompletedOnboarding)
    }

    @Test
    func resetPersistsLaunchSafeDefaultsAcrossPreferenceInstances() {
        let defaults = makeDefaults()
        let preferences = UserPreferences(defaults: defaults)
        preferences.minimumImpact = .high
        preferences.selectedCurrencyCodes = ["EUR", "USD"]
        preferences.selectedCountryCode = "US"
        preferences.selectedCategory = "Labor"
        preferences.startupTab = .calendar
        preferences.calendarFilterPresets = [
            CalendarFilterPreset(
                name: "Macro",
                minimumImpact: .high,
                selectedCurrencyCodes: ["USD"],
                selectedCountryCode: nil,
                selectedCategory: nil,
                showOnlyWatchedPairs: false
            )
        ]
        preferences.hasCompletedOnboarding = true

        preferences.reset()
        let restored = UserPreferences(defaults: defaults)

        #expect(restored.minimumImpact == .low)
        #expect(restored.selectedCurrencyCodes.isEmpty)
        #expect(restored.selectedCountryCode == nil)
        #expect(restored.selectedCategory == nil)
        #expect(restored.startupTab == .today)
        #expect(restored.calendarFilterPresets.isEmpty)
        #expect(restored.hasCompletedOnboarding)
    }

    @Test
    func firstLaunchDateIsCreatedOnceAndNotOverwritten() throws {
        let defaults = makeDefaults()
        let firstLaunchDate = Date(timeIntervalSince1970: 1_700_000_000)
        defaults.set(firstLaunchDate, forKey: "preferences.firstLaunchDate")

        let preferences = UserPreferences(defaults: defaults)
        let restored = UserPreferences(defaults: defaults)

        #expect(preferences.firstLaunchDate == firstLaunchDate)
        #expect(restored.firstLaunchDate == firstLaunchDate)
    }

    @Test
    func legacyAsianSessionNotificationSettingsMigrateToSydney() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: "preferences.asianSessionNotificationsEnabled")
        defaults.set(true, forKey: "preferences.asianSessionOpenNotificationsEnabled")

        let preferences = UserPreferences(defaults: defaults)

        #expect(preferences.sydneySessionNotificationsEnabled)
        #expect(preferences.sydneySessionOpenNotificationsEnabled)
        #expect(!preferences.tokyoSessionNotificationsEnabled)
        #expect(!preferences.tokyoSessionOpenNotificationsEnabled)
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
