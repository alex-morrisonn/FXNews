import Foundation
import Testing
@testable import FXNews

struct CalendarUtilitiesTests {
    @Test
    func tradingWeekIntervalRespectsRequestedTimeZoneAndWeekOffset() throws {
        let formatter = ISO8601DateFormatter()
        let referenceDate = try #require(formatter.date(from: "2026-04-15T12:00:00Z"))
        let newYork = try #require(TimeZone(identifier: "America/New_York"))
        let tokyo = try #require(TimeZone(identifier: "Asia/Tokyo"))

        let newYorkInterval = Calendar.tradingWeekInterval(referenceDate: referenceDate, timeZone: newYork)
        let tokyoInterval = Calendar.tradingWeekInterval(referenceDate: referenceDate, timeZone: tokyo)
        let nextTokyoInterval = Calendar.tradingWeekInterval(referenceDate: referenceDate, weekOffset: 1, timeZone: tokyo)

        #expect(newYorkInterval.start == formatter.date(from: "2026-04-13T04:00:00Z"))
        #expect(tokyoInterval.start == formatter.date(from: "2026-04-12T15:00:00Z"))
        #expect(nextTokyoInterval.start == formatter.date(from: "2026-04-19T15:00:00Z"))
        #expect(nextTokyoInterval.duration == 7 * 24 * 60 * 60)
    }

    @Test
    func tradingWeekdaysReturnFiveLocalWeekdays() throws {
        let formatter = ISO8601DateFormatter()
        let referenceDate = try #require(formatter.date(from: "2026-04-15T12:00:00Z"))
        let tokyo = try #require(TimeZone(identifier: "Asia/Tokyo"))

        let weekdays = Calendar.tradingWeekdays(referenceDate: referenceDate, timeZone: tokyo)

        #expect(weekdays.count == 5)
        #expect(weekdays.first == formatter.date(from: "2026-04-12T15:00:00Z"))
        #expect(weekdays.last == formatter.date(from: "2026-04-16T15:00:00Z"))
    }
}
