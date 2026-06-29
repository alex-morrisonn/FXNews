import Foundation
import Observation
import SwiftUI
import UserNotifications

@MainActor
@Observable
final class UserPreferences {
    var minimumImpact: ImpactLevel {
        didSet { defaults.set(minimumImpact.rawValue, forKey: Keys.minimumImpact) }
    }

    var selectedCurrencyCodes: [String] {
        didSet {
            defaults.set(selectedCurrencyCodes, forKey: Keys.selectedCurrencyCodes)
            setOptionalString(selectedCurrencyCode, forKey: Keys.selectedCurrencyCode)
        }
    }

    var selectedCurrencyCode: String? {
        get { selectedCurrencyCodes.first }
        set { selectedCurrencyCodes = newValue.map { [$0] } ?? [] }
    }

    var selectedCountryCode: String? {
        didSet { setOptionalString(selectedCountryCode, forKey: Keys.selectedCountryCode) }
    }

    var selectedCategory: String? {
        didSet { setOptionalString(selectedCategory, forKey: Keys.selectedCategory) }
    }

    var showOnlyWatchedPairs: Bool {
        didSet { defaults.set(showOnlyWatchedPairs, forKey: Keys.showOnlyWatchedPairs) }
    }

    var use24HourTime: Bool {
        didSet { defaults.set(use24HourTime, forKey: Keys.use24HourTime) }
    }

    var useUTC: Bool {
        didSet { defaults.set(useUTC, forKey: Keys.useUTC) }
    }

    var manualTimeZoneIdentifier: String? {
        didSet { setOptionalString(manualTimeZoneIdentifier, forKey: Keys.manualTimeZoneIdentifier) }
    }

    var preferredAppearance: AppAppearance {
        didSet { defaults.set(preferredAppearance.rawValue, forKey: Keys.preferredAppearance) }
    }

    var startupTab: AppTab {
        didSet { defaults.set(startupTab.rawValue, forKey: Keys.startupTab) }
    }

    var calendarFilterPresets: [CalendarFilterPreset] {
        didSet { saveCalendarFilterPresets() }
    }

    var watchedPairSymbols: [String] {
        didSet { defaults.set(watchedPairSymbols, forKey: Keys.watchedPairSymbols) }
    }

    var highImpactNotificationLeadTimeMinutes: Int {
        didSet { defaults.set(highImpactNotificationLeadTimeMinutes, forKey: Keys.highImpactNotificationLeadTimeMinutes) }
    }

    var mediumImpactNotificationLeadTimeMinutes: Int {
        didSet { defaults.set(mediumImpactNotificationLeadTimeMinutes, forKey: Keys.mediumImpactNotificationLeadTimeMinutes) }
    }

    var lowImpactNotificationLeadTimeMinutes: Int {
        didSet { defaults.set(lowImpactNotificationLeadTimeMinutes, forKey: Keys.lowImpactNotificationLeadTimeMinutes) }
    }

    var notificationSoundOption: NotificationSoundOption {
        didSet { defaults.set(notificationSoundOption.rawValue, forKey: Keys.notificationSoundOption) }
    }

    var quietHoursEnabled: Bool {
        didSet { defaults.set(quietHoursEnabled, forKey: Keys.quietHoursEnabled) }
    }

    var quietHoursStartMinutes: Int {
        didSet { defaults.set(quietHoursStartMinutes, forKey: Keys.quietHoursStartMinutes) }
    }

    var quietHoursEndMinutes: Int {
        didSet { defaults.set(quietHoursEndMinutes, forKey: Keys.quietHoursEndMinutes) }
    }

    var sydneySessionNotificationsEnabled: Bool {
        didSet { defaults.set(sydneySessionNotificationsEnabled, forKey: Keys.sydneySessionNotificationsEnabled) }
    }

    var tokyoSessionNotificationsEnabled: Bool {
        didSet { defaults.set(tokyoSessionNotificationsEnabled, forKey: Keys.tokyoSessionNotificationsEnabled) }
    }

    var londonSessionNotificationsEnabled: Bool {
        didSet { defaults.set(londonSessionNotificationsEnabled, forKey: Keys.londonSessionNotificationsEnabled) }
    }

    var newYorkSessionNotificationsEnabled: Bool {
        didSet { defaults.set(newYorkSessionNotificationsEnabled, forKey: Keys.newYorkSessionNotificationsEnabled) }
    }

    var sydneySessionOpenNotificationsEnabled: Bool {
        didSet { defaults.set(sydneySessionOpenNotificationsEnabled, forKey: Keys.sydneySessionOpenNotificationsEnabled) }
    }

    var tokyoSessionOpenNotificationsEnabled: Bool {
        didSet { defaults.set(tokyoSessionOpenNotificationsEnabled, forKey: Keys.tokyoSessionOpenNotificationsEnabled) }
    }

    var londonSessionOpenNotificationsEnabled: Bool {
        didSet { defaults.set(londonSessionOpenNotificationsEnabled, forKey: Keys.londonSessionOpenNotificationsEnabled) }
    }

    var newYorkSessionOpenNotificationsEnabled: Bool {
        didSet { defaults.set(newYorkSessionOpenNotificationsEnabled, forKey: Keys.newYorkSessionOpenNotificationsEnabled) }
    }

    var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Keys.hasCompletedOnboarding) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.minimumImpact = ImpactLevel(rawValue: defaults.string(forKey: Keys.minimumImpact) ?? "") ?? .low
        self.selectedCurrencyCodes = Self.loadSelectedCurrencyCodes(from: defaults)
        self.selectedCountryCode = defaults.string(forKey: Keys.selectedCountryCode)
        self.selectedCategory = defaults.string(forKey: Keys.selectedCategory)
        self.showOnlyWatchedPairs = defaults.bool(forKey: Keys.showOnlyWatchedPairs)
        self.use24HourTime = defaults.bool(forKey: Keys.use24HourTime)
        self.useUTC = defaults.bool(forKey: Keys.useUTC)
        self.manualTimeZoneIdentifier = defaults.string(forKey: Keys.manualTimeZoneIdentifier)
        self.preferredAppearance = AppAppearance(rawValue: defaults.string(forKey: Keys.preferredAppearance) ?? "") ?? .dark
        self.startupTab = AppTab(rawValue: defaults.string(forKey: Keys.startupTab) ?? "") ?? .today
        self.calendarFilterPresets = Self.loadCalendarFilterPresets(from: defaults)
        self.watchedPairSymbols = defaults.stringArray(forKey: Keys.watchedPairSymbols) ?? []
        self.highImpactNotificationLeadTimeMinutes = defaults.object(forKey: Keys.highImpactNotificationLeadTimeMinutes) as? Int ?? 30
        self.mediumImpactNotificationLeadTimeMinutes = defaults.object(forKey: Keys.mediumImpactNotificationLeadTimeMinutes) as? Int ?? 15
        self.lowImpactNotificationLeadTimeMinutes = defaults.object(forKey: Keys.lowImpactNotificationLeadTimeMinutes) as? Int ?? 0
        self.notificationSoundOption = NotificationSoundOption(rawValue: defaults.string(forKey: Keys.notificationSoundOption) ?? "") ?? .subtle
        self.quietHoursEnabled = defaults.bool(forKey: Keys.quietHoursEnabled)
        self.quietHoursStartMinutes = defaults.object(forKey: Keys.quietHoursStartMinutes) as? Int ?? 22 * 60
        self.quietHoursEndMinutes = defaults.object(forKey: Keys.quietHoursEndMinutes) as? Int ?? 6 * 60
        self.sydneySessionNotificationsEnabled = Self.boolValue(
            forKey: Keys.sydneySessionNotificationsEnabled,
            fallbackKey: Keys.asianSessionNotificationsEnabled,
            defaults: defaults
        )
        self.tokyoSessionNotificationsEnabled = defaults.bool(forKey: Keys.tokyoSessionNotificationsEnabled)
        self.londonSessionNotificationsEnabled = defaults.bool(forKey: Keys.londonSessionNotificationsEnabled)
        self.newYorkSessionNotificationsEnabled = defaults.bool(forKey: Keys.newYorkSessionNotificationsEnabled)
        self.sydneySessionOpenNotificationsEnabled = Self.boolValue(
            forKey: Keys.sydneySessionOpenNotificationsEnabled,
            fallbackKey: Keys.asianSessionOpenNotificationsEnabled,
            defaults: defaults
        )
        self.tokyoSessionOpenNotificationsEnabled = defaults.bool(forKey: Keys.tokyoSessionOpenNotificationsEnabled)
        self.londonSessionOpenNotificationsEnabled = defaults.bool(forKey: Keys.londonSessionOpenNotificationsEnabled)
        self.newYorkSessionOpenNotificationsEnabled = defaults.bool(forKey: Keys.newYorkSessionOpenNotificationsEnabled)
        self.hasCompletedOnboarding = defaults.bool(forKey: Keys.hasCompletedOnboarding)

        if defaults.object(forKey: Keys.firstLaunchDate) == nil {
            defaults.set(Date(), forKey: Keys.firstLaunchDate)
        }
    }

    func isPairWatched(_ symbol: String) -> Bool {
        watchedPairSymbols.contains(symbol)
    }

    func toggleWatch(for symbol: String) {
        if isPairWatched(symbol) {
            watchedPairSymbols.removeAll { $0 == symbol }
        } else {
            watchedPairSymbols.append(symbol)
            watchedPairSymbols.sort()
        }
    }

    var watchedPairCurrencyCodes: Set<String> {
        Set(watchedPairSymbols.flatMap(Self.currencyCodes(inPairSymbol:)))
    }

    func matchesWatchedPair(_ event: EconomicEvent) -> Bool {
        let normalizedEventPairs = Set(event.relatedPairs.map(Self.normalizePairSymbol(_:)))
        let normalizedWatchedPairs = Set(watchedPairSymbols.map(Self.normalizePairSymbol(_:)))

        if !normalizedEventPairs.isDisjoint(with: normalizedWatchedPairs) {
            return true
        }

        return watchedPairCurrencyCodes.contains(event.currencyCode.uppercased())
    }

    @discardableResult
    func saveCurrentCalendarFilterPreset(named name: String) -> CalendarFilterPreset? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return nil }

        let preset = CalendarFilterPreset(
            name: trimmedName,
            minimumImpact: minimumImpact,
            selectedCurrencyCodes: selectedCurrencyCodes,
            selectedCountryCode: selectedCountryCode,
            selectedCategory: selectedCategory,
            showOnlyWatchedPairs: showOnlyWatchedPairs
        )

        let remainingPresets = calendarFilterPresets.filter {
            $0.name.caseInsensitiveCompare(trimmedName) != .orderedSame
        }
        calendarFilterPresets = Array(([preset] + remainingPresets).prefix(12))
        return preset
    }

    func applyCalendarFilterPreset(_ preset: CalendarFilterPreset) {
        minimumImpact = preset.minimumImpact
        selectedCurrencyCodes = preset.selectedCurrencyCodes
        selectedCountryCode = preset.selectedCountryCode
        selectedCategory = preset.selectedCategory
        showOnlyWatchedPairs = preset.showOnlyWatchedPairs
    }

    func deleteCalendarFilterPreset(_ preset: CalendarFilterPreset) {
        calendarFilterPresets.removeAll { $0.id == preset.id }
    }

    func toggleCurrencyFilter(_ code: String) {
        if selectedCurrencyCodes.contains(code) {
            selectedCurrencyCodes.removeAll { $0 == code }
        } else {
            selectedCurrencyCodes.append(code)
            selectedCurrencyCodes.sort()
        }
    }

    func reset() {
        minimumImpact = .low
        selectedCurrencyCodes = []
        selectedCountryCode = nil
        selectedCategory = nil
        showOnlyWatchedPairs = false
        use24HourTime = false
        useUTC = false
        manualTimeZoneIdentifier = nil
        preferredAppearance = .dark
        startupTab = .today
        calendarFilterPresets = []
        watchedPairSymbols = []
        highImpactNotificationLeadTimeMinutes = 30
        mediumImpactNotificationLeadTimeMinutes = 15
        lowImpactNotificationLeadTimeMinutes = 0
        notificationSoundOption = .subtle
        quietHoursEnabled = false
        quietHoursStartMinutes = 22 * 60
        quietHoursEndMinutes = 6 * 60
        sydneySessionNotificationsEnabled = false
        tokyoSessionNotificationsEnabled = false
        londonSessionNotificationsEnabled = false
        newYorkSessionNotificationsEnabled = false
        sydneySessionOpenNotificationsEnabled = false
        tokyoSessionOpenNotificationsEnabled = false
        londonSessionOpenNotificationsEnabled = false
        newYorkSessionOpenNotificationsEnabled = false
    }

    private func saveCalendarFilterPresets() {
        if let data = try? JSONEncoder().encode(calendarFilterPresets) {
            defaults.set(data, forKey: Keys.calendarFilterPresets)
        }
    }

    private static func loadCalendarFilterPresets(from defaults: UserDefaults) -> [CalendarFilterPreset] {
        guard let data = defaults.data(forKey: Keys.calendarFilterPresets),
              let presets = try? JSONDecoder().decode([CalendarFilterPreset].self, from: data) else {
            return []
        }

        return presets
    }

    private static func loadSelectedCurrencyCodes(from defaults: UserDefaults) -> [String] {
        if let currencyCodes = defaults.stringArray(forKey: Keys.selectedCurrencyCodes) {
            return currencyCodes.sorted()
        }

        if let legacyCurrencyCode = defaults.string(forKey: Keys.selectedCurrencyCode) {
            return [legacyCurrencyCode]
        }

        return []
    }

    private func setOptionalString(_ value: String?, forKey key: String) {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    var effectiveTimeZone: TimeZone {
        if useUTC {
            return .gmt
        }

        if let manualTimeZoneIdentifier, let timeZone = TimeZone(identifier: manualTimeZoneIdentifier) {
            return timeZone
        }

        return .current
    }

    var effectiveColorScheme: ColorScheme? {
        preferredAppearance.colorScheme
    }

    var firstLaunchDate: Date {
        defaults.object(forKey: Keys.firstLaunchDate) as? Date ?? Date()
    }

    var shouldShowRateAction: Bool {
        Date().timeIntervalSince(firstLaunchDate) >= 14 * 24 * 60 * 60
    }

    func isWithinQuietHours(on date: Date, timeZone: TimeZone? = nil) -> Bool {
        guard quietHoursEnabled else {
            return false
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone ?? effectiveTimeZone
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let minutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)

        if quietHoursEndMinutes <= quietHoursStartMinutes {
            return minutes >= quietHoursStartMinutes || minutes < quietHoursEndMinutes
        }

        return minutes >= quietHoursStartMinutes && minutes < quietHoursEndMinutes
    }

    private static func currencyCodes(inPairSymbol symbol: String) -> [String] {
        let normalizedSymbol = normalizePairSymbol(symbol)
        guard normalizedSymbol.count == 6 else {
            return []
        }

        return [
            String(normalizedSymbol.prefix(3)),
            String(normalizedSymbol.suffix(3))
        ]
    }

    private static func normalizePairSymbol(_ symbol: String) -> String {
        symbol
            .uppercased()
            .filter(\.isLetter)
    }

    private static func boolValue(forKey key: String, fallbackKey: String, defaults: UserDefaults) -> Bool {
        if defaults.object(forKey: key) != nil {
            return defaults.bool(forKey: key)
        }

        return defaults.bool(forKey: fallbackKey)
    }
}

struct CalendarFilterPreset: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var minimumImpact: ImpactLevel
    var selectedCurrencyCodes: [String]
    var selectedCountryCode: String?
    var selectedCategory: String?
    var showOnlyWatchedPairs: Bool

    var selectedCurrencyCode: String? { selectedCurrencyCodes.first }

    init(
        id: UUID = UUID(),
        name: String,
        minimumImpact: ImpactLevel,
        selectedCurrencyCodes: [String],
        selectedCountryCode: String?,
        selectedCategory: String?,
        showOnlyWatchedPairs: Bool
    ) {
        self.id = id
        self.name = name
        self.minimumImpact = minimumImpact
        self.selectedCurrencyCodes = selectedCurrencyCodes.sorted()
        self.selectedCountryCode = selectedCountryCode
        self.selectedCategory = selectedCategory
        self.showOnlyWatchedPairs = showOnlyWatchedPairs
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case minimumImpact
        case selectedCurrencyCode
        case selectedCurrencyCodes
        case selectedCountryCode
        case selectedCategory
        case showOnlyWatchedPairs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.minimumImpact = try container.decode(ImpactLevel.self, forKey: .minimumImpact)
        self.selectedCountryCode = try container.decodeIfPresent(String.self, forKey: .selectedCountryCode)
        self.selectedCategory = try container.decodeIfPresent(String.self, forKey: .selectedCategory)
        self.showOnlyWatchedPairs = try container.decode(Bool.self, forKey: .showOnlyWatchedPairs)

        if let selectedCurrencyCodes = try container.decodeIfPresent([String].self, forKey: .selectedCurrencyCodes) {
            self.selectedCurrencyCodes = selectedCurrencyCodes.sorted()
        } else if let selectedCurrencyCode = try container.decodeIfPresent(String.self, forKey: .selectedCurrencyCode) {
            self.selectedCurrencyCodes = [selectedCurrencyCode]
        } else {
            self.selectedCurrencyCodes = []
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(minimumImpact, forKey: .minimumImpact)
        try container.encode(selectedCurrencyCodes, forKey: .selectedCurrencyCodes)
        try container.encodeIfPresent(selectedCurrencyCode, forKey: .selectedCurrencyCode)
        try container.encodeIfPresent(selectedCountryCode, forKey: .selectedCountryCode)
        try container.encodeIfPresent(selectedCategory, forKey: .selectedCategory)
        try container.encode(showOnlyWatchedPairs, forKey: .showOnlyWatchedPairs)
    }

    var summary: String {
        var items: [String] = []

        switch minimumImpact {
        case .high:
            items.append("High impact")
        case .medium:
            items.append("Market movers")
        case .low:
            items.append("All events")
        }

        if !selectedCurrencyCodes.isEmpty {
            items.append(selectedCurrencyCodes.joined(separator: ", "))
        }

        if let selectedCountryCode {
            items.append(CountryDisplay.name(for: selectedCountryCode))
        }

        if let selectedCategory {
            items.append(selectedCategory)
        }

        if showOnlyWatchedPairs {
            items.append("Watchlist")
        }

        return items.joined(separator: " • ")
    }
}

enum NotificationSoundOption: String, CaseIterable, Identifiable {
    case subtle
    case prominent

    var id: String { rawValue }

    var label: String { rawValue.capitalized }

    var unNotificationSound: UNNotificationSound {
        switch self {
        case .subtle:
            .default
        case .prominent:
            // Critical-alert sounds require a special Apple entitlement.
            .default
        }
    }
}


enum AppAppearance: String, CaseIterable, Identifiable {
    case dark
    case light
    case system

    var id: String { rawValue }

    var label: String { rawValue.capitalized }

    var colorScheme: ColorScheme? {
        switch self {
        case .dark:
            .dark
        case .light:
            .light
        case .system:
            nil
        }
    }
}

private enum Keys {
    static let minimumImpact = "preferences.minimumImpact"
    static let selectedCurrencyCode = "preferences.selectedCurrencyCode"
    static let selectedCurrencyCodes = "preferences.selectedCurrencyCodes"
    static let selectedCountryCode = "preferences.selectedCountryCode"
    static let selectedCategory = "preferences.selectedCategory"
    static let showOnlyWatchedPairs = "preferences.showOnlyWatchedPairs"
    static let use24HourTime = "preferences.use24HourTime"
    static let useUTC = "preferences.useUTC"
    static let manualTimeZoneIdentifier = "preferences.manualTimeZoneIdentifier"
    static let preferredAppearance = "preferences.preferredAppearance"
    static let startupTab = "preferences.startupTab"
    static let calendarFilterPresets = "preferences.calendarFilterPresets"
    static let watchedPairSymbols = "preferences.watchedPairSymbols"
    static let highImpactNotificationLeadTimeMinutes = "preferences.highImpactNotificationLeadTimeMinutes"
    static let mediumImpactNotificationLeadTimeMinutes = "preferences.mediumImpactNotificationLeadTimeMinutes"
    static let lowImpactNotificationLeadTimeMinutes = "preferences.lowImpactNotificationLeadTimeMinutes"
    static let notificationSoundOption = "preferences.notificationSoundOption"
    static let quietHoursEnabled = "preferences.quietHoursEnabled"
    static let quietHoursStartMinutes = "preferences.quietHoursStartMinutes"
    static let quietHoursEndMinutes = "preferences.quietHoursEndMinutes"
    static let asianSessionNotificationsEnabled = "preferences.asianSessionNotificationsEnabled"
    static let sydneySessionNotificationsEnabled = "preferences.sydneySessionNotificationsEnabled"
    static let tokyoSessionNotificationsEnabled = "preferences.tokyoSessionNotificationsEnabled"
    static let londonSessionNotificationsEnabled = "preferences.londonSessionNotificationsEnabled"
    static let newYorkSessionNotificationsEnabled = "preferences.newYorkSessionNotificationsEnabled"
    static let asianSessionOpenNotificationsEnabled = "preferences.asianSessionOpenNotificationsEnabled"
    static let sydneySessionOpenNotificationsEnabled = "preferences.sydneySessionOpenNotificationsEnabled"
    static let tokyoSessionOpenNotificationsEnabled = "preferences.tokyoSessionOpenNotificationsEnabled"
    static let londonSessionOpenNotificationsEnabled = "preferences.londonSessionOpenNotificationsEnabled"
    static let newYorkSessionOpenNotificationsEnabled = "preferences.newYorkSessionOpenNotificationsEnabled"
    static let hasCompletedOnboarding = "preferences.hasCompletedOnboarding"
    static let firstLaunchDate = "preferences.firstLaunchDate"
}
