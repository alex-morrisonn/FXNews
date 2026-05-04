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
    func appOpenRefreshChecksRemoteWhenLastCheckIsOlderThanOneHour() async throws {
        let fileManager = TestFileManager()
        let session = makeSession()
        let formatter = ISO8601DateFormatter()
        let weekStart = try #require(formatter.date(from: "2026-04-13T00:00:00Z"))
        let weekEnd = try #require(formatter.date(from: "2026-04-17T23:59:59Z"))

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
            fileManager: fileManager,
            now: { weekStart },
            cacheLifetime: 24 * 60 * 60,
            bypassCache: false,
            preferBundledSource: false
        )

        _ = try await service.refreshEventsIfNeededOnAppOpen(from: weekStart, to: weekEnd)
        #expect(MockURLProtocol.requestCount == 1)

        let twoHoursLater = try #require(formatter.date(from: "2026-04-13T02:01:00Z"))
        let laterService = RemoteCalendarService(
            session: session,
            fileManager: fileManager,
            now: { twoHoursLater },
            cacheLifetime: 24 * 60 * 60,
            bypassCache: false,
            preferBundledSource: false
        )

        _ = try await laterService.refreshEventsIfNeededOnAppOpen(from: weekStart, to: weekEnd)
        #expect(MockURLProtocol.requestCount == 2)
    }

    @Test
    func appOpenRefreshUsesCacheWhenLastCheckWasWithinOneHour() async throws {
        let fileManager = TestFileManager()
        let session = makeSession()
        let formatter = ISO8601DateFormatter()
        let weekStart = try #require(formatter.date(from: "2026-04-13T00:00:00Z"))
        let weekEnd = try #require(formatter.date(from: "2026-04-17T23:59:59Z"))

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
            fileManager: fileManager,
            now: { weekStart },
            cacheLifetime: 24 * 60 * 60,
            bypassCache: false,
            preferBundledSource: false
        )

        _ = try await service.refreshEventsIfNeededOnAppOpen(from: weekStart, to: weekEnd)
        #expect(MockURLProtocol.requestCount == 1)

        MockURLProtocol.responseData = responseData(
            weekOf: "2026-04-13",
            lastUpdated: "2026-04-13T07:00:00Z",
            eventID: "unexpected-second-fetch",
            title: "Unexpected Second Fetch",
            timestamp: "2026-04-15T12:30:00Z"
        )

        let thirtyMinutesLater = try #require(formatter.date(from: "2026-04-13T00:30:00Z"))
        let laterService = RemoteCalendarService(
            session: session,
            fileManager: fileManager,
            now: { thirtyMinutesLater },
            cacheLifetime: 24 * 60 * 60,
            bypassCache: false,
            preferBundledSource: false
        )

        let result = try await laterService.refreshEventsIfNeededOnAppOpen(from: weekStart, to: weekEnd)
        #expect(MockURLProtocol.requestCount == 1)
        #expect(result.source == .cache)
        #expect(result.events.map(\.id) == ["remote-event"])
    }

    @Test
    func refreshReportsActualRefreshTimeInsteadOfEventTime() async throws {
        let fileManager = TestFileManager()
        let session = makeSession()
        let formatter = ISO8601DateFormatter()
        let weekStart = try #require(formatter.date(from: "2026-04-13T00:00:00Z"))
        let weekEnd = try #require(formatter.date(from: "2026-04-17T23:59:59Z"))
        let refreshTime = try #require(formatter.date(from: "2026-04-13T09:45:00Z"))

        MockURLProtocol.reset()
        MockURLProtocol.responseData = responseData(
            weekOf: "2026-04-13",
            lastUpdated: "2026-04-20T12:00:00Z",
            eventID: "future-dated-event",
            title: "Future Dated Event",
            timestamp: "2026-04-30T12:30:00Z"
        )

        let service = RemoteCalendarService(
            session: session,
            fileManager: fileManager,
            now: { refreshTime },
            cacheLifetime: 24 * 60 * 60,
            bypassCache: false,
            preferBundledSource: false
        )

        let result = try await service.refreshEvents(from: weekStart, to: weekEnd)

        #expect(result.source == .remote)
        #expect(result.lastUpdated == refreshTime)
    }

    @Test
    func refreshBypassesFreshCacheAndClearCacheRemovesStoredResponse() async throws {
        let fileManager = TestFileManager()
        let session = makeSession()
        let formatter = ISO8601DateFormatter()
        let weekStart = try #require(formatter.date(from: "2026-04-13T00:00:00Z"))
        let weekEnd = try #require(formatter.date(from: "2026-04-17T23:59:59Z"))

        MockURLProtocol.responseData = responseData(
            weekOf: "2026-04-13",
            lastUpdated: "2026-04-13T06:00:00Z",
            eventID: "cached-event",
            title: "Cached Event",
            timestamp: "2026-04-14T12:30:00Z"
        )

        let service = RemoteCalendarService(
            session: session,
            fileManager: fileManager,
            now: { weekStart },
            cacheLifetime: 24 * 60 * 60,
            bypassCache: false,
            preferBundledSource: false
        )

        let initial = try await service.fetchEvents(from: weekStart, to: weekEnd)
        #expect(initial.source == .remote)
        #expect(initial.events.map(\.id) == ["cached-event"])

        MockURLProtocol.responseData = responseData(
            weekOf: "2026-04-13",
            lastUpdated: "2026-04-13T08:00:00Z",
            eventID: "fresh-event",
            title: "Fresh Event",
            timestamp: "2026-04-15T12:30:00Z"
        )

        let cached = try await service.fetchEvents(from: weekStart, to: weekEnd)
        #expect(cached.source == .cache)
        #expect(cached.events.map(\.id) == ["cached-event"])

        let refreshed = try await service.refreshEvents(from: weekStart, to: weekEnd)
        #expect(refreshed.source == .remote)
        #expect(refreshed.events.map(\.id) == ["fresh-event"])

        let cacheURL = fileManager.cacheRoot
            .appendingPathComponent("fxnews", isDirectory: true)
            .appendingPathComponent("calendar-cache.json")
        #expect(fileManager.fileExists(atPath: cacheURL.path))

        try RemoteCalendarService.clearCache(fileManager: fileManager)

        #expect(!fileManager.fileExists(atPath: cacheURL.path))
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
        """
        {
          "weekOf": "\(weekOf)",
          "lastUpdated": "\(lastUpdated)",
          "events": [
            {
              "id": "\(eventID)",
              "title": "\(title)",
              "country": "US",
              "currency": "USD",
              "timestamp": "\(timestamp)",
              "impact": "high",
              "forecast": "2.1%",
              "previous": "1.8%",
              "actual": null,
              "category": "inflation",
              "relatedPairs": ["EURUSD"]
            }
          ]
        }
        """.data(using: .utf8) ?? Data()
    }
}

private final class TestFileManager: FileManager, @unchecked Sendable {
    let cacheRoot: URL

    override init() {
        self.cacheRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        super.init()
    }

    override func urls(for directory: SearchPathDirectory, in domainMask: SearchPathDomainMask) -> [URL] {
        guard directory == .cachesDirectory, domainMask == .userDomainMask else {
            return super.urls(for: directory, in: domainMask)
        }

        return [cacheRoot]
    }
}

private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    static var responseData = Data()
    static var requestCount = 0

    static func reset() {
        responseData = Data()
        requestCount = 0
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.requestCount += 1
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseData)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
