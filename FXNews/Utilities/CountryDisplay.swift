import Foundation

enum CountryDisplay {
    static func flag(for countryCode: String) -> String {
        if countryCode.uppercased() == "EU" {
            return "🇪🇺"
        }

        let scalars = countryCode.uppercased().unicodeScalars.compactMap { scalar -> UnicodeScalar? in
            guard let regionalIndicator = UnicodeScalar(127397 + scalar.value) else {
                return nil
            }
            return regionalIndicator
        }

        return String(String.UnicodeScalarView(scalars))
    }

    static func name(for countryCode: String) -> String {
        let normalizedCode = countryCode.uppercased()

        if normalizedCode == "EU" {
            return "Euro Area"
        }

        return Locale.current.localizedString(forRegionCode: normalizedCode) ?? normalizedCode
    }
}
