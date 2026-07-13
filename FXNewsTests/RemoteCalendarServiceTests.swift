import Foundation
import Testing
@testable import FXNews

@Suite(.serialized)
@MainActor
struct RemoteCalendarServiceTests {
    @Test
    func lineDelimitedWeeklyArraysDecodeIntoSingleCalendarResponse() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = try #require(
            """
            [{"title":"Bank Holiday","country":"NZD","date":"2026-04-26T16:00:00-04:00","impact":"Holiday","forecast":"","previous":""}]
            [{"title":"Federal Funds Rate","country":"USD","date":"2026-05-06T14:00:00-04:00","impact":"High","forecast":"3.75%","previous":"3.75%"}]
            """.data(using: .utf8)
        )

        let response = try CalendarResponse.decode(from: data, using: decoder)

        #expect(response.weekOf == "2026-04-20")
        #expect(response.events.count == 2)
        #expect(response.events.map(\.currencyCode) == ["NZD", "USD"])
        #expect(response.events.map(\.timestamp) == response.events.map(\.timestamp).sorted())
    }

    @Test
    func fetchRequestsViewedWeekFromCloudflareBaseURL() async throws {
        let session = makeSession()
        let formatter = ISO8601DateFormatter()
        let weekStart = try #require(formatter.date(from: "2026-04-13T00:00:00Z"))
        let weekEnd = try #require(formatter.date(from: "2026-04-20T00:00:00Z"))

        MockURLProtocol.reset()
        MockURLProtocol.responseData = responseData(
            weekOf: "2026-04-13",
            lastUpdated: "2026-04-13T06:00:00Z",
            eventID: "remote-event",
            title: "Remote Event",
            timestamp: "2026-04-14T12:30:00Z"
        )

        let service = RemoteCalendarService(
            session: session,
            calendarBaseURL: URL(string: "https://api.example.com/calendar/")!
        )

        let result = try await service.fetchEvents(from: weekStart, to: weekEnd)

        #expect(MockURLProtocol.requestCount == 1)
        #expect(MockURLProtocol.lastRequestURL?.absoluteString == "https://api.example.com/calendar/2026-04-13.json")
        #expect(result.source == .remote)
        #expect(result.isFallback == false)
        #expect(result.events.map(\.id) == ["remote-event"])
    }

    @Test
    func appOpenRefreshAlwaysRequestsCloudflare() async throws {
        let session = makeSession()
        let formatter = ISO8601DateFormatter()
        let weekStart = try #require(formatter.date(from: "2026-04-13T00:00:00Z"))
        let weekEnd = try #require(formatter.date(from: "2026-04-20T00:00:00Z"))

        MockURLProtocol.reset()
        MockURLProtocol.responseData = responseData(
            weekOf: "2026-04-13",
            lastUpdated: "2026-04-13T06:00:00Z",
            eventID: "first-event",
            title: "First Event",
            timestamp: "2026-04-14T12:30:00Z"
        )

        let service = RemoteCalendarService(
            session: session,
            calendarBaseURL: URL(string: "https://api.example.com/calendar/")!
        )

        _ = try await service.refreshEventsIfNeededOnAppOpen(from: weekStart, to: weekEnd)

        MockURLProtocol.responseData = responseData(
            weekOf: "2026-04-13",
            lastUpdated: "2026-04-13T07:00:00Z",
            eventID: "second-event",
            title: "Second Event",
            timestamp: "2026-04-15T12:30:00Z"
        )

        let secondResult = try await service.refreshEventsIfNeededOnAppOpen(from: weekStart, to: weekEnd)

        #expect(MockURLProtocol.requestCount == 2)
        #expect(secondResult.events.map(\.id) == ["second-event"])
    }

    @Test
    func refreshReportsCloudflareLastUpdatedTime() async throws {
        let session = makeSession()
        let formatter = ISO8601DateFormatter()
        let weekStart = try #require(formatter.date(from: "2026-04-13T00:00:00Z"))
        let weekEnd = try #require(formatter.date(from: "2026-04-20T00:00:00Z"))
        let lastUpdated = try #require(formatter.date(from: "2026-04-13T06:00:00Z"))

        MockURLProtocol.reset()
        MockURLProtocol.responseData = responseData(
            weekOf: "2026-04-13",
            lastUpdated: "2026-04-13T06:00:00Z",
            eventID: "remote-event",
            title: "Remote Event",
            timestamp: "2026-04-14T12:30:00Z"
        )

        let service = RemoteCalendarService(
            session: session,
            calendarBaseURL: URL(string: "https://api.example.com/calendar/")!
        )

        let result = try await service.refreshEvents(from: weekStart, to: weekEnd)

        #expect(result.source == .remote)
        #expect(result.lastUpdated == lastUpdated)
    }

    @Test
    func fetchUsesFreshCacheForRepeatedWeekRequests() async throws {
        let session = makeSession()
        let formatter = ISO8601DateFormatter()
        let weekStart = try #require(formatter.date(from: "2026-04-13T00:00:00Z"))
        let weekEnd = try #require(formatter.date(from: "2026-04-20T00:00:00Z"))

        MockURLProtocol.reset()
        MockURLProtocol.responseData = responseData(
            weekOf: "2026-04-13",
            lastUpdated: "2026-04-13T06:00:00Z",
            eventID: "cached-event",
            title: "Cached Event",
            timestamp: "2026-04-14T12:30:00Z"
        )

        let service = RemoteCalendarService(
            session: session,
            calendarBaseURL: URL(string: "https://api.example.com/calendar/")!
        )

        let firstResult = try await service.fetchEvents(from: weekStart, to: weekEnd)

        MockURLProtocol.responseData = responseData(
            weekOf: "2026-04-13",
            lastUpdated: "2026-04-13T07:00:00Z",
            eventID: "network-event",
            title: "Network Event",
            timestamp: "2026-04-15T12:30:00Z"
        )

        let secondResult = try await service.fetchEvents(from: weekStart, to: weekEnd)

        #expect(MockURLProtocol.requestCount == 1)
        #expect(firstResult.source == .remote)
        #expect(secondResult.source == .cache)
        #expect(secondResult.isFallback == false)
        #expect(secondResult.events.map(\.id) == ["cached-event"])
    }

    @Test
    func remoteFailureFallsBackToCachedResponse() async throws {
        let session = makeSession()
        let formatter = ISO8601DateFormatter()
        let weekStart = try #require(formatter.date(from: "2026-04-13T00:00:00Z"))
        let weekEnd = try #require(formatter.date(from: "2026-04-20T00:00:00Z"))

        MockURLProtocol.reset()
        MockURLProtocol.responseData = responseData(
            weekOf: "2026-04-13",
            lastUpdated: "2026-04-13T06:00:00Z",
            eventID: "stable-cache",
            title: "Stable Cache",
            timestamp: "2026-04-14T12:30:00Z"
        )

        let service = RemoteCalendarService(
            session: session,
            calendarBaseURL: URL(string: "https://api.example.com/calendar/")!
        )

        _ = try await service.refreshEvents(from: weekStart, to: weekEnd)

        MockURLProtocol.statusCode = 503
        MockURLProtocol.responseData = Data()

        let fallbackResult = try await service.refreshEvents(from: weekStart, to: weekEnd)

        #expect(MockURLProtocol.requestCount == 2)
        #expect(fallbackResult.source == .cache)
        #expect(fallbackResult.isFallback)
        #expect(fallbackResult.events.map(\.id) == ["stable-cache"])
    }

    @Test
    func fetchFiltersOutEventsAtEndBoundary() async throws {
        let session = makeSession()
        let formatter = ISO8601DateFormatter()
        let weekStart = try #require(formatter.date(from: "2026-04-13T00:00:00Z"))
        let weekEnd = try #require(formatter.date(from: "2026-04-20T00:00:00Z"))

        MockURLProtocol.reset()
        MockURLProtocol.responseData = responseData(
            weekOf: "2026-04-13",
            lastUpdated: "2026-04-13T06:00:00Z",
            events: [
                ("inside", "Inside Event", "2026-04-19T23:59:59Z"),
                ("boundary", "Boundary Event", "2026-04-20T00:00:00Z")
            ]
        )

        let service = RemoteCalendarService(
            session: session,
            calendarBaseURL: URL(string: "https://api.example.com/calendar/")!
        )

        let result = try await service.fetchEvents(from: weekStart, to: weekEnd)

        #expect(result.events.map(\.id) == ["inside"])
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func responseData(
        weekOf: String,
        lastUpdated: String,
        eventID: String,
        title: String,
        timestamp: String
    ) -> Data {
        responseData(
            weekOf: weekOf,
            lastUpdated: lastUpdated,
            events: [(eventID, title, timestamp)]
        )
    }

    private func responseData(
        weekOf: String,
        lastUpdated: String,
        events: [(id: String, title: String, timestamp: String)]
    ) -> Data {
        let eventJSON = events.map { event in
            """
            {
              "id": "\(event.id)",
              "title": "\(event.title)",
              "country": "US",
              "currency": "USD",
              "timestamp": "\(event.timestamp)",
              "impact": "high",
              "forecast": "2.1%",
              "previous": "1.8%",
              "actual": null,
              "category": "inflation",
              "relatedPairs": ["EURUSD"]
            }
            """
        }
        .joined(separator: ",\n")

        return """
        {
          "weekOf": "\(weekOf)",
          "lastUpdated": "\(lastUpdated)",
          "events": [
            \(eventJSON)
          ]
        }
        """.data(using: .utf8) ?? Data()
    }
}

private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    static var responseData = Data()
    static var statusCode = 200
    static var requestCount = 0
    static var lastRequestURL: URL?

    static func reset() {
        responseData = Data()
        statusCode = 200
        requestCount = 0
        lastRequestURL = nil
        try? RemoteCalendarService.clearCache()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.requestCount += 1
        Self.lastRequestURL = request.url
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://example.com")!,
            statusCode: Self.statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseData)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
