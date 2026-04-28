import SwiftUI

enum ImpactLevel: String, Codable, CaseIterable, Identifiable {
    case low
    case medium
    case high

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .low:
            .yellow
        case .medium:
            .orange
        case .high:
            .red
        }
    }

    var label: String {
        rawValue.capitalized
    }

    var rank: Int {
        switch self {
        case .low:
            0
        case .medium:
            1
        case .high:
            2
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        switch rawValue {
        case Self.low.rawValue, "holiday":
            self = .low
        case Self.medium.rawValue:
            self = .medium
        case Self.high.rawValue:
            self = .high
        default:
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported impact level: \(rawValue)")
        }
    }
}
