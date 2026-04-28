import Foundation

private struct CalendarResponse: Codable {
    let weekOf: String
    let lastUpdated: Date
    let events: [EconomicEvent]

    init(weekOf: String, lastUpdated: Date, events: [EconomicEvent]) {
        self.weekOf = weekOf
        self.lastUpdated = lastUpdated
        self.events = events
    }

    init(from decoder: Decoder) throws {
        if let container = try? decoder.container(keyedBy: CodingKeys.self) {
            self.weekOf = try container.decode(String.self, forKey: .weekOf)
            self.lastUpdated = try container.decode(Date.self, forKey: .lastUpdated)
            self.events = try container.decode([EconomicEvent].self, forKey: .events)
            return
        }

        let container = try decoder.singleValueContainer()
        let events = try container.decode([EconomicEvent].self)

        self.events = events
        self.lastUpdated = events.map(\.timestamp).max() ?? Date()
        self.weekOf = Self.inferredWeekOf(from: events)
    }

    private static func inferredWeekOf(from events: [EconomicEvent]) -> String {
        guard let firstTimestamp = events.map(\.timestamp).min() else {
            return ""
        }

        let calendar = Calendar.utcGregorian
        let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: firstTimestamp)?.start ?? firstTimestamp
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: startOfWeek)
    }
}

final class RemoteCalendarService: CalendarService {
    static let calendarURL = URL(string: "https://raw.githubusercontent.com/alex-morrisonn/FXNews/main/FXNews/SampleData/calendar.json")!
    static let productionCacheLifetime: TimeInterval = 24 * 60 * 60

    private let session: URLSession
    private let fileManager: FileManager
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let now: @Sendable () -> Date
    private let cacheLifetime: TimeInterval
    private let bypassCache: Bool
    private let preferBundledSource: Bool

    init(
        session: URLSession = .shared,
        fileManager: FileManager = .default,
        now: @escaping @Sendable () -> Date = Date.init,
        cacheLifetime: TimeInterval? = nil,
        bypassCache: Bool? = nil,
        preferBundledSource: Bool? = nil
    ) {
        self.session = session
        self.fileManager = fileManager
        self.now = now
        self.cacheLifetime = cacheLifetime ?? Self.productionCacheLifetime
        self.bypassCache = bypassCache ?? Self.shouldBypassCacheFromRuntimeConfiguration
        self.preferBundledSource = preferBundledSource ?? Self.shouldPreferBundledSourceFromRuntimeConfiguration

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
    }

    func fetchEvents(from startDate: Date, to endDate: Date) async throws -> CalendarFetchResult {
        let result = try await loadResponse(forceRefresh: false)
        return filteredResult(from: result, startDate: startDate, endDate: endDate)
    }

    func refreshEvents(from startDate: Date, to endDate: Date) async throws -> CalendarFetchResult {
        let result = try await loadResponse(forceRefresh: true)
        return filteredResult(from: result, startDate: startDate, endDate: endDate)
    }

    private func filteredResult(from result: CalendarFetchResult, startDate: Date, endDate: Date) -> CalendarFetchResult {
        CalendarFetchResult(
            events: result.events
                .filter { $0.timestamp >= startDate && $0.timestamp <= endDate }
                .sorted { $0.timestamp < $1.timestamp },
            source: result.source,
            lastUpdated: result.lastUpdated,
            isFallback: result.isFallback
        )
    }

    private func loadResponse(forceRefresh: Bool) async throws -> CalendarFetchResult {
        do {
            if preferBundledSource {
                let bundledResponse = try loadBundledResponse()
                return CalendarFetchResult(
                    events: bundledResponse.events,
                    source: .bundled,
                    lastUpdated: bundledResponse.lastUpdated,
                    isFallback: false
                )
            }

            if !forceRefresh, !bypassCache, try isCacheFresh() {
                let cachedResponse = try loadCachedResponse()
                return CalendarFetchResult(
                    events: cachedResponse.events,
                    source: .cache,
                    lastUpdated: cachedResponse.lastUpdated,
                    isFallback: false
                )
            }

            let remoteResponse = try await fetchRemoteResponse()
            try cache(response: remoteResponse)
            return CalendarFetchResult(
                events: remoteResponse.events,
                source: .remote,
                lastUpdated: remoteResponse.lastUpdated,
                isFallback: false
            )
        } catch {
            if let cachedResponse = try? loadCachedResponse() {
                return CalendarFetchResult(
                    events: cachedResponse.events,
                    source: .cache,
                    lastUpdated: cachedResponse.lastUpdated,
                    isFallback: true
                )
            }

            if let bundledResponse = try? loadBundledResponse() {
                return CalendarFetchResult(
                    events: bundledResponse.events,
                    source: .bundled,
                    lastUpdated: bundledResponse.lastUpdated,
                    isFallback: true
                )
            }

            throw RemoteCalendarServiceError.noDataAvailable
        }
    }

    private func fetchRemoteResponse() async throws -> CalendarResponse {
        var request = URLRequest(url: Self.calendarURL)
        request.timeoutInterval = 30
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        try validate(response: response)

        do {
            return try decoder.decode(CalendarResponse.self, from: data)
        } catch {
            throw RemoteCalendarServiceError.invalidPayload
        }
    }

    private func validate(response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw RemoteCalendarServiceError.invalidResponse
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            throw RemoteCalendarServiceError.requestFailed(statusCode: httpResponse.statusCode)
        }
    }

    private func loadBundledResponse() throws -> CalendarResponse {
        guard let fileURL = Bundle.main.url(forResource: "calendar", withExtension: "json", subdirectory: "SampleData")
            ?? Bundle.main.url(forResource: "calendar", withExtension: "json")
        else {
            throw RemoteCalendarServiceError.missingBundledFile
        }

        let data = try Data(contentsOf: fileURL)
        do {
            return try decoder.decode(CalendarResponse.self, from: data)
        } catch {
            throw RemoteCalendarServiceError.invalidPayload
        }
    }

    private func loadCachedResponse() throws -> CalendarResponse {
        let data = try Data(contentsOf: cacheFileURL())

        do {
            return try decoder.decode(CalendarResponse.self, from: data)
        } catch {
            throw RemoteCalendarServiceError.invalidPayload
        }
    }

    private func cache(response: CalendarResponse) throws {
        let data = try encoder.encode(response)
        let cacheURL = try cacheFileURL()
        let directoryURL = cacheURL.deletingLastPathComponent()

        if !fileManager.fileExists(atPath: directoryURL.path) {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }

        try data.write(to: cacheURL, options: .atomic)
    }

    private func isCacheFresh() throws -> Bool {
        let cacheURL = try cacheFileURL()
        guard fileManager.fileExists(atPath: cacheURL.path) else {
            return false
        }

        let attributes = try fileManager.attributesOfItem(atPath: cacheURL.path)
        guard let modificationDate = attributes[.modificationDate] as? Date else {
            return false
        }

        return now().timeIntervalSince(modificationDate) < cacheLifetime
    }

    private func cacheFileURL() throws -> URL {
        guard let cachesDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            throw RemoteCalendarServiceError.cacheUnavailable
        }

        return cachesDirectory
            .appendingPathComponent("fxnews", isDirectory: true)
            .appendingPathComponent("calendar-cache.json")
    }

    static func clearCache(fileManager: FileManager = .default) throws {
        guard let cachesDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            throw RemoteCalendarServiceError.cacheUnavailable
        }

        let cacheURL = cachesDirectory
            .appendingPathComponent("fxnews", isDirectory: true)
            .appendingPathComponent("calendar-cache.json")

        if fileManager.fileExists(atPath: cacheURL.path) {
            try fileManager.removeItem(at: cacheURL)
        }
    }

    private static var shouldBypassCacheFromRuntimeConfiguration: Bool {
        #if DEBUG
        let processInfo = ProcessInfo.processInfo
        return processInfo.arguments.contains("-FXNewsDisableCalendarCache")
            || processInfo.environment["FXNEWS_DISABLE_CALENDAR_CACHE"] == "1"
        #else
        return false
        #endif
    }

    private static var shouldPreferBundledSourceFromRuntimeConfiguration: Bool {
        #if DEBUG
        let processInfo = ProcessInfo.processInfo
        if processInfo.arguments.contains("-FXNewsUseRemoteCalendar") {
            return false
        }

        if processInfo.environment["FXNEWS_USE_REMOTE_CALENDAR"] == "1" {
            return false
        }

        return true
        #else
        return false
        #endif
    }
}

enum RemoteCalendarServiceError: LocalizedError {
    case cacheUnavailable
    case missingBundledFile
    case invalidResponse
    case invalidPayload
    case requestFailed(statusCode: Int)
    case noDataAvailable

    var errorDescription: String? {
        switch self {
        case .cacheUnavailable:
            return "The local calendar cache is unavailable."
        case .missingBundledFile:
            return "The bundled calendar.json file could not be found."
        case .invalidResponse:
            return "The remote calendar returned an invalid response."
        case .invalidPayload:
            return "The calendar.json file could not be parsed."
        case let .requestFailed(statusCode):
            return "The remote calendar request failed with status \(statusCode)."
        case .noDataAvailable:
            return "No calendar data is available. Pull to refresh to try again."
        }
    }
}
