import Foundation
import Testing
@testable import FXNews

struct EventDateFormatterTests {
    @Test
    func timeStringUsesSuppliedTimeZone() throws {
        let date = try #require(ISO8601DateFormatter().date(from: "2026-04-14T12:30:00Z"))
        let newYork = try #require(TimeZone(identifier: "America/New_York"))
        let tokyo = try #require(TimeZone(identifier: "Asia/Tokyo"))

        #expect(EventDateFormatter.timeString(from: date, timeZone: newYork, use24HourTime: true) == "08:30")
        #expect(EventDateFormatter.timeString(from: date, timeZone: tokyo, use24HourTime: true) == "21:30")
        #expect(EventDateFormatter.timeString(from: date, timeZone: newYork, use24HourTime: false) == "8:30 AM")
    }

    @Test
    func dateTimeStringUsesSuppliedTimeZoneAndClockFormat() throws {
        let date = try #require(ISO8601DateFormatter().date(from: "2026-04-14T12:30:00Z"))
        let newYork = try #require(TimeZone(identifier: "America/New_York"))

        #expect(EventDateFormatter.dateTimeString(from: date, timeZone: newYork, use24HourTime: true) == "Apr 14, 08:30 EDT")
        #expect(EventDateFormatter.dateTimeString(from: date, timeZone: newYork, use24HourTime: false) == "Apr 14, 8:30 AM EDT")
    }

    @Test
    func dayStringUsesSuppliedTimeZoneAcrossDateBoundary() throws {
        let date = try #require(ISO8601DateFormatter().date(from: "2026-04-14T23:30:00Z"))
        let newYork = try #require(TimeZone(identifier: "America/New_York"))
        let tokyo = try #require(TimeZone(identifier: "Asia/Tokyo"))

        #expect(EventDateFormatter.dayString(from: date, timeZone: newYork) == "Tuesday, Apr 14")
        #expect(EventDateFormatter.dayString(from: date, timeZone: tokyo) == "Wednesday, Apr 15")
    }

    @Test
    func monthDayStringUsesSuppliedTimeZoneAcrossDateBoundary() throws {
        let date = try #require(ISO8601DateFormatter().date(from: "2026-04-14T23:30:00Z"))
        let newYork = try #require(TimeZone(identifier: "America/New_York"))
        let tokyo = try #require(TimeZone(identifier: "Asia/Tokyo"))

        #expect(EventDateFormatter.monthDayString(from: date, timeZone: newYork) == "Apr 14")
        #expect(EventDateFormatter.monthDayString(from: date, timeZone: tokyo) == "Apr 15")
    }

    @Test
    func relativeStringUsesReferenceDate() throws {
        let formatter = ISO8601DateFormatter()
        let referenceDate = try #require(formatter.date(from: "2026-04-14T12:00:00Z"))
        let futureDate = try #require(formatter.date(from: "2026-04-14T12:30:00Z"))

        #expect(EventDateFormatter.relativeString(for: futureDate, relativeTo: referenceDate).contains("30"))
    }
}
