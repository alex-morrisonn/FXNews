import Foundation

struct CalendarResponse: Codable {
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

    static func decode(from data: Data, using decoder: JSONDecoder) throws -> CalendarResponse {
        do {
            return try decoder.decode(CalendarResponse.self, from: data)
        } catch {
            let lineResponses = try String(decoding: data, as: UTF8.self)
                .split(whereSeparator: \.isNewline)
                .map(String.init)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .map { line in
                    guard let lineData = line.data(using: .utf8) else {
                        throw RemoteCalendarServiceError.invalidPayload
                    }

                    return try decoder.decode(CalendarResponse.self, from: lineData)
                }

            guard !lineResponses.isEmpty else {
                throw error
            }

            return merged(lineResponses)
        }
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

    private static func merged(_ responses: [CalendarResponse]) -> CalendarResponse {
        let events = responses
            .flatMap(\.events)
            .sorted { $0.timestamp < $1.timestamp }

        let lastUpdated = responses.map(\.lastUpdated).max()
            ?? events.map(\.timestamp).max()
            ?? Date()

        return CalendarResponse(
            weekOf: responses.map(\.weekOf).filter { !$0.isEmpty }.min() ?? inferredWeekOf(from: events),
            lastUpdated: lastUpdated,
            events: events
        )
    }
}

final class RemoteCalendarService: CalendarService {
    static let calendarBaseURL = URL(string: "https://fxnews-calendar-worker.fxnews-alexmorrison.workers.dev/calendar/")!
    private static let cacheDirectoryName = "RemoteCalendarCache"
    private static let weekFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = .utcGregorian
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let fileManager: FileManager
    private let calendarBaseURL: URL
    private let cacheLifetime: TimeInterval
    private let bypassCache: Bool

    init(
        session: URLSession = .shared,
        fileManager: FileManager = .default,
        calendarBaseURL: URL = RemoteCalendarService.calendarBaseURL,
        cacheLifetime: TimeInterval? = nil,
        bypassCache: Bool? = nil
    ) {
        self.session = session
        self.fileManager = fileManager
        self.calendarBaseURL = calendarBaseURL
        self.cacheLifetime = cacheLifetime ?? 60 * 20
        self.bypassCache = bypassCache ?? false

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
    }

    func fetchEvents(from startDate: Date, to endDate: Date) async throws -> CalendarFetchResult {
        let result = try await loadResponse(for: startDate, policy: .useFreshCache)
        return filteredResult(from: result, startDate: startDate, endDate: endDate)
    }

    func refreshEvents(from startDate: Date, to endDate: Date) async throws -> CalendarFetchResult {
        let result = try await loadResponse(for: startDate, policy: .forceRemote)
        return filteredResult(from: result, startDate: startDate, endDate: endDate)
    }

    func refreshEventsIfNeededOnAppOpen(from startDate: Date, to endDate: Date) async throws -> CalendarFetchResult {
        let result = try await loadResponse(for: startDate, policy: .forceRemote)
        return filteredResult(from: result, startDate: startDate, endDate: endDate)
    }

    private func filteredResult(from result: CalendarFetchResult, startDate: Date, endDate: Date) -> CalendarFetchResult {
        CalendarFetchResult(
            events: result.events
                .filter { $0.timestamp >= startDate && $0.timestamp < endDate }
                .sorted { $0.timestamp < $1.timestamp },
            source: result.source,
            lastUpdated: result.lastUpdated,
            isFallback: result.isFallback
        )
    }

    private func loadResponse(for startDate: Date, policy: CachePolicy) async throws -> CalendarFetchResult {
        let weekIdentifier = Self.weekIdentifier(for: startDate)

        if policy == .useFreshCache, !bypassCache, isCacheFresh(forWeek: weekIdentifier), let cachedResponse = try? loadCachedResponse(forWeek: weekIdentifier) {
            return CalendarFetchResult(
                events: cachedResponse.events,
                source: .cache,
                lastUpdated: cachedResponse.lastUpdated,
                isFallback: false
            )
        }

        do {
            let remoteResponse = try await fetchRemoteResponse(forWeek: weekIdentifier)
            try? saveCachedResponse(remoteResponse, forWeek: weekIdentifier)

            return CalendarFetchResult(
                events: remoteResponse.events,
                source: .remote,
                lastUpdated: remoteResponse.lastUpdated,
                isFallback: false
            )
        } catch {
            if let cachedResponse = try? loadCachedResponse(forWeek: weekIdentifier) {
                return CalendarFetchResult(
                    events: cachedResponse.events,
                    source: .cache,
                    lastUpdated: cachedResponse.lastUpdated,
                    isFallback: true
                )
            }

            throw error
        }
    }

    private func fetchRemoteResponse(forWeek weekIdentifier: String) async throws -> CalendarResponse {
        var request = URLRequest(url: remoteCalendarURL(forWeek: weekIdentifier))
        request.timeoutInterval = 30
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        try validate(response: response)

        do {
            return try CalendarResponse.decode(from: data, using: decoder)
        } catch {
            throw RemoteCalendarServiceError.invalidPayload
        }
    }

    private func remoteCalendarURL(forWeek weekIdentifier: String) -> URL {
        calendarBaseURL
            .appendingPathComponent(weekIdentifier)
            .appendingPathExtension("json")
    }

    private func validate(response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw RemoteCalendarServiceError.invalidResponse
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            throw RemoteCalendarServiceError.requestFailed(statusCode: httpResponse.statusCode)
        }
    }

    private static func weekIdentifier(for date: Date) -> String {
        let dateSafelyInsideTradingWeek = date.addingTimeInterval(24 * 60 * 60)
        let startOfWeek = Calendar.utcGregorian.dateInterval(of: .weekOfYear, for: dateSafelyInsideTradingWeek)?.start ?? dateSafelyInsideTradingWeek
        return weekFormatter.string(from: startOfWeek)
    }

    static func clearCache(fileManager: FileManager = .default) throws {
        let cacheDirectory = try cacheDirectory(fileManager: fileManager)
        guard fileManager.fileExists(atPath: cacheDirectory.path) else {
            return
        }

        try fileManager.removeItem(at: cacheDirectory)
    }

    private func loadCachedResponse(forWeek weekIdentifier: String) throws -> CalendarResponse {
        let data = try Data(contentsOf: cacheURL(forWeek: weekIdentifier))
        return try decoder.decode(CalendarResponse.self, from: data)
    }

    private func saveCachedResponse(_ response: CalendarResponse, forWeek weekIdentifier: String) throws {
        let cacheDirectory = try Self.cacheDirectory(fileManager: fileManager)
            .appendingPathComponent(cacheNamespace, isDirectory: true)
        try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        let data = try encoder.encode(response)
        try data.write(to: cacheURL(forWeek: weekIdentifier), options: [.atomic])
    }

    private func cacheURL(forWeek weekIdentifier: String) throws -> URL {
        try Self.cacheDirectory(fileManager: fileManager)
            .appendingPathComponent(cacheNamespace, isDirectory: true)
            .appendingPathComponent(weekIdentifier)
            .appendingPathExtension("json")
    }

    private var cacheNamespace: String {
        calendarBaseURL.absoluteString
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private func isCacheFresh(forWeek weekIdentifier: String) -> Bool {
        guard
            let attributes = try? fileManager.attributesOfItem(atPath: cacheURL(forWeek: weekIdentifier).path),
            let modificationDate = attributes[.modificationDate] as? Date
        else {
            return false
        }

        return abs(modificationDate.timeIntervalSinceNow) <= cacheLifetime
    }

    private static func cacheDirectory(fileManager: FileManager) throws -> URL {
        try fileManager.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        .appendingPathComponent(cacheDirectoryName, isDirectory: true)
    }
}

private enum CachePolicy {
    case useFreshCache
    case forceRemote
}

enum RemoteCalendarServiceError: LocalizedError {
    case invalidResponse
    case invalidPayload
    case requestFailed(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The remote calendar returned an invalid response."
        case .invalidPayload:
            return "The remote calendar data could not be parsed."
        case let .requestFailed(statusCode):
            return "The remote calendar request failed with status \(statusCode)."
        }
    }
}
