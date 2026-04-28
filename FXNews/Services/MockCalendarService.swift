import Foundation

struct MockCalendarService: CalendarService {
    func fetchEvents(from startDate: Date, to endDate: Date) async throws -> CalendarFetchResult {
        try await Task.sleep(for: .milliseconds(350))

        let events = weeklyEvents()
            .filter { $0.timestamp >= startDate && $0.timestamp <= endDate }
            .sorted { $0.timestamp < $1.timestamp }

        return CalendarFetchResult(
            events: events,
            source: .bundled,
            lastUpdated: Date(),
            isFallback: false
        )
    }

    private func weeklyEvents() -> [EconomicEvent] {
        let utcCalendar = Calendar.utcGregorian
        let referenceDate = Date()
        let weekInterval = utcCalendar.dateInterval(of: .weekOfYear, for: referenceDate) ?? DateInterval(start: referenceDate, duration: 7 * 24 * 60 * 60)

        return [
            EconomicEvent(
                title: "ISM Services PMI",
                countryCode: "US",
                currencyCode: "USD",
                timestamp: utcCalendar.date(
                    in: weekInterval,
                    weekday: 2,
                    hour: 14,
                    minute: 0
                ),
                impactLevel: .medium,
                forecast: "52.1",
                previous: "51.4",
                actual: nil,
                relatedPairs: ["EUR/USD", "GBP/USD", "USD/JPY"]
            ),
            EconomicEvent(
                title: "Eurozone CPI y/y",
                countryCode: "EU",
                currencyCode: "EUR",
                timestamp: utcCalendar.date(
                    in: weekInterval,
                    weekday: 3,
                    hour: 9,
                    minute: 0
                ),
                impactLevel: .high,
                forecast: "2.5%",
                previous: "2.7%",
                actual: nil,
                relatedPairs: ["EUR/USD", "EUR/GBP"]
            ),
            EconomicEvent(
                title: "BoJ Monetary Policy Statement",
                countryCode: "JP",
                currencyCode: "JPY",
                timestamp: utcCalendar.date(
                    in: weekInterval,
                    weekday: 3,
                    hour: 3,
                    minute: 0
                ),
                impactLevel: .high,
                forecast: nil,
                previous: "Maintain policy",
                actual: nil,
                relatedPairs: ["USD/JPY", "EUR/JPY", "GBP/JPY"]
            ),
            EconomicEvent(
                title: "UK Claimant Count Change",
                countryCode: "GB",
                currencyCode: "GBP",
                timestamp: utcCalendar.date(
                    in: weekInterval,
                    weekday: 4,
                    hour: 6,
                    minute: 0
                ),
                impactLevel: .medium,
                forecast: "12.4K",
                previous: "16.8K",
                actual: nil,
                relatedPairs: ["GBP/USD", "EUR/GBP"]
            ),
            EconomicEvent(
                title: "US CPI m/m",
                countryCode: "US",
                currencyCode: "USD",
                timestamp: utcCalendar.date(
                    in: weekInterval,
                    weekday: 4,
                    hour: 12,
                    minute: 30
                ),
                impactLevel: .high,
                forecast: "0.3%",
                previous: "0.2%",
                actual: nil,
                relatedPairs: ["EUR/USD", "GBP/USD", "USD/JPY"]
            ),
            EconomicEvent(
                title: "ECB Main Refinancing Rate",
                countryCode: "EU",
                currencyCode: "EUR",
                timestamp: utcCalendar.date(
                    in: weekInterval,
                    weekday: 5,
                    hour: 12,
                    minute: 15
                ),
                impactLevel: .high,
                forecast: "4.25%",
                previous: "4.25%",
                actual: nil,
                relatedPairs: ["EUR/USD", "EUR/JPY", "EUR/GBP"]
            ),
            EconomicEvent(
                title: "US Initial Jobless Claims",
                countryCode: "US",
                currencyCode: "USD",
                timestamp: utcCalendar.date(
                    in: weekInterval,
                    weekday: 5,
                    hour: 12,
                    minute: 30
                ),
                impactLevel: .low,
                forecast: "221K",
                previous: "218K",
                actual: nil,
                relatedPairs: ["EUR/USD", "USD/JPY"]
            ),
            EconomicEvent(
                title: "UK GDP m/m",
                countryCode: "GB",
                currencyCode: "GBP",
                timestamp: utcCalendar.date(
                    in: weekInterval,
                    weekday: 6,
                    hour: 6,
                    minute: 0
                ),
                impactLevel: .high,
                forecast: "0.2%",
                previous: "0.1%",
                actual: nil,
                relatedPairs: ["GBP/USD", "EUR/GBP", "GBP/JPY"]
            )
        ]
    }
}
