import Foundation

enum EventDateFormatter {
    static func dayString(from date: Date, useUTC: Bool) -> String {
        dayString(from: date, timeZone: timeZone(useUTC: useUTC))
    }

    static func dayString(from date: Date, timeZone: TimeZone) -> String {
        string(from: date, cacheKey: dayFormatterKey(timeZone: timeZone)) {
            let formatter = DateFormatter()
            formatter.calendar = .current
            formatter.timeZone = timeZone
            formatter.dateFormat = "EEEE, MMM d"
            return formatter
        }
    }

    static func monthDayString(from date: Date, useUTC: Bool) -> String {
        monthDayString(from: date, timeZone: timeZone(useUTC: useUTC))
    }

    static func monthDayString(from date: Date, timeZone: TimeZone) -> String {
        string(from: date, cacheKey: monthDayFormatterKey(timeZone: timeZone)) {
            let formatter = DateFormatter()
            formatter.calendar = .current
            formatter.timeZone = timeZone
            formatter.dateFormat = "MMM d"
            return formatter
        }
    }

    static func timeString(from date: Date, useUTC: Bool, use24HourTime: Bool) -> String {
        timeString(from: date, timeZone: timeZone(useUTC: useUTC), use24HourTime: use24HourTime)
    }

    static func timeString(from date: Date, timeZone: TimeZone, use24HourTime: Bool) -> String {
        string(from: date, cacheKey: timeFormatterKey(timeZone: timeZone, use24HourTime: use24HourTime)) {
            let formatter = DateFormatter()
            formatter.calendar = .current
            formatter.timeZone = timeZone
            formatter.dateStyle = .none
            // Use a fixed POSIX locale so the 12/24-hour toggle is not overridden by device locale defaults.
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = use24HourTime ? "HH:mm" : "h:mm a"
            return formatter
        }
    }

    static func relativeString(for date: Date, relativeTo referenceDate: Date = Date()) -> String {
        lock.lock()
        defer { lock.unlock() }

        return relativeFormatter.localizedString(for: date, relativeTo: referenceDate)
    }

    private static let lock = NSLock()
    private static var formatters: [String: DateFormatter] = [:]
    private static let relativeFormatter = RelativeDateTimeFormatter()

    private static func string(from date: Date, cacheKey: String, makeFormatter: () -> DateFormatter) -> String {
        lock.lock()
        defer { lock.unlock() }

        if let formatter = formatters[cacheKey] {
            return formatter.string(from: date)
        }

        let formatter = makeFormatter()
        formatters[cacheKey] = formatter
        return formatter.string(from: date)
    }

    static func timeZoneLabel(for timeZone: TimeZone) -> String {
        timeZone.localizedName(for: .shortStandard, locale: .current) ?? timeZone.identifier
    }

    private static func dayFormatterKey(timeZone: TimeZone) -> String {
        "day|\(timeZone.identifier)"
    }

    private static func timeFormatterKey(timeZone: TimeZone, use24HourTime: Bool) -> String {
        "time|\(timeZone.identifier)|\(use24HourTime ? "24" : "12")"
    }

    private static func monthDayFormatterKey(timeZone: TimeZone) -> String {
        "monthDay|\(timeZone.identifier)"
    }

    private static func timeZone(useUTC: Bool) -> TimeZone {
        useUTC ? .gmt : .current
    }
}
