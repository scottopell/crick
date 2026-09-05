import CreekCore
import CreekRunner
import Foundation
import Observation

struct CellProjection: Equatable, Identifiable {
    let id: Int
    let bedElevation: Double
    let waterDepth: Double
    let suspendedSediment: Double
    let rockResistance: Double
}

struct SimulationProjection: Equatable {
    let scenarioName: String
    let tick: UInt64
    let totalWater: Double
    let totalSediment: Double
    let waterResidual: Double
    let sedimentResidual: Double
    let violations: [String]
    let cells: [CellProjection]
}

protocol SnapshotStoring {
    func save(_ data: Data) throws
    func load() throws -> Data
}

struct FileSnapshotStore: SnapshotStoring {
    let url: URL

    func save(_ data: Data) throws {
        try data.write(to: url, options: .atomic)
    }

    func load() throws -> Data {
        try Data(contentsOf: url)
    }

    static func applicationSupport() throws -> Self {
        let manager = FileManager.default
        let directory = try manager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("Crick", isDirectory: true)
        try manager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return Self(url: directory.appendingPathComponent("current.crick.json"))
    }
}

private struct ClientSnapshot: Codable {
    let scenarioName: String
    let simulation: SimulationSnapshot
}

@MainActor
@Observable
final class SimulationSession {
    private var simulator: Simulator
    private let snapshotStore: any SnapshotStoring

    private(set) var projection: SimulationProjection
    private(set) var message = "Ready"

    init(
        scenario: ScenarioDefinition = BuiltInScenarios.baseline,
        snapshotStore: any SnapshotStoring
    ) throws {
        let simulator = try Simulator(state: scenario.initialState)
        self.simulator = simulator
        self.snapshotStore = snapshotStore
        self.projection = Self.project(
            scenarioName: scenario.name,
            simulator: simulator
        )
    }

    func load(_ scenario: ScenarioDefinition) throws {
        simulator = try Simulator(state: scenario.initialState)
        refresh(scenarioName: scenario.name)
        message = "Loaded \(scenario.name)"
    }

    func advance(ticks: UInt64) {
        simulator.step(count: ticks)
        refresh()
        message = "Advanced \(ticks) fixed tick\(ticks == 1 ? "" : "s")"
    }

    func placeRock(cell: Int = 2, resistance: Double = 0.8) throws {
        try simulator.apply(ScheduledCommand(
            tick: simulator.state.tick,
            command: .placeRock(cell: cell, resistance: resistance)
        ))
        refresh()
        message = "Placed rock at cell \(cell)"
    }

    func save() throws {
        let snapshot = ClientSnapshot(
            scenarioName: projection.scenarioName,
            simulation: SimulationSnapshot(simulator: simulator)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try snapshotStore.save(try encoder.encode(snapshot))
        message = "Saved tick \(simulator.state.tick)"
    }

    func resume() throws {
        let snapshot = try JSONDecoder().decode(
            ClientSnapshot.self,
            from: snapshotStore.load()
        )
        simulator = try snapshot.simulation.restore()
        refresh(scenarioName: snapshot.scenarioName)
        message = "Resumed tick \(simulator.state.tick)"
    }

    private func refresh(scenarioName: String? = nil) {
        projection = Self.project(
            scenarioName: scenarioName ?? projection.scenarioName,
            simulator: simulator
        )
    }

    private static func project(
        scenarioName: String,
        simulator: Simulator
    ) -> SimulationProjection {
        let diagnostics = simulator.diagnostics()
        return SimulationProjection(
            scenarioName: scenarioName,
            tick: simulator.state.tick,
            totalWater: simulator.state.totalWater,
            totalSediment: simulator.state.totalSediment,
            waterResidual: diagnostics.balance.waterResidual,
            sedimentResidual: diagnostics.balance.sedimentResidual,
            violations: diagnostics.violations,
            cells: simulator.state.cells.enumerated().map { index, cell in
                CellProjection(
                    id: index,
                    bedElevation: cell.bedElevation,
                    waterDepth: cell.waterDepth,
                    suspendedSediment: cell.suspendedSediment,
                    rockResistance: cell.rockResistance
                )
            }
        )
    }
}
