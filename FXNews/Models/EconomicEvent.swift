import Foundation

struct EconomicEvent: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let countryCode: String
    let currencyCode: String
    let timestamp: Date
    let impactLevel: ImpactLevel
    let forecast: String?
    let previous: String?
    let actual: String?
    let category: String?
    let relatedPairs: [String]

    init(
        id: String = UUID().uuidString,
        title: String,
        countryCode: String,
        currencyCode: String,
        timestamp: Date,
        impactLevel: ImpactLevel,
        forecast: String? = nil,
        previous: String? = nil,
        actual: String? = nil,
        category: String? = nil,
        relatedPairs: [String] = []
    ) {
        self.id = id
        self.title = title
        self.countryCode = countryCode
        self.currencyCode = currencyCode
        self.timestamp = timestamp
        self.impactLevel = impactLevel
        self.forecast = forecast
        self.previous = previous
        self.actual = actual
        self.category = category
        self.relatedPairs = relatedPairs
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case countryCode = "country"
        case currencyCode = "currency"
        case timestamp
        case date
        case impactLevel = "impact"
        case forecast
        case previous
        case actual
        case category
        case relatedPairs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let title = try container.decode(String.self, forKey: .title)
        let currencyCode = try Self.decodeCurrencyCode(from: container)
        let countryCode = try Self.decodeCountryCode(from: container, currencyCode: currencyCode)
        let timestamp = try Self.decodeTimestamp(from: container)
        let impactLevel = try container.decode(ImpactLevel.self, forKey: .impactLevel)
        let forecast = try Self.decodeOptionalString(from: container, forKey: .forecast)
        let previous = try Self.decodeOptionalString(from: container, forKey: .previous)
        let actual = try Self.decodeOptionalString(from: container, forKey: .actual)
        let category = try Self.decodeOptionalString(from: container, forKey: .category)
        let relatedPairs = try container.decodeIfPresent([String].self, forKey: .relatedPairs)
            ?? Self.defaultRelatedPairs(for: currencyCode)
        let id = try container.decodeIfPresent(String.self, forKey: .id)
            ?? Self.makeID(title: title, currencyCode: currencyCode, timestamp: timestamp)

        self.init(
            id: id,
            title: title,
            countryCode: countryCode,
            currencyCode: currencyCode,
            timestamp: timestamp,
            impactLevel: impactLevel,
            forecast: forecast,
            previous: previous,
            actual: actual,
            category: category,
            relatedPairs: relatedPairs
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(countryCode, forKey: .countryCode)
        try container.encode(currencyCode, forKey: .currencyCode)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(impactLevel, forKey: .impactLevel)
        try container.encodeIfPresent(forecast, forKey: .forecast)
        try container.encodeIfPresent(previous, forKey: .previous)
        try container.encodeIfPresent(actual, forKey: .actual)
        try container.encodeIfPresent(category, forKey: .category)
        try container.encode(relatedPairs, forKey: .relatedPairs)
    }

    private static func decodeCurrencyCode(from container: KeyedDecodingContainer<CodingKeys>) throws -> String {
        if let currencyCode = try container.decodeIfPresent(String.self, forKey: .currencyCode)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !currencyCode.isEmpty {
            return currencyCode.uppercased()
        }

        if let countryValue = try container.decodeIfPresent(String.self, forKey: .countryCode)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !countryValue.isEmpty {
            return countryValue.uppercased()
        }

        throw DecodingError.keyNotFound(
            CodingKeys.currencyCode,
            DecodingError.Context(codingPath: container.codingPath, debugDescription: "Expected either currency or country code.")
        )
    }

    private static func decodeCountryCode(
        from container: KeyedDecodingContainer<CodingKeys>,
        currencyCode: String
    ) throws -> String {
        guard let rawCountry = try container.decodeIfPresent(String.self, forKey: .countryCode)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !rawCountry.isEmpty else {
            return defaultCountryCode(for: currencyCode)
        }

        let normalized = rawCountry.uppercased()
        if normalized.count == 2 {
            return normalized
        }

        return defaultCountryCode(for: normalized)
    }

    private static func decodeTimestamp(from container: KeyedDecodingContainer<CodingKeys>) throws -> Date {
        if let timestamp = try container.decodeIfPresent(Date.self, forKey: .timestamp) {
            return timestamp
        }

        if let date = try container.decodeIfPresent(Date.self, forKey: .date) {
            return date
        }

        throw DecodingError.keyNotFound(
            CodingKeys.timestamp,
            DecodingError.Context(codingPath: container.codingPath, debugDescription: "Expected timestamp or date.")
        )
    }

    private static func decodeOptionalString(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws -> String? {
        guard let value = try container.decodeIfPresent(String.self, forKey: key)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty else {
            return nil
        }

        return value
    }

    private static func makeID(title: String, currencyCode: String, timestamp: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        let slug = title
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))

        return "\(currencyCode.lowercased())-\(formatter.string(from: timestamp))-\(slug)"
    }

    private static func defaultCountryCode(for currencyCode: String) -> String {
        switch currencyCode.uppercased() {
        case "AUD":
            return "AU"
        case "CAD":
            return "CA"
        case "CHF":
            return "CH"
        case "CNY":
            return "CN"
        case "EUR":
            return "EU"
        case "GBP":
            return "GB"
        case "JPY":
            return "JP"
        case "NZD":
            return "NZ"
        case "USD":
            return "US"
        default:
            return String(currencyCode.prefix(2)).uppercased()
        }
    }

    private static func defaultRelatedPairs(for currencyCode: String) -> [String] {
        switch currencyCode.uppercased() {
        case "AUD":
            return ["AUDUSD", "AUDJPY", "EURAUD"]
        case "CAD":
            return ["USDCAD", "EURCAD", "CADJPY"]
        case "CHF":
            return ["USDCHF", "EURCHF", "CHFJPY"]
        case "CNY":
            return ["USDCNH", "AUDUSD", "NZDUSD"]
        case "EUR":
            return ["EURUSD", "EURGBP", "EURJPY"]
        case "GBP":
            return ["GBPUSD", "EURGBP", "GBPJPY"]
        case "JPY":
            return ["USDJPY", "EURJPY", "GBPJPY"]
        case "NZD":
            return ["NZDUSD", "AUDNZD", "EURNZD"]
        case "USD":
            return ["EURUSD", "GBPUSD", "USDJPY", "XAUUSD"]
        default:
            return []
        }
    }

    var isHoliday: Bool {
        let normalizedTitle = title.localizedLowercase
        let normalizedCategory = category?.localizedLowercase ?? ""
        return normalizedTitle.contains("holiday") || normalizedCategory.contains("holiday")
    }

    var hasNumericContext: Bool {
        forecast != nil || previous != nil || actual != nil
    }
}
