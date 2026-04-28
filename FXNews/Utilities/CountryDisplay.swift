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
}
