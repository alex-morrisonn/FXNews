import Foundation
import Testing
@testable import FXNews

@MainActor
struct CalendarViewModelTests {
    @Test
    func loadWeekUsesRequestedTimeZoneForVisibleInterval() async throws {
        let formatter = ISO8601DateFormatter()
        let event = EconomicEvent(
            id: "tokyo-monday",
            title: "Tokyo Monday Event",
            countryCode: "JP",
            currencyCode: "JPY",
            timestamp: try #require(formatter.date(from: "2026-04-19T16:00:00Z")),
            impactLevel: .high
        )
        let viewModel = CalendarViewModel(service: StubCalendarService(events: [event]))
        let tokyo = try #require(TimeZone(identifier: "Asia/Tokyo"))
        let referenceDate = try #require(formatter.date(from: "2026-04-19T16:00:00Z"))

        await viewModel.loadWeek(referenceDate: referenceDate, timeZone: tokyo)

        #expect(viewModel.events.map(\.id) == ["tokyo-monday"])
        #expect(viewModel.visibleInterval == Calendar.tradingWeekInterval(referenceDate: referenceDate, timeZone: tokyo))
        #expect(viewModel.lastRefreshDate != nil)
        #expect(viewModel.dataSource == .remote)
        #expect(!viewModel.isShowingFallbackData)
        #expect(viewModel.errorMessage == nil)
        #expect(!viewModel.isLoading)
    }

    @Test
    func pairHelpersFilterAndSortUpcomingEvents() async throws {
        let formatter = ISO8601DateFormatter()
        let first = EconomicEvent(
            id: "first",
            title: "First",
            countryCode: "US",
            currencyCode: "USD",
            timestamp: try #require(formatter.date(from: "2026-04-14T12:30:00Z")),
            impactLevel: .high,
            relatedPairs: ["EURUSD"]
        )
        let second = EconomicEvent(
            id: "second",
            title: "Second",
            countryCode: "US",
            currencyCode: "USD",
            timestamp: try #require(formatter.date(from: "2026-04-15T12:30:00Z")),
            impactLevel: .medium,
            relatedPairs: ["EURUSD", "GBPUSD"]
        )
        let viewModel = CalendarViewModel(service: StubCalendarService(events: [second, first]))
        let referenceDate = try #require(formatter.date(from: "2026-04-13T12:00:00Z"))

        await viewModel.loadWeek(referenceDate: referenceDate)

        #expect(viewModel.availablePairSymbols == ["EURUSD", "GBPUSD"])
        #expect(viewModel.events(forPair: "EURUSD").map(\.id) == ["first", "second"])
        #expect(viewModel.nextEvent(forPair: "EURUSD", now: referenceDate)?.id == "first")
        #expect(viewModel.nextEvent(forPair: "EURUSD", now: second.timestamp.addingTimeInterval(1)) == nil)
    }

    @Test
    func pairHelpersIncludeBothCurrenciesWhenFeedPairTagsAreIncomplete() async throws {
        let formatter = ISO8601DateFormatter()
        let audEvent = EconomicEvent(
            id: "aud-event",
            title: "RBA Minutes",
            countryCode: "AU",
            currencyCode: "AUD",
            timestamp: try #require(formatter.date(from: "2026-04-14T01:30:00Z")),
            impactLevel: .medium,
            relatedPairs: ["AUDUSD", "AUDJPY"]
        )
        let usdEvent = EconomicEvent(
            id: "usd-event",
            title: "US Retail Sales",
            countryCode: "US",
            currencyCode: "USD",
            timestamp: try #require(formatter.date(from: "2026-04-14T12:30:00Z")),
            impactLevel: .high,
            relatedPairs: ["EURUSD", "GBPUSD", "USDJPY"]
        )
        let unrelatedEvent = EconomicEvent(
            id: "jpy-event",
            title: "Japan CPI",
            countryCode: "JP",
            currencyCode: "JPY",
            timestamp: try #require(formatter.date(from: "2026-04-15T00:30:00Z")),
            impactLevel: .medium,
            relatedPairs: ["USDJPY"]
        )
        let viewModel = CalendarViewModel(service: StubCalendarService(events: [usdEvent, unrelatedEvent, audEvent]))
        let referenceDate = try #require(formatter.date(from: "2026-04-13T12:00:00Z"))

        await viewModel.loadWeek(referenceDate: referenceDate)

        #expect(viewModel.events(forPair: "AUDUSD").map(\.id) == ["aud-event", "usd-event"])
        #expect(viewModel.events(forPair: "AUD/USD").map(\.id) == ["aud-event", "usd-event"])
        #expect(viewModel.nextEvent(forPair: "AUDUSD", now: referenceDate)?.id == "aud-event")
    }

    @Test
    func loadFailureClearsEventsAndPublishesErrorState() async throws {
        let viewModel = CalendarViewModel(service: FailingCalendarService())
        let referenceDate = try #require(ISO8601DateFormatter().date(from: "2026-04-13T12:00:00Z"))

        await viewModel.loadWeek(referenceDate: referenceDate)

        #expect(viewModel.events.isEmpty)
        #expect(viewModel.errorMessage == CalendarServiceStubError.unavailable.localizedDescription)
        #expect(viewModel.visibleInterval == Calendar.tradingWeekInterval(referenceDate: referenceDate))
        #expect(viewModel.lastRefreshDate == nil)
        #expect(viewModel.dataSource == nil)
        #expect(!viewModel.isShowingFallbackData)
        #expect(!viewModel.isLoading)
    }

    @Test
    func availableCurrenciesAreUniqueAndSorted() async throws {
        let formatter = ISO8601DateFormatter()
        let events = [
            EconomicEvent(
                id: "usd-2",
                title: "Second USD",
                countryCode: "US",
                currencyCode: "USD",
                timestamp: try #require(formatter.date(from: "2026-04-14T12:30:00Z")),
                impactLevel: .medium
            ),
            EconomicEvent(
                id: "eur",
                title: "EUR",
                countryCode: "EU",
                currencyCode: "EUR",
                timestamp: try #require(formatter.date(from: "2026-04-14T09:00:00Z")),
                impactLevel: .high
            ),
            EconomicEvent(
                id: "usd-1",
                title: "First USD",
                countryCode: "US",
                currencyCode: "USD",
                timestamp: try #require(formatter.date(from: "2026-04-14T08:30:00Z")),
                impactLevel: .low
            )
        ]
        let viewModel = CalendarViewModel(service: StubCalendarService(events: events))

        await viewModel.loadWeek(referenceDate: try #require(formatter.date(from: "2026-04-13T12:00:00Z")))

        #expect(viewModel.events.map(\.id) == ["usd-1", "eur", "usd-2"])
        #expect(viewModel.availableCurrencies == ["EUR", "USD"])
    }

    @Test
    func loadWeekPublishesFallbackSourceMetadata() async throws {
        let formatter = ISO8601DateFormatter()
        let lastUpdated = try #require(formatter.date(from: "2026-04-16T20:00:00Z"))
        let event = EconomicEvent(
            id: "fallback-event",
            title: "Fallback Event",
            countryCode: "US",
            currencyCode: "USD",
            timestamp: try #require(formatter.date(from: "2026-04-14T12:30:00Z")),
            impactLevel: .high
        )
        let viewModel = CalendarViewModel(
            service: StubCalendarService(
                result: CalendarFetchResult(
                    events: [event],
                    source: .cache,
                    lastUpdated: lastUpdated,
                    isFallback: true
                )
            )
        )

        await viewModel.loadWeek(referenceDate: try #require(formatter.date(from: "2026-04-13T12:00:00Z")))

        #expect(viewModel.events.map(\.id) == ["fallback-event"])
        #expect(viewModel.dataSource == .cache)
        #expect(viewModel.isShowingFallbackData)
        #expect(viewModel.lastRefreshDate == lastUpdated)
    }
}

private struct StubCalendarService: CalendarService {
    let result: CalendarFetchResult

    init(events: [EconomicEvent]) {
        self.result = CalendarFetchResult(
            events: events,
            source: .remote,
            lastUpdated: Date(timeIntervalSince1970: 0),
            isFallback: false
        )
    }

    init(result: CalendarFetchResult) {
        self.result = result
    }

    func fetchEvents(from startDate: Date, to endDate: Date) async throws -> CalendarFetchResult {
        let filteredEvents = result.events
            .filter { $0.timestamp >= startDate && $0.timestamp <= endDate }
            .sorted { $0.timestamp < $1.timestamp }

        return CalendarFetchResult(
            events: filteredEvents,
            source: result.source,
            lastUpdated: result.lastUpdated,
            isFallback: result.isFallback
        )
    }
}

private struct FailingCalendarService: CalendarService {
    func fetchEvents(from startDate: Date, to endDate: Date) async throws -> CalendarFetchResult {
        throw CalendarServiceStubError.unavailable
    }
}

private enum CalendarServiceStubError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        "Calendar data is unavailable."
    }
}
