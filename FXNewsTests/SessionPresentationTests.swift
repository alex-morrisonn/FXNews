import Foundation
import Testing
@testable import FXNews

struct SessionPresentationTests {
    @Test
    func forexMarketOpenStateHonorsNewYorkWeeklyBoundaries() throws {
        let formatter = ISO8601DateFormatter()
        let fridayBeforeClose = try #require(formatter.date(from: "2026-04-17T20:59:00Z"))
        let fridayAtClose = try #require(formatter.date(from: "2026-04-17T21:00:00Z"))
        let sundayBeforeOpen = try #require(formatter.date(from: "2026-04-19T20:59:00Z"))
        let sundayAtOpen = try #require(formatter.date(from: "2026-04-19T21:00:00Z"))

        #expect(SessionPresentation.isForexMarketOpen(at: fridayBeforeClose))
        #expect(!SessionPresentation.isForexMarketOpen(at: fridayAtClose))
        #expect(!SessionPresentation.isForexMarketOpen(at: sundayBeforeOpen))
        #expect(SessionPresentation.isForexMarketOpen(at: sundayAtOpen))
    }

    @Test
    func nextForexMarketOpenReturnsSundayNewYorkOpenWhenClosed() throws {
        let formatter = ISO8601DateFormatter()
        let saturday = try #require(formatter.date(from: "2026-04-18T12:00:00Z"))
        let sundayBeforeOpen = try #require(formatter.date(from: "2026-04-19T20:59:00Z"))
        let expectedOpen = try #require(formatter.date(from: "2026-04-19T21:00:00Z"))

        #expect(SessionPresentation.nextForexMarketOpen(after: saturday) == expectedOpen)
        #expect(SessionPresentation.nextForexMarketOpen(after: sundayBeforeOpen) == expectedOpen)
    }

    @Test
    func nextSessionIntervalUsesSessionLocalTimeZones() throws {
        let formatter = ISO8601DateFormatter()
        let beforeLondonOpen = try #require(formatter.date(from: "2026-04-14T06:30:00Z"))

        let interval = SessionPresentation.nextInterval(for: .london, after: beforeLondonOpen)

        #expect(interval.start == formatter.date(from: "2026-04-14T07:00:00Z"))
        #expect(interval.end == formatter.date(from: "2026-04-14T16:00:00Z"))
    }

    @Test
    func overlapIntervalFindsLondonNewYorkLiquidityWindow() throws {
        let formatter = ISO8601DateFormatter()
        let referenceDate = try #require(formatter.date(from: "2026-04-14T11:00:00Z"))

        let interval = SessionPresentation.nextOverlapInterval(for: .londonNewYork, after: referenceDate)

        #expect(interval.start == formatter.date(from: "2026-04-14T12:00:00Z"))
        #expect(interval.end == formatter.date(from: "2026-04-14T16:00:00Z"))
    }

    @Test
    func timelineSegmentsAreClampedToDisplayedLocalDay() throws {
        let formatter = ISO8601DateFormatter()
        let referenceDate = try #require(formatter.date(from: "2026-04-14T12:00:00Z"))
        let tokyo = try #require(TimeZone(identifier: "Asia/Tokyo"))

        let segments = SessionPresentation.timelineSegments(for: ForexSessionDefinition.asian, dayContaining: referenceDate, displayTimeZone: tokyo)

        #expect(!segments.isEmpty)
        #expect(segments.allSatisfy { 0...1 ~= $0.start })
        #expect(segments.allSatisfy { 0...1 ~= $0.length })
        #expect(segments.allSatisfy { $0.start + $0.length <= 1.000001 })
    }

    @Test
    func centeredTimelineSegmentsCoverRollingTwentyFourHourWindow() throws {
        let formatter = ISO8601DateFormatter()
        let referenceDate = try #require(formatter.date(from: "2026-04-14T12:00:00Z"))

        let segments = SessionPresentation.timelineSegments(for: MarketBoardDefinition.newYork, centeredAt: referenceDate)
        let expectedStart = (try #require(formatter.date(from: "2026-04-14T13:00:00Z"))).timeIntervalSince(referenceDate.addingTimeInterval(-12 * 60 * 60)) / (24 * 60 * 60)
        let expectedLength = Double(8 * 60 * 60) / Double(24 * 60 * 60)

        #expect(segments.count == 1)
        #expect(abs(segments[0].start - expectedStart) < 0.000001)
        #expect(abs(segments[0].length - expectedLength) < 0.000001)
    }
}
