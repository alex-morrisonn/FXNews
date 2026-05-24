import Foundation
import Observation

@MainActor
@Observable
final class CalendarViewModel {
    private let service: CalendarService

    var events: [EconomicEvent] = []
    var isLoading = false
    var errorMessage: String?
    var lastRefreshDate: Date?
    var visibleInterval: DateInterval?
    var dataSource: CalendarDataSource?
    var isShowingFallbackData = false

    init(service: CalendarService) {
        self.service = service
    }

    @discardableResult
    func loadCurrentWeek(timeZone: TimeZone = .current) async -> Bool {
        let interval = Calendar.tradingWeekInterval(timeZone: timeZone)
        return await load(interval: interval, forceRefresh: false)
    }

    @discardableResult
    func refresh() async -> Bool {
        let interval = visibleInterval ?? Calendar.tradingWeekInterval()
        return await load(interval: interval, forceRefresh: true)
    }

    @discardableResult
    func refreshIfNeededOnAppOpen() async -> Bool {
        let interval = visibleInterval ?? Calendar.tradingWeekInterval()
        return await load(interval: interval, forceRefresh: false, refreshIfNeededOnAppOpen: true)
    }

    @discardableResult
    func loadWeek(referenceDate: Date = Date(), weekOffset: Int = 0, timeZone: TimeZone = .current) async -> Bool {
        let interval = Calendar.tradingWeekInterval(referenceDate: referenceDate, weekOffset: weekOffset, timeZone: timeZone)
        return await load(interval: interval, forceRefresh: false)
    }

    func clearCache() throws {
        guard service is RemoteCalendarService else {
            return
        }

        try RemoteCalendarService.clearCache()
        lastRefreshDate = nil
    }

    private func load(interval: DateInterval, forceRefresh: Bool, refreshIfNeededOnAppOpen: Bool = false) async -> Bool {
        isLoading = true
        errorMessage = nil
        visibleInterval = interval

        do {
            let result: CalendarFetchResult
            if forceRefresh, let remoteService = service as? RemoteCalendarService {
                result = try await remoteService.refreshEvents(from: interval.start, to: interval.end)
            } else if refreshIfNeededOnAppOpen, let remoteService = service as? RemoteCalendarService {
                result = try await remoteService.refreshEventsIfNeededOnAppOpen(from: interval.start, to: interval.end)
            } else {
                result = try await service.fetchEvents(from: interval.start, to: interval.end)
            }
            events = EconomicEvent.uniquingIDs(in: result.events)
            dataSource = result.source
            isShowingFallbackData = result.isFallback
            lastRefreshDate = result.lastUpdated
            isLoading = false
            return true
        } catch {
            errorMessage = error.localizedDescription
            isShowingFallbackData = false

            if events.isEmpty {
                dataSource = nil
            }

            isLoading = false
            return false
        }
    }

    var availableCurrencies: [String] {
        Array(Set(events.map(\.currencyCode))).sorted()
    }

    var availablePairSymbols: [String] {
        Array(Set(events.flatMap(\.relatedPairs))).sorted()
    }

    func events(forPair symbol: String) -> [EconomicEvent] {
        let normalizedSymbol = Self.normalizePairSymbol(symbol)
        let pairCurrencies = Self.currencyCodes(inPairSymbol: normalizedSymbol)

        return events.filter { event in
            let normalizedEventPairs = Set(event.relatedPairs.map(Self.normalizePairSymbol(_:)))

            if normalizedEventPairs.contains(normalizedSymbol) {
                return true
            }

            return pairCurrencies.contains(event.currencyCode.uppercased())
        }
    }

    func nextEvent(forPair symbol: String, now: Date = Date()) -> EconomicEvent? {
        events(forPair: symbol)
            .filter { $0.timestamp >= now }
            .min { $0.timestamp < $1.timestamp }
    }

    private static func currencyCodes(inPairSymbol symbol: String) -> Set<String> {
        guard symbol.count == 6 else {
            return []
        }

        return [
            String(symbol.prefix(3)),
            String(symbol.suffix(3))
        ]
    }

    private static func normalizePairSymbol(_ symbol: String) -> String {
        symbol
            .uppercased()
            .filter(\.isLetter)
    }
}
