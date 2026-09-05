import Testing
@testable import CreekCore

@Test("A scenario has a deterministic summary")
func deterministicScenarioSummary() {
    let first = Scenario(seed: 42)
    let replay = Scenario(seed: 42)

    #expect(first == replay)
    #expect(first.summary == "Crick scenario seed: 42")
}
