import Foundation
import UserNotifications

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
            try? await scheduleSessionNotification(for: .asian, preferences: preferences)
        }
        if preferences.londonSessionNotificationsEnabled {
            try? await scheduleSessionNotification(for: .london, preferences: preferences)
        }
        if preferences.newYorkSessionNotificationsEnabled {
            try? await scheduleSessionNotification(for: .newYork, preferences: preferences)
        }
        if preferences.asianLondonOverlapNotificationsEnabled {
            try? await scheduleOverlapNotification(for: .asianLondon, preferences: preferences)
        }
        if preferences.londonNewYorkOverlapNotificationsEnabled {
            try? await scheduleOverlapNotification(for: .londonNewYork, preferences: preferences)
        }
    }

    static func scheduleSessionNotification(for definition: ForexSessionDefinition, preferences: UserPreferences) async throws {
        let nextStart = SessionPresentation.nextInterval(for: definition, after: Date()).start
        try await scheduleNotification(
            identifier: prefix + "session." + definition.id,
            title: "\(definition.title) Session",
            body: "\(definition.title) opens in 15 minutes.",
            fireDate: nextStart.addingTimeInterval(-15 * 60),
            preferences: preferences
        )
    }

    static func removeSessionNotification(for definition: ForexSessionDefinition) async {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [prefix + "session." + definition.id])
    }

    static func scheduleOverlapNotification(for definition: ForexOverlapDefinition, preferences: UserPreferences) async throws {
        let nextStart = SessionPresentation.nextOverlapInterval(for: definition, after: Date()).start
        try await scheduleNotification(
            identifier: prefix + "overlap." + definition.id,
            title: definition.title,
            body: "\(definition.title) starts in 15 minutes.",
            fireDate: nextStart.addingTimeInterval(-15 * 60),
            preferences: preferences
        )
    }

    static func removeOverlapNotification(for definition: ForexOverlapDefinition) async {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [prefix + "overlap." + definition.id])
    }

    private static func scheduleNotification(identifier: String, title: String, body: String, fireDate: Date, preferences: UserPreferences) async throws {
        guard fireDate > Date() else {
            throw SessionNotificationError.notificationWindowPassed
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
    case notificationWindowPassed
    case quietHoursBlocked

    var errorDescription: String? {
        switch self {
        case .authorizationDenied:
            "Notifications are disabled for FX News."
        case .notificationWindowPassed:
            "The next 15-minute warning for that session has already passed."
        case .quietHoursBlocked:
            "That alert falls within your quiet hours."
        }
    }
}
