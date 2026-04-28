import Foundation

enum SessionPresentation {
    static let newYorkTimeZone = TimeZone(identifier: "America/New_York") ?? .current

    static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }()

    static let newYorkCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = newYorkTimeZone
        return calendar
    }()

    static let localCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }()

    static func intervalsAroundNow(for definition: ForexSessionDefinition, now: Date) -> [DateInterval] {
        (-2...3).compactMap { sessionInterval(for: definition, around: now, dayOffset: $0) }
            .filter { $0.end > now.addingTimeInterval(-24 * 60 * 60) }
            .sorted { $0.start < $1.start }
    }

    static func nextInterval(for definition: ForexSessionDefinition, after date: Date) -> DateInterval {
        intervalsAroundNow(for: definition, now: date)
            .first(where: { $0.start > date })
            ?? sessionInterval(for: definition, around: date, dayOffset: 4)
            ?? DateInterval(start: date, duration: 60)
    }

    static func marketIntervalsAroundNow(for definition: MarketBoardDefinition, now: Date) -> [DateInterval] {
        (-2...3).compactMap { marketInterval(for: definition, around: now, dayOffset: $0) }
            .filter { $0.end > now.addingTimeInterval(-24 * 60 * 60) }
            .sorted { $0.start < $1.start }
    }

    static func nextMarketInterval(for definition: MarketBoardDefinition, after date: Date) -> DateInterval {
        marketIntervalsAroundNow(for: definition, now: date)
            .first(where: { $0.start > date })
            ?? marketInterval(for: definition, around: date, dayOffset: 4)
            ?? DateInterval(start: date, duration: 60)
    }

    static func overlapIntervalsAroundNow(for definition: ForexOverlapDefinition, now: Date) -> [DateInterval] {
        let firstSession = intervalsAroundNow(for: definition.sessions.0, now: now)
        let secondSession = intervalsAroundNow(for: definition.sessions.1, now: now)

        let overlaps = firstSession.flatMap { first in
            secondSession.compactMap { second in
                first.intersection(with: second)
            }
        }

        return overlaps
            .filter { $0.duration > 0 }
            .sorted { $0.start < $1.start }
    }

    static func nextOverlapInterval(for definition: ForexOverlapDefinition, after date: Date) -> DateInterval {
        overlapIntervalsAroundNow(for: definition, now: date)
            .first(where: { $0.start > date })
            ?? DateInterval(start: nextForexMarketOpen(after: date), duration: 60)
    }

    static func isForexMarketOpen(at date: Date) -> Bool {
        let components = newYorkCalendar.dateComponents([.weekday, .hour, .minute], from: date)
        let weekday = components.weekday ?? 1
        let minutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)

        if weekday == 6 {
            return minutes < 17 * 60
        }

        if weekday == 7 {
            return false
        }

        if weekday == 1 {
            return minutes >= 17 * 60
        }

        return true
    }

    static func nextForexMarketOpen(after date: Date) -> Date {
        if isForexMarketOpen(at: date) {
            return date
        }

        let components = newYorkCalendar.dateComponents([.weekday], from: date)
        let weekday = components.weekday ?? 1
        let startOfDay = newYorkCalendar.startOfDay(for: date)

        switch weekday {
        case 6:
            let sunday = newYorkCalendar.date(byAdding: .day, value: 2, to: startOfDay) ?? startOfDay
            return newYorkCalendar.date(bySettingHour: 17, minute: 0, second: 0, of: sunday) ?? date
        case 7:
            let sunday = newYorkCalendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
            return newYorkCalendar.date(bySettingHour: 17, minute: 0, second: 0, of: sunday) ?? date
        case 1:
            return newYorkCalendar.date(bySettingHour: 17, minute: 0, second: 0, of: startOfDay) ?? date
        default:
            return date
        }
    }

    static func localWindowLabel(for definition: ForexSessionDefinition, referenceDate: Date, displayTimeZone: TimeZone = .current) -> String {
        let interval = nextRelevantInterval(for: definition, referenceDate: referenceDate)
        return "\(localTime(interval.start, displayTimeZone: displayTimeZone)) - \(localTime(interval.end, displayTimeZone: displayTimeZone))"
    }

    static func localWindowLabel(for definition: ForexOverlapDefinition, referenceDate: Date, displayTimeZone: TimeZone = .current) -> String {
        let interval = overlapIntervalsAroundNow(for: definition, now: referenceDate).first(where: { $0.contains(referenceDate) || $0.start > referenceDate })
            ?? nextOverlapInterval(for: definition, after: referenceDate)
        return "\(localTime(interval.start, displayTimeZone: displayTimeZone)) - \(localTime(interval.end, displayTimeZone: displayTimeZone))"
    }

    static func timelineSegments(for definition: ForexSessionDefinition, dayContaining date: Date, displayTimeZone: TimeZone = .current) -> [TimelineSegment] {
        let localDayInterval = localDayInterval(containing: date, timeZone: displayTimeZone)
        let localDayStart = localDayInterval.start
        let localDayDuration = localDayInterval.duration

        return intervalsAroundNow(for: definition, now: date).compactMap { interval in
            guard let intersection = interval.intersection(with: localDayInterval) else {
                return nil
            }

            let startFraction = intersection.start.timeIntervalSince(localDayStart) / localDayDuration
            let lengthFraction = intersection.duration / localDayDuration
            return TimelineSegment(start: startFraction, length: lengthFraction)
        }
    }

    static func timelineSegments(for definition: MarketBoardDefinition, dayContaining date: Date, displayTimeZone: TimeZone = .current) -> [TimelineSegment] {
        let localDayInterval = localDayInterval(containing: date, timeZone: displayTimeZone)
        let localDayStart = localDayInterval.start
        let localDayDuration = localDayInterval.duration

        return marketIntervalsAroundNow(for: definition, now: date).compactMap { interval in
            guard let intersection = interval.intersection(with: localDayInterval) else {
                return nil
            }

            let startFraction = intersection.start.timeIntervalSince(localDayStart) / localDayDuration
            let lengthFraction = intersection.duration / localDayDuration
            return TimelineSegment(start: startFraction, length: lengthFraction)
        }
    }

    static func relativeCountdown(to date: Date, from now: Date) -> String {
        let seconds = max(Int(date.timeIntervalSince(now)), 0)
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours == 0 {
            return "\(minutes)m"
        }
        return "\(hours)h \(minutes)m"
    }

    static func timeString(in timeZone: TimeZone, for date: Date) -> String {
        string(from: date, formatterKey: "time|\(timeZone.identifier)") {
            let formatter = DateFormatter()
            formatter.timeZone = timeZone
            formatter.dateFormat = "h:mm a"
            formatter.amSymbol = "am"
            formatter.pmSymbol = "pm"
            return formatter
        }
    }

    static func dateString(in timeZone: TimeZone, for date: Date) -> String {
        string(from: date, formatterKey: "date|\(timeZone.identifier)") {
            let formatter = DateFormatter()
            formatter.timeZone = timeZone
            formatter.dateFormat = "EEE MMM d"
            return formatter
        }
    }

    static func zoneLabel(for timeZone: TimeZone) -> String {
        timeZone.localizedName(for: .shortStandard, locale: .current) ?? timeZone.identifier
    }

    static func dayFraction(for date: Date, displayTimeZone: TimeZone = .current) -> Double {
        let dayInterval = localDayInterval(containing: date, timeZone: displayTimeZone)
        let elapsed = date.timeIntervalSince(dayInterval.start)
        return min(max(elapsed / dayInterval.duration, 0), 1)
    }

    static func date(for dayFraction: Double, onSameDayAs referenceDate: Date, displayTimeZone: TimeZone = .current) -> Date {
        let dayInterval = localDayInterval(containing: referenceDate, timeZone: displayTimeZone)
        let clampedFraction = min(max(dayFraction, 0), 1)
        return dayInterval.start.addingTimeInterval(dayInterval.duration * clampedFraction)
    }

    static func markerTimeString(for date: Date, displayTimeZone: TimeZone = .current) -> String {
        EventDateFormatter.timeString(from: date, timeZone: displayTimeZone, use24HourTime: false)
    }

    static func marketBoundaryFractions(onSameDayAs referenceDate: Date, displayTimeZone: TimeZone = .current) -> [Double] {
        let localDayInterval = localDayInterval(containing: referenceDate, timeZone: displayTimeZone)
        let localDayStart = localDayInterval.start
        let localDayDuration = localDayInterval.duration
        var fractions: [Double] = []

        for definition in MarketBoardDefinition.allCases {
            let intervals = marketIntervalsAroundNow(for: definition, now: referenceDate)
            for interval in intervals {
                let boundaries = [interval.start, interval.end]
                for boundary in boundaries where localDayInterval.contains(boundary) {
                    fractions.append(boundary.timeIntervalSince(localDayStart) / localDayDuration)
                }
            }
        }

        return fractions
    }

    static func hourLabel(for hour: Int) -> String {
        let normalizedHour = hour % 24
        switch normalizedHour {
        case 0:
            return "12"
        case 1...12:
            return "\(normalizedHour)"
        default:
            return "\(normalizedHour - 12)"
        }
    }

    static func currentLocalHour(on date: Date, displayTimeZone: TimeZone = .current) -> Int {
        localCalendar(timeZone: displayTimeZone).component(.hour, from: date)
    }

    private static func localDayInterval(containing date: Date, timeZone: TimeZone) -> DateInterval {
        let calendar = localCalendar(timeZone: timeZone)
        return calendar.dateInterval(of: .day, for: date)
            ?? DateInterval(start: calendar.startOfDay(for: date), duration: 24 * 60 * 60)
    }

    private static func localCalendar(timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    private static func localTime(_ date: Date, displayTimeZone: TimeZone) -> String {
        EventDateFormatter.timeString(from: date, timeZone: displayTimeZone, use24HourTime: false)
    }

    private static let formatterLock = NSLock()
    private static var formatters: [String: DateFormatter] = [:]

    private static func string(from date: Date, formatterKey: String, makeFormatter: () -> DateFormatter) -> String {
        formatterLock.lock()
        defer { formatterLock.unlock() }

        if let formatter = formatters[formatterKey] {
            return formatter.string(from: date)
        }

        let formatter = makeFormatter()
        formatters[formatterKey] = formatter
        return formatter.string(from: date)
    }

    private static func nextRelevantInterval(for definition: ForexSessionDefinition, referenceDate: Date) -> DateInterval {
        intervalsAroundNow(for: definition, now: referenceDate)
            .first(where: { $0.contains(referenceDate) || $0.start > referenceDate })
            ?? nextInterval(for: definition, after: referenceDate)
    }

    private static func marketInterval(for definition: MarketBoardDefinition, around date: Date, dayOffset: Int) -> DateInterval? {
        guard
            let start = zonedDate(
                in: definition.timeZone,
                relativeTo: date,
                dayOffset: dayOffset,
                hour: definition.openHour,
                minute: 0
            ),
            let end = zonedDate(
                in: definition.timeZone,
                relativeTo: date,
                dayOffset: dayOffset,
                hour: definition.closeHour,
                minute: 0
            )
        else {
            return nil
        }

        let interval = DateInterval(start: start, end: max(end, start.addingTimeInterval(60)))
        return clipToForexWeek(interval)
    }

    private static func sessionInterval(for definition: ForexSessionDefinition, around date: Date, dayOffset: Int) -> DateInterval? {
        guard
            let start = zonedDate(
                in: definition.startTimeZone,
                relativeTo: date,
                dayOffset: dayOffset,
                hour: definition.startHour,
                minute: definition.startMinute
            ),
            var end = zonedDate(
                in: definition.endTimeZone,
                relativeTo: date,
                dayOffset: dayOffset,
                hour: definition.endHour,
                minute: definition.endMinute
            )
        else {
            return nil
        }

        if end <= start {
            end = Calendar(identifier: .gregorian).date(byAdding: .day, value: 1, to: end) ?? end
        }

        let interval = DateInterval(start: start, end: end)
        return clipToForexWeek(interval)
    }

    private static func zonedDate(in timeZone: TimeZone, relativeTo date: Date, dayOffset: Int, hour: Int, minute: Int) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let startOfDay = calendar.startOfDay(for: date)
        guard let shiftedDay = calendar.date(byAdding: .day, value: dayOffset, to: startOfDay) else {
            return nil
        }

        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: shiftedDay)
    }

    private static func clipToForexWeek(_ interval: DateInterval) -> DateInterval? {
        let openIntervals = forexOpenIntervals(around: interval.start)
        for openInterval in openIntervals {
            if let intersection = interval.intersection(with: openInterval), intersection.duration > 0 {
                return intersection
            }
        }

        return nil
    }

    private static func forexOpenIntervals(around date: Date) -> [DateInterval] {
        (-1...2).compactMap { weekOffset in
            let weekStart = startOfWeekInNewYork(for: date, weekOffset: weekOffset)
            guard
                let sundayOpen = newYorkCalendar.date(bySettingHour: 17, minute: 0, second: 0, of: weekStart),
                let fridayClose = newYorkCalendar.date(byAdding: .day, value: 5, to: sundayOpen)
            else {
                return nil
            }

            return DateInterval(start: sundayOpen, end: fridayClose)
        }
    }

    private static func startOfWeekInNewYork(for date: Date, weekOffset: Int) -> Date {
        let dayStart = newYorkCalendar.startOfDay(for: date)
        let weekday = newYorkCalendar.component(.weekday, from: dayStart)
        let daysToSunday = weekday - 1
        let currentSunday = newYorkCalendar.date(byAdding: .day, value: -daysToSunday, to: dayStart) ?? dayStart
        return newYorkCalendar.date(byAdding: .day, value: weekOffset * 7, to: currentSunday) ?? currentSunday
    }
}
