import CreekCore
import CreekRunner
import Foundation
import Testing
@testable import CrickiOS

private final class MemorySnapshotStore: SnapshotStoring {
    var data: Data?

    func exists() -> Bool { data != nil }

    func save(_ data: Data) {
        self.data = data
    }

    func load() throws -> Data {
        guard let data else { throw CocoaError(.fileNoSuchFile) }
        return data
    }
}

@MainActor
@Test("Resume is unavailable until a snapshot exists")
func resumeAvailability() throws {
    let store = MemorySnapshotStore()
    let session = try SimulationSession(snapshotStore: store)

    #expect(!session.canResume)
    try session.save()
    #expect(session.canResume)
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
    #expect(session.projection.rockEffect == nil)
}

@MainActor
@Test("Tapped rock causes upstream pooling and downstream reduction")
func causalRockEffect() throws {
    let baseline = try SimulationSession(snapshotStore: MemorySnapshotStore())
    let obstructed = try SimulationSession(snapshotStore: MemorySnapshotStore())

    try obstructed.placeRock(cell: 2, resistance: 0.8)
    baseline.advance(ticks: 40)
    obstructed.advance(ticks: 40)

    #expect(obstructed.projection.cells[2].waterDepth
        > baseline.projection.cells[2].waterDepth)
    #expect(obstructed.projection.cells[3].waterDepth
        < baseline.projection.cells[3].waterDepth)
    #expect(obstructed.projection.rockEffect?.cell == 2)
    #expect(obstructed.projection.rockEffect?.elapsedTicks == 40)
    #expect(obstructed.projection.rockEffect?.upstreamDepthChange != 0)
    #expect(obstructed.projection.rockEffect?.downstreamDepthChange != nil)
    #expect(obstructed.projection.rockEffect?.flowPastRock != nil)
    #expect(obstructed.projection.violations.isEmpty)
}

@MainActor
@Test("Effect follows the latest selected rock and handles the outlet")
func selectedRockAttribution() throws {
    let session = try SimulationSession(snapshotStore: MemorySnapshotStore())
    try session.placeRock(cell: 1, resistance: 0.4)
    try session.placeRock(cell: 5, resistance: 0.7)

    session.advance(ticks: 3)

    #expect(session.projection.rockEffect?.cell == 5)
    #expect(session.projection.rockEffect?.elapsedTicks == 3)
    #expect(session.projection.rockEffect?.downstreamDepthChange == nil)
    #expect(session.projection.rockEffect?.flowPastRock == nil)
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
@Test("Malformed resume preserves the current authoritative projection")
func malformedResumePreservesState() throws {
    let store = MemorySnapshotStore()
    store.data = Data("not a snapshot".utf8)
    let session = try SimulationSession(snapshotStore: store)
    session.advance(ticks: 7)
    let before = session.projection

    #expect(throws: Error.self) {
        try session.resume()
    }
    #expect(session.projection == before)
    #expect(session.canResume)
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
