import Testing
@testable import FXNews

struct ImpactLevelTests {
    @Test
    func impactLevelsExposeStableOrderingAndLabels() {
        #expect(ImpactLevel.low.rank < ImpactLevel.medium.rank)
        #expect(ImpactLevel.medium.rank < ImpactLevel.high.rank)
        #expect(ImpactLevel.allCases.map(\.label) == ["Low", "Medium", "High"])
    }
}
