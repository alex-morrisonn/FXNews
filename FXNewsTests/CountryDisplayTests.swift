import Testing
@testable import FXNews

struct CountryDisplayTests {
    @Test
    func flagHandlesEuropeanUnionAndCaseInsensitiveCountryCodes() {
        #expect(CountryDisplay.flag(for: "EU") == "🇪🇺")
        #expect(CountryDisplay.flag(for: "us") == "🇺🇸")
        #expect(CountryDisplay.flag(for: "GB") == "🇬🇧")
    }

    @Test
    func nameUsesFriendlyRegionNames() {
        #expect(CountryDisplay.name(for: "EU") == "Euro Area")
        #expect(!CountryDisplay.name(for: "US").isEmpty)
    }
}
