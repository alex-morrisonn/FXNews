import Foundation
import UserNotifications

enum SessionNotificationTiming: String {
    case warning
    case open

    var identifierComponent: String { rawValue }

    var titleSuffix: String {
        switch self {
        case .warning:
            "warning"
        case .open:
            "open"
        }
    }

    var bodyText: String {
        switch self {
        case .warning:
            "opens in 15 minutes."
        case .open:
            "is open now."
        }
    }

    var errorDescription: String {
        switch self {
        case .warning:
            "The next 15-minute warning for that session has already passed."
        case .open:
            "The next session open for that alert has already passed."
        }
    }
}

enum SessionNotificationStore {
    private static let prefix = "fxnews.sessions."

    static func resyncEnabledNotifications(preferences: UserPreferences, hasProAccess: Bool) async {
        let existingIdentifiers = await pendingIdentifiers()
        let sessionIdentifiers = existingIdentifiers.filter { $0.hasPrefix(prefix) }

        guard hasProAccess else {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: sessionIdentifiers)
            return
        }

        guard await NotificationAuthorizationStore.canScheduleNotificationsWithoutPrompt() else {
            return
        }

        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: sessionIdentifiers)

        if preferences.sydneySessionNotificationsEnabled {
            try? await scheduleSessionNotification(for: .sydney, timing: .warning, preferences: preferences)
        }
        if preferences.tokyoSessionNotificationsEnabled {
            try? await scheduleSessionNotification(for: .tokyo, timing: .warning, preferences: preferences)
        }
        if preferences.londonSessionNotificationsEnabled {
            try? await scheduleSessionNotification(for: .london, timing: .warning, preferences: preferences)
        }
        if preferences.newYorkSessionNotificationsEnabled {
            try? await scheduleSessionNotification(for: .newYork, timing: .warning, preferences: preferences)
        }
        if preferences.sydneySessionOpenNotificationsEnabled {
            try? await scheduleSessionNotification(for: .sydney, timing: .open, preferences: preferences)
        }
        if preferences.tokyoSessionOpenNotificationsEnabled {
            try? await scheduleSessionNotification(for: .tokyo, timing: .open, preferences: preferences)
        }
        if preferences.londonSessionOpenNotificationsEnabled {
            try? await scheduleSessionNotification(for: .london, timing: .open, preferences: preferences)
        }
        if preferences.newYorkSessionOpenNotificationsEnabled {
            try? await scheduleSessionNotification(for: .newYork, timing: .open, preferences: preferences)
        }
    }

    static func scheduleSessionNotification(
        for definition: MarketBoardDefinition,
        timing: SessionNotificationTiming,
        preferences: UserPreferences
    ) async throws {
        let nextStart = SessionPresentation.nextMarketInterval(for: definition, after: Date()).start
        let fireDate: Date

        switch timing {
        case .warning:
            fireDate = nextStart.addingTimeInterval(-15 * 60)
        case .open:
            fireDate = nextStart
        }

        try await scheduleNotification(
            identifier: prefix + "session." + notificationIdentifierComponent(for: definition) + "." + timing.identifierComponent,
            title: "\(definition.cityName) Session",
            body: "\(definition.cityName) \(timing.bodyText)",
            fireDate: fireDate,
            additionalIdentifiersToRemove: legacyNotificationIdentifiers(for: definition, timing: timing),
            preferences: preferences,
            timing: timing
        )
    }

    static func removeSessionNotification(for definition: MarketBoardDefinition, timing: SessionNotificationTiming) async {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [
                prefix + "session." + notificationIdentifierComponent(for: definition) + "." + timing.identifierComponent
            ] + legacyNotificationIdentifiers(for: definition, timing: timing)
        )
    }

    private static func notificationIdentifierComponent(for definition: MarketBoardDefinition) -> String {
        switch definition {
        case .sydney:
            "sydney"
        case .tokyo:
            "tokyo"
        case .london:
            "london"
        case .newYork:
            "new-york"
        }
    }

    private static func legacyNotificationIdentifiers(
        for definition: MarketBoardDefinition,
        timing: SessionNotificationTiming
    ) -> [String] {
        switch definition {
        case .sydney:
            [prefix + "session.Asian." + timing.identifierComponent]
        case .tokyo, .london, .newYork:
            []
        }
    }

    private static func scheduleNotification(
        identifier: String,
        title: String,
        body: String,
        fireDate: Date,
        additionalIdentifiersToRemove: [String] = [],
        preferences: UserPreferences,
        timing: SessionNotificationTiming
    ) async throws {
        guard fireDate > Date() else {
            throw SessionNotificationError.notificationWindowPassed(timing)
        }

        guard !preferences.isWithinQuietHours(on: fireDate) else {
            throw SessionNotificationError.quietHoursBlocked
        }

        let granted = try await requestAuthorization()
        guard granted else {
            throw SessionNotificationError.authorizationDenied
        }

        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier] + additionalIdentifiersToRemove)

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = preferences.notificationSoundOption.unNotificationSound

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(fireDate.timeIntervalSinceNow, 1), repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        try await add(request, center: center)
    }

    private static func requestAuthorization() async throws -> Bool {
        try await NotificationAuthorizationStore.requestAuthorizationIfNeeded()
    }

    private static func add(_ request: UNNotificationRequest, center: UNUserNotificationCenter) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            center.add(request) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    private static func pendingIdentifiers() async -> [String] {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
                continuation.resume(returning: requests.map(\.identifier))
            }
        }
    }
}

private enum SessionNotificationError: LocalizedError {
    case authorizationDenied
    case notificationWindowPassed(SessionNotificationTiming)
    case quietHoursBlocked

    var errorDescription: String? {
        switch self {
        case .authorizationDenied:
            "Notifications are disabled for FX News."
        case let .notificationWindowPassed(timing):
            timing.errorDescription
        case .quietHoursBlocked:
            "That alert falls within your quiet hours."
        }
    }
}
