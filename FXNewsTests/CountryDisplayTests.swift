import Testing
@testable import FXNews

struct CountryDisplayTests {
    @Test
    func flagHandlesEuropeanUnionAndCaseInsensitiveCountryCodes() {
        #expect(CountryDisplay.flag(for: "EU") == "🇪🇺")
        #expect(CountryDisplay.flag(for: "us") == "🇺🇸")
        #expect(CountryDisplay.flag(for: "GB") == "🇬🇧")
    }
}
