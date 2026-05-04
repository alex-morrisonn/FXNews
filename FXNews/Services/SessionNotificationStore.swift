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

    static func resyncEnabledNotifications(preferences: UserPreferences) async {
        guard await NotificationAuthorizationStore.canScheduleNotificationsWithoutPrompt() else {
            return
        }

        let existingIdentifiers = await pendingIdentifiers()
        let sessionIdentifiers = existingIdentifiers.filter { $0.hasPrefix(prefix) }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: sessionIdentifiers)

        if preferences.asianSessionNotificationsEnabled {
            try? await scheduleSessionNotification(for: .asian, timing: .warning, preferences: preferences)
        }
        if preferences.londonSessionNotificationsEnabled {
            try? await scheduleSessionNotification(for: .london, timing: .warning, preferences: preferences)
        }
        if preferences.newYorkSessionNotificationsEnabled {
            try? await scheduleSessionNotification(for: .newYork, timing: .warning, preferences: preferences)
        }
        if preferences.asianSessionOpenNotificationsEnabled {
            try? await scheduleSessionNotification(for: .asian, timing: .open, preferences: preferences)
        }
        if preferences.londonSessionOpenNotificationsEnabled {
            try? await scheduleSessionNotification(for: .london, timing: .open, preferences: preferences)
        }
        if preferences.newYorkSessionOpenNotificationsEnabled {
            try? await scheduleSessionNotification(for: .newYork, timing: .open, preferences: preferences)
        }
    }

    static func scheduleSessionNotification(
        for definition: ForexSessionDefinition,
        timing: SessionNotificationTiming,
        preferences: UserPreferences
    ) async throws {
        let nextStart = SessionPresentation.nextInterval(for: definition, after: Date()).start
        let fireDate: Date

        switch timing {
        case .warning:
            fireDate = nextStart.addingTimeInterval(-15 * 60)
        case .open:
            fireDate = nextStart
        }

        try await scheduleNotification(
            identifier: prefix + "session." + definition.id + "." + timing.identifierComponent,
            title: "\(definition.title) Session",
            body: "\(definition.title) \(timing.bodyText)",
            fireDate: fireDate,
            preferences: preferences,
            timing: timing
        )
    }

    static func removeSessionNotification(for definition: ForexSessionDefinition, timing: SessionNotificationTiming) async {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [prefix + "session." + definition.id + "." + timing.identifierComponent]
        )
    }

    private static func scheduleNotification(
        identifier: String,
        title: String,
        body: String,
        fireDate: Date,
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
        center.removePendingNotificationRequests(withIdentifiers: [identifier])

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
