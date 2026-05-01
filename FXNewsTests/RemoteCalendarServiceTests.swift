import Foundation
import Testing
@testable import FXNews

@MainActor
struct RemoteCalendarServiceTests {
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

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
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
