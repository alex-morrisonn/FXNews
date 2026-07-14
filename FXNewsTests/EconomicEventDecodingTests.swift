import Foundation
import Testing
@testable import FXNews

@MainActor
struct EconomicEventDecodingTests {
    @Test
    func eventDecodesFromProductionCalendarSchema() throws {
        let json = """
        {
          "id": "2026-04-14-us-core-retail-sales",
          "title": "Core Retail Sales m/m",
          "country": "US",
          "currency": "USD",
          "timestamp": "2026-04-14T12:30:00Z",
          "impact": "high",
          "forecast": "0.4%",
          "previous": "0.6%",
          "actual": null,
          "category": "consumption",
          "relatedPairs": ["EURUSD", "GBPUSD", "USDJPY"]
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let event = try decoder.decode(EconomicEvent.self, from: try #require(json.data(using: .utf8)))

        #expect(event.id == "2026-04-14-us-core-retail-sales")
        #expect(event.countryCode == "US")
        #expect(event.currencyCode == "USD")
        #expect(event.impactLevel == .high)
        #expect(event.category == "consumption")
        #expect(event.relatedPairs == ["EURUSD", "GBPUSD", "USDJPY"])
        #expect(event.actual == nil)
    }

    @Test
    func calendarResponseDecodesFromProductionSchema() throws {
        let json = """
        {
          "weekOf": "2026-04-13",
          "lastUpdated": "2026-04-13T06:00:00Z",
          "events": [
            {
              "id": "2026-04-14-us-cpi",
              "title": "US CPI m/m",
              "country": "US",
              "currency": "USD",
              "timestamp": "2026-04-14T12:30:00Z",
              "impact": "high",
              "forecast": "0.3%",
              "previous": "0.2%",
              "actual": null,
              "category": "inflation",
              "relatedPairs": ["EURUSD", "GBPUSD", "USDJPY"]
            }
          ]
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let calendar = try CalendarResponse.decode(from: try #require(json.data(using: .utf8)), using: decoder)

        #expect(calendar.weekOf == "2026-04-13")
        #expect(calendar.events.map(\.id) == ["2026-04-14-us-cpi"])
        #expect(calendar.events.first?.impactLevel == .high)
        #expect(calendar.events.first?.relatedPairs == ["EURUSD", "GBPUSD", "USDJPY"])
    }

    @Test
    func forexFactoryExportDecodesFromRawArraySchema() throws {
        let json = """
        [
          {
            "title": "Bank Holiday",
            "country": "NZD",
            "date": "2026-04-26T16:00:00-04:00",
            "impact": "Holiday",
            "forecast": "",
            "previous": ""
          },
          {
            "title": "Federal Funds Rate",
            "country": "USD",
            "date": "2026-04-29T14:00:00-04:00",
            "impact": "High",
            "forecast": "3.75%",
            "previous": "3.75%"
          }
        ]
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let events = try decoder.decode([EconomicEvent].self, from: try #require(json.data(using: .utf8)))

        #expect(events.count == 2)
        #expect(events[0].currencyCode == "NZD")
        #expect(events[0].countryCode == "NZ")
        #expect(events[0].impactLevel == .low)
        #expect(events[0].forecast == nil)
        #expect(events[0].previous == nil)
        #expect(!events[0].id.isEmpty)
        #expect(events[0].relatedPairs == ["NZDUSD", "AUDNZD", "EURNZD"])
        #expect(events[1].currencyCode == "USD")
        #expect(events[1].countryCode == "US")
        #expect(events[1].impactLevel == .high)
    }

    @Test
    func eventDecodingTrimsOptionalTextAndGeneratesStableIDWhenMissing() throws {
        let json = """
        {
          "title": "  Fed Chair Speech  ",
          "country": " usd ",
          "date": "2026-04-29T14:00:00-04:00",
          "impact": "Medium",
          "forecast": "   ",
          "previous": " 1.2% ",
          "actual": "",
          "category": " Central Bank "
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let event = try decoder.decode(EconomicEvent.self, from: try #require(json.data(using: .utf8)))

        #expect(event.id == "usd-2026-04-29T18:00:00Z-fed-chair-speech")
        #expect(event.title == "  Fed Chair Speech  ")
        #expect(event.currencyCode == "USD")
        #expect(event.countryCode == "US")
        #expect(event.impactLevel == .medium)
        #expect(event.forecast == nil)
        #expect(event.previous == "1.2%")
        #expect(event.actual == nil)
        #expect(event.category == "Central Bank")
        #expect(event.relatedPairs == ["EURUSD", "GBPUSD", "USDJPY", "XAUUSD"])
        #expect(event.hasNumericContext)
    }

    @Test
    func eventDecodingUsesCurrencyFallbackCountryForUnknownCurrency() throws {
        let json = """
        {
          "title": "Gold Volatility",
          "currency": "XAU",
          "timestamp": "2026-04-29T18:00:00Z",
          "impact": "low"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let event = try decoder.decode(EconomicEvent.self, from: try #require(json.data(using: .utf8)))

        #expect(event.currencyCode == "XAU")
        #expect(event.countryCode == "XA")
        #expect(event.relatedPairs.isEmpty)
    }

    @Test
    func calendarDayDisplayOrderPrioritizesHolidaysBeforeTimedEvents() throws {
        let formatter = ISO8601DateFormatter()
        let holiday = EconomicEvent(
            id: "holiday",
            title: "Bank Holiday",
            countryCode: "GB",
            currencyCode: "GBP",
            timestamp: try #require(formatter.date(from: "2026-05-04T03:00:00Z")),
            impactLevel: .low
        )
        let earlierEvent = EconomicEvent(
            id: "earlier",
            title: "Manufacturing PMI",
            countryCode: "GB",
            currencyCode: "GBP",
            timestamp: try #require(formatter.date(from: "2026-05-04T01:00:00Z")),
            impactLevel: .medium
        )
        let laterEvent = EconomicEvent(
            id: "later",
            title: "Services PMI",
            countryCode: "GB",
            currencyCode: "GBP",
            timestamp: try #require(formatter.date(from: "2026-05-04T09:00:00Z")),
            impactLevel: .high
        )

        let sortedEvents = [laterEvent, earlierEvent, holiday].sorted(by: EconomicEvent.calendarDayDisplayOrder)

        #expect(sortedEvents.map { $0.id } == ["holiday", "earlier", "later"])
    }

    @Test
    func uniquingIDsAppendsStableSuffixesForDuplicateEvents() throws {
        let formatter = ISO8601DateFormatter()
        let timestamp = try #require(formatter.date(from: "2026-05-07T14:00:00Z"))
        let first = EconomicEvent(
            id: "usd-2026-05-07T14:00:00Z-construction-spending-m-m",
            title: "Construction Spending m/m",
            countryCode: "US",
            currencyCode: "USD",
            timestamp: timestamp,
            impactLevel: .medium
        )
        let second = EconomicEvent(
            id: "usd-2026-05-07T14:00:00Z-construction-spending-m-m",
            title: "Construction Spending m/m",
            countryCode: "US",
            currencyCode: "USD",
            timestamp: timestamp,
            impactLevel: .medium
        )
        let third = EconomicEvent(
            id: "usd-2026-05-07T14:00:00Z-construction-spending-m-m",
            title: "Construction Spending m/m",
            countryCode: "US",
            currencyCode: "USD",
            timestamp: timestamp,
            impactLevel: .high
        )

        let uniqued = EconomicEvent.uniquingIDs(in: [first, second, third])

        #expect(uniqued.map { $0.id } == [
            "usd-2026-05-07T14:00:00Z-construction-spending-m-m",
            "usd-2026-05-07T14:00:00Z-construction-spending-m-m--2",
            "usd-2026-05-07T14:00:00Z-construction-spending-m-m--3"
        ])
    }
}
