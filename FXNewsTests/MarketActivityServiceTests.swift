import Foundation
import Testing
@testable import FXNews

struct MarketActivityServiceTests {
    private let service = EstimatedMarketActivityService()

    @Test
    func snapshotReportsClosedMarketDuringWeekend() throws {
        let saturday = try #require(ISO8601DateFormatter().date(from: "2026-04-18T12:00:00Z"))

        let snapshot = service.snapshot(at: saturday, events: [])

        #expect(snapshot.tier == .low)
        #expect(snapshot.isMarketClosed)
        #expect(snapshot.statusText == "Market closed")
        #expect(snapshot.score >= 0)
        #expect(snapshot.score <= 1)
        #expect(snapshot.sparklineSamples.count == 32)
        #expect(snapshot.sparklineSamples.allSatisfy { 0...1 ~= $0 })
    }

    @Test
    func snapshotPromotesLondonNewYorkOverlapWithHighImpactRelease() throws {
        let formatter = ISO8601DateFormatter()
        let releaseDate = try #require(formatter.date(from: "2026-04-14T13:00:00Z"))
        let event = EconomicEvent(
            id: "high-impact-us",
            title: "High Impact US Release",
            countryCode: "US",
            currencyCode: "USD",
            timestamp: releaseDate,
            impactLevel: .high
        )

        let snapshot = service.snapshot(at: releaseDate, events: [event])

        #expect(snapshot.tier == .high)
        #expect(!snapshot.isMarketClosed)
        #expect(snapshot.statusText == "London/NY overlap")
        #expect(snapshot.score > 0.72)
    }

    @Test
    func snapshotCallsOutNearbyMarketMovingEventOutsideOverlap() throws {
        let formatter = ISO8601DateFormatter()
        let releaseDate = try #require(formatter.date(from: "2026-04-14T10:00:00Z"))
        let event = EconomicEvent(
            id: "high-impact-eu",
            title: "High Impact EU Release",
            countryCode: "EU",
            currencyCode: "EUR",
            timestamp: releaseDate,
            impactLevel: .high
        )

        let snapshot = service.snapshot(at: releaseDate, events: [event])

        #expect(!snapshot.isMarketClosed)
        #expect(snapshot.statusText == "High-impact release window")
        #expect(snapshot.tier == .medium)
    }
}
