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

struct RockEffectProjection: Equatable {
    let cell: Int
    let resistance: Double
    let elapsedTicks: UInt64
    let upstreamDepthChange: Double
    let downstreamDepthChange: Double?
    let flowPastRock: Double?
}

struct PoolObjectiveProjection: Equatable {
    let targetCell: Int
    let status: PoolObjectiveStatus
    let progressTicks: UInt64
    let requiredTicks: UInt64
    let depth: Double
    let transfer: Double

    var title: String {
        switch status {
        case .gathering: "The bend is still finding its shape"
        case .deepButQuick: "Deeper, but the current is still quick"
        case .calmButShallow: "Calmer, but the pool needs more depth"
        case .holding: "A calm pool is holding"
        }
    }
}

struct SimulationProjection: Equatable {
    let scenarioName: String
    let tick: UInt64
    let totalWater: Double
    let totalSediment: Double
    let waterResidual: Double
    let sedimentResidual: Double
    let violations: [String]
    let waterTransfers: [Double]
    let cells: [CellProjection]
    let rockEffect: RockEffectProjection?
    let poolObjective: PoolObjectiveProjection?
}

protocol SnapshotStoring {
    func save(_ data: Data) throws
    func load() throws -> Data
    func exists() -> Bool
}

struct FileSnapshotStore: SnapshotStoring {
    let url: URL

    func save(_ data: Data) throws {
        try data.write(to: url, options: .atomic)
    }

    func load() throws -> Data {
        try Data(contentsOf: url)
    }

    func removeIfPresent() throws {
        guard exists() else { return }
        try FileManager.default.removeItem(at: url)
    }

    func exists() -> Bool {
        FileManager.default.fileExists(atPath: url.path)
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
    let selectedRockCell: Int?
    let simulation: SimulationSnapshot
}

@MainActor
@Observable
final class SimulationSession {
    private var simulator: Simulator
    private var selectedRockCell: Int?
    private let snapshotStore: any SnapshotStoring

    private(set) var projection: SimulationProjection
    private(set) var message = "Ready"
    private(set) var canResume: Bool

    init(
        scenario: ScenarioDefinition = BuiltInScenarios.shapeTheBend,
        snapshotStore: any SnapshotStoring
    ) throws {
        let simulator = try Simulator(state: scenario.initialState)
        self.simulator = simulator
        self.selectedRockCell = nil
        self.snapshotStore = snapshotStore
        self.canResume = snapshotStore.exists()
        self.projection = Self.project(
            scenarioName: scenario.name,
            simulator: simulator
        )
    }

    func load(_ scenario: ScenarioDefinition) throws {
        simulator = try Simulator(state: scenario.initialState)
        selectedRockCell = nil
        refresh(scenarioName: scenario.name)
        message = "Loaded \(scenario.name)"
    }

    func advance(ticks: UInt64) {
        let before = projection
        simulator.step(count: ticks)
        refresh(effectComparedWith: before)
        message = "Advanced \(ticks) fixed tick\(ticks == 1 ? "" : "s")"
    }

    func placeRock(cell: Int = 2, resistance: Double = 0.8) throws {
        try simulator.apply(ScheduledCommand(
            tick: simulator.state.tick,
            command: .moveRock(
                from: selectedRockCell,
                to: cell,
                resistance: resistance
            )
        ))
        selectedRockCell = cell
        refresh()
        message = "Placed rock at cell \(cell)"
    }

    func save() throws {
        let snapshot = ClientSnapshot(
            scenarioName: projection.scenarioName,
            selectedRockCell: selectedRockCell,
            simulation: SimulationSnapshot(simulator: simulator)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try snapshotStore.save(try encoder.encode(snapshot))
        canResume = true
        message = "Saved tick \(simulator.state.tick)"
    }

    func resume() throws {
        let snapshot = try JSONDecoder().decode(
            ClientSnapshot.self,
            from: snapshotStore.load()
        )
        simulator = try snapshot.simulation.restore()
        selectedRockCell = snapshot.selectedRockCell
        refresh(scenarioName: snapshot.scenarioName)
        message = "Resumed tick \(simulator.state.tick)"
    }

    private func refresh(
        scenarioName: String? = nil,
        effectComparedWith previous: SimulationProjection? = nil
    ) {
        var updated = Self.project(
            scenarioName: scenarioName ?? projection.scenarioName,
            simulator: simulator
        )
        if let previous,
           let selectedRockCell,
           let rock = updated.cells.first(where: {
               $0.id == selectedRockCell && $0.rockResistance > 0
           }) {
            let downstream = updated.cells.indices.contains(rock.id + 1)
                ? updated.cells[rock.id + 1].waterDepth
                    - previous.cells[rock.id + 1].waterDepth
                : nil
            updated = SimulationProjection(
                scenarioName: updated.scenarioName,
                tick: updated.tick,
                totalWater: updated.totalWater,
                totalSediment: updated.totalSediment,
                waterResidual: updated.waterResidual,
                sedimentResidual: updated.sedimentResidual,
                violations: updated.violations,
                waterTransfers: updated.waterTransfers,
                cells: updated.cells,
                rockEffect: RockEffectProjection(
                    cell: rock.id,
                    resistance: rock.rockResistance,
                    elapsedTicks: updated.tick - previous.tick,
                    upstreamDepthChange: rock.waterDepth
                        - previous.cells[rock.id].waterDepth,
                    downstreamDepthChange: downstream,
                    flowPastRock: updated.waterTransfers.indices.contains(rock.id)
                        ? updated.waterTransfers[rock.id]
                        : nil
                ),
                poolObjective: updated.poolObjective
            )
        }
        projection = updated
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
            waterTransfers: diagnostics.lastTick?.waterTransfers ?? [],
            cells: simulator.state.cells.enumerated().map { index, cell in
                CellProjection(
                    id: index,
                    bedElevation: cell.bedElevation,
                    waterDepth: cell.waterDepth,
                    suspendedSediment: cell.suspendedSediment,
                    rockResistance: cell.rockResistance
                )
            },
            rockEffect: nil,
            poolObjective: simulator.state.poolObjectiveResult.map {
                PoolObjectiveProjection(
                    targetCell: simulator.state.poolObjective!.targetCell,
                    status: $0.status,
                    progressTicks: $0.progressTicks,
                    requiredTicks: $0.requiredTicks,
                    depth: $0.depth,
                    transfer: $0.transfer
                )
            }
        )
    }
}
