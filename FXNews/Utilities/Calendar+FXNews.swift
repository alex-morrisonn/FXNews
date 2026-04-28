import Foundation

extension Calendar {
    static let utcGregorian: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }()

    static func currentWeekIntervalInUTC(referenceDate: Date = Date()) -> DateInterval {
        tradingWeekInterval(referenceDate: referenceDate, weekOffset: 0, timeZone: .gmt)
    }

    static func tradingWeekInterval(
        referenceDate: Date = Date(),
        weekOffset: Int = 0,
        timeZone: TimeZone = .current
    ) -> DateInterval {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4

        let currentWeek = calendar.dateInterval(of: .weekOfYear, for: referenceDate)
            ?? DateInterval(start: referenceDate, duration: 7 * 24 * 60 * 60)
        let shiftedStart = calendar.date(byAdding: .weekOfYear, value: weekOffset, to: currentWeek.start) ?? currentWeek.start
        let shiftedEnd = calendar.date(byAdding: .day, value: 7, to: shiftedStart) ?? currentWeek.end
        return DateInterval(start: shiftedStart, end: shiftedEnd)
    }

    static func tradingWeekdays(
        referenceDate: Date = Date(),
        weekOffset: Int = 0,
        timeZone: TimeZone = .current
    ) -> [Date] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4

        let weekInterval = tradingWeekInterval(referenceDate: referenceDate, weekOffset: weekOffset, timeZone: timeZone)
        return (0..<5).compactMap { dayOffset in
            calendar.date(byAdding: .day, value: dayOffset, to: weekInterval.start)
        }
    }

    func date(in interval: DateInterval, weekday: Int, hour: Int, minute: Int) -> Date {
        let weekStart = interval.start
        let startWeekday = component(.weekday, from: weekStart)
        let dayOffset = (weekday - startWeekday + 7) % 7

        return date(
            bySettingHour: hour,
            minute: minute,
            second: 0,
            of: self.date(byAdding: .day, value: dayOffset, to: weekStart) ?? weekStart
        ) ?? weekStart
    }
}
