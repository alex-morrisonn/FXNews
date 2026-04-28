import SwiftUI

enum MarketBoardDefinition: CaseIterable, Identifiable {
    case sydney
    case tokyo
    case london
    case newYork

    var id: String { cityName }

    var cityName: String {
        switch self {
        case .sydney:
            "Sydney"
        case .tokyo:
            "Tokyo"
        case .london:
            "London"
        case .newYork:
            "New York"
        }
    }

    var flag: String {
        switch self {
        case .sydney:
            "🇦🇺"
        case .tokyo:
            "🇯🇵"
        case .london:
            "🇬🇧"
        case .newYork:
            "🇺🇸"
        }
    }

    var timeZone: TimeZone {
        switch self {
        case .sydney:
            TimeZone(identifier: "Australia/Sydney") ?? .current
        case .tokyo:
            TimeZone(identifier: "Asia/Tokyo") ?? .current
        case .london:
            TimeZone(identifier: "Europe/London") ?? .current
        case .newYork:
            TimeZone(identifier: "America/New_York") ?? .current
        }
    }

    var openHour: Int {
        switch self {
        case .sydney:
            7
        case .tokyo:
            9
        case .london:
            8
        case .newYork:
            8
        }
    }

    var closeHour: Int {
        switch self {
        case .sydney:
            16
        case .tokyo:
            18
        case .london:
            17
        case .newYork:
            17
        }
    }

    var color: Color {
        switch self {
        case .sydney:
            Color(red: 0.26, green: 0.39, blue: 0.83)
        case .tokyo:
            Color(red: 0.64, green: 0.13, blue: 0.57)
        case .london:
            Color(red: 0.27, green: 0.54, blue: 0.89)
        case .newYork:
            Color(red: 0.43, green: 0.78, blue: 0.22)
        }
    }
}

enum ForexSessionDefinition: CaseIterable, Identifiable {
    case asian
    case london
    case newYork

    var id: String { shortTitle }

    var title: String {
        switch self {
        case .asian:
            "Sydney/Tokyo"
        case .london:
            "London"
        case .newYork:
            "New York"
        }
    }

    var shortTitle: String {
        switch self {
        case .asian:
            "Asian"
        case .london:
            "London"
        case .newYork:
            "New York"
        }
    }

    var startTimeZone: TimeZone {
        switch self {
        case .asian:
            TimeZone(identifier: "Australia/Sydney") ?? .current
        case .london:
            TimeZone(identifier: "Europe/London") ?? .current
        case .newYork:
            TimeZone(identifier: "America/New_York") ?? .current
        }
    }

    var endTimeZone: TimeZone {
        switch self {
        case .asian:
            TimeZone(identifier: "Asia/Tokyo") ?? .current
        case .london:
            TimeZone(identifier: "Europe/London") ?? .current
        case .newYork:
            TimeZone(identifier: "America/New_York") ?? .current
        }
    }

    var startHour: Int {
        switch self {
        case .asian: 7
        case .london: 8
        case .newYork: 8
        }
    }

    var startMinute: Int { 0 }

    var endHour: Int {
        switch self {
        case .asian: 18
        case .london: 17
        case .newYork: 17
        }
    }

    var endMinute: Int { 0 }

    var color: Color {
        switch self {
        case .asian:
            Color(red: 0.15, green: 0.49, blue: 0.69)
        case .london:
            FXNewsPalette.accent
        case .newYork:
            Color(red: 0.72, green: 0.32, blue: 0.20)
        }
    }
}

enum ForexOverlapDefinition: CaseIterable, Identifiable {
    case asianLondon
    case londonNewYork

    var id: String { shortTitle }

    var title: String {
        switch self {
        case .asianLondon:
            "Asian/London Overlap"
        case .londonNewYork:
            "London/New York Overlap"
        }
    }

    var shortTitle: String {
        switch self {
        case .asianLondon:
            "Asia/London"
        case .londonNewYork:
            "London/NY"
        }
    }

    var note: String {
        switch self {
        case .asianLondon:
            "Early European liquidity comes online while Asia is still active."
        case .londonNewYork:
            "Highest-volume period for most forex pairs."
        }
    }

    var sessions: (ForexSessionDefinition, ForexSessionDefinition) {
        switch self {
        case .asianLondon:
            (.asian, .london)
        case .londonNewYork:
            (.london, .newYork)
        }
    }

    var color: Color {
        switch self {
        case .asianLondon:
            Color(red: 0.31, green: 0.55, blue: 0.73)
        case .londonNewYork:
            Color(red: 0.87, green: 0.58, blue: 0.15)
        }
    }
}

struct TimelineSegment {
    let start: Double
    let length: Double
}
