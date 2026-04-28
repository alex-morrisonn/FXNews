import Foundation

enum CalendarDataSource: String {
    case remote
    case cache
    case bundled
}

struct CalendarFetchResult {
    let events: [EconomicEvent]
    let source: CalendarDataSource
    let lastUpdated: Date
    let isFallback: Bool
}

protocol CalendarService {
    func fetchEvents(from startDate: Date, to endDate: Date) async throws -> CalendarFetchResult
}
