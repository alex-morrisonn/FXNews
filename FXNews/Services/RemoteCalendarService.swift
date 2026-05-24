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
    private let calendarBaseURL: URL

    init(
        session: URLSession = .shared,
        fileManager: FileManager = .default,
        calendarBaseURL: URL = RemoteCalendarService.calendarBaseURL,
        now: @escaping @Sendable () -> Date = Date.init,
        cacheLifetime: TimeInterval? = nil,
        bypassCache: Bool? = nil,
        preferBundledSource: Bool? = nil
    ) {
        self.session = session
        self.calendarBaseURL = calendarBaseURL

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func fetchEvents(from startDate: Date, to endDate: Date) async throws -> CalendarFetchResult {
        let result = try await loadResponse(for: startDate)
        return filteredResult(from: result, startDate: startDate, endDate: endDate)
    }

    func refreshEvents(from startDate: Date, to endDate: Date) async throws -> CalendarFetchResult {
        let result = try await loadResponse(for: startDate)
        return filteredResult(from: result, startDate: startDate, endDate: endDate)
    }

    func refreshEventsIfNeededOnAppOpen(from startDate: Date, to endDate: Date) async throws -> CalendarFetchResult {
        let result = try await loadResponse(for: startDate)
        return filteredResult(from: result, startDate: startDate, endDate: endDate)
    }

    private func filteredResult(from result: CalendarFetchResult, startDate: Date, endDate: Date) -> CalendarFetchResult {
        CalendarFetchResult(
            events: result.events
                .filter { $0.timestamp >= startDate && $0.timestamp < endDate }
                .sorted { $0.timestamp < $1.timestamp },
            source: result.source,
            lastUpdated: result.lastUpdated,
            isFallback: false
        )
    }

    private func loadResponse(for startDate: Date) async throws -> CalendarFetchResult {
        let weekIdentifier = Self.weekIdentifier(for: startDate)
        let remoteResponse = try await fetchRemoteResponse(forWeek: weekIdentifier)

        return CalendarFetchResult(
            events: remoteResponse.events,
            source: .remote,
            lastUpdated: remoteResponse.lastUpdated,
            isFallback: false
        )
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
        // Calendar data now comes only from Cloudflare, so there is no local calendar cache to clear.
    }
}

enum RemoteCalendarServiceError: LocalizedError {
    case invalidResponse
    case invalidPayload
    case requestFailed(statusCode: Int)
    case noDataAvailable

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The remote calendar returned an invalid response."
        case .invalidPayload:
            return "The remote calendar data could not be parsed."
        case let .requestFailed(statusCode):
            return "The remote calendar request failed with status \(statusCode)."
        case .noDataAvailable:
            return "No calendar data is available from Cloudflare. Pull to refresh to try again."
        }
    }
}
