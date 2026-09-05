import CreekCore
import CreekRunner
import Foundation
import Testing
@testable import CrickiOS

private final class MemorySnapshotStore: SnapshotStoring {
    var data: Data?

    func save(_ data: Data) {
        self.data = data
    }

    func load() throws -> Data {
        guard let data else { throw CocoaError(.fileNoSuchFile) }
        return data
    }
}

@MainActor
@Test("Session advances only by explicit fixed-tick intents")
func explicitSteppingOnly() throws {
    let session = try SimulationSession(snapshotStore: MemorySnapshotStore())
    let initial = session.projection

    #expect(session.projection.tick == 0)
    #expect(session.projection == initial)
    session.advance(ticks: 1)
    #expect(session.projection.tick == 1)
    session.advance(ticks: 10)
    #expect(session.projection.tick == 11)
}

@MainActor
@Test("Rock intent is applied by authoritative simulator command")
func rockIntent() throws {
    let session = try SimulationSession(snapshotStore: MemorySnapshotStore())

    try session.placeRock(cell: 2, resistance: 0.8)

    #expect(session.projection.cells[2].rockResistance == 0.8)
    #expect(session.projection.tick == 0)
    #expect(session.projection.violations.isEmpty)
}

@MainActor
@Test("Snapshot persistence restores exact projected state")
func saveResume() throws {
    let store = MemorySnapshotStore()
    let session = try SimulationSession(snapshotStore: store)
    try session.placeRock()
    session.advance(ticks: 25)
    let saved = session.projection
    try session.save()

    session.advance(ticks: 10)
    #expect(session.projection != saved)
    try session.resume()

    #expect(session.projection.tick == saved.tick)
    #expect(session.projection.cells == saved.cells)
    #expect(session.projection.totalWater == saved.totalWater)
    #expect(session.projection.totalSediment == saved.totalSediment)
    #expect(session.projection.scenarioName == saved.scenarioName)
}

@MainActor
@Test("Loading a scenario resets from its authoritative definition")
func scenarioLoading() throws {
    let session = try SimulationSession(snapshotStore: MemorySnapshotStore())
    session.advance(ticks: 5)

    try session.load(BuiltInScenarios.rock)

    #expect(session.projection.scenarioName == "rock")
    #expect(session.projection.tick == 0)
    #expect(session.projection.cells[2].rockResistance == 0)
}
