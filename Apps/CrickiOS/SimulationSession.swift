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
    let calmness: Double

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

private enum SavedAttemptPhase: String, Codable {
    case arranging
    case mustMove
    case outcome
    case kept
}

private struct ClientSnapshot: Codable {
    let scenarioName: String
    let selectedRockCell: Int?
    let attemptPhase: SavedAttemptPhase
    let simulation: SimulationSnapshot
    let comparisonBefore: SimulationSnapshot?
}

enum ShapeTheBendAttemptError: Error, Equatable {
    case ineligibleCell(Int)
    case stoneRequired
    case attemptAlreadyCommitted
    case noAttemptToRetry
    case noAttemptToKeep
    case attemptClosed
    case comparisonSnapshotMismatch
    case snapshotRockMismatch
    case objectiveNotHolding
}

@MainActor
@Observable
final class SimulationSession {
    static let attemptTicks: UInt64 = 20

    private var simulator: Simulator
    private var selectedRockCell: Int?
    private var requiresNewPlacement = false
    private var comparisonBeforeSnapshot: SimulationSnapshot?
    private let snapshotStore: any SnapshotStoring

    private(set) var projection: SimulationProjection
    private(set) var message = "Ready"
    private(set) var canResume: Bool
    private(set) var hasCommittedAttempt = false
    private(set) var attemptClosed = false
    private(set) var attemptStartTick: UInt64 = 0

    var eligibleStoneCells: [Int] {
        BuiltInScenarios.shapeTheBendStoneCells(current: selectedRockCell)
    }

    var canCommitAttempt: Bool {
        selectedRockCell != nil
            && !requiresNewPlacement
            && !hasCommittedAttempt
            && !attemptClosed
    }

    var mustMoveStone: Bool { requiresNewPlacement }

    // The comparison source is an immutable snapshot of the real flowing reach
    // immediately before the player's first intervention in each bounded attempt.
    var comparisonBeforeProjection: SimulationProjection? {
        guard let comparisonBeforeSnapshot,
              let before = try? comparisonBeforeSnapshot.restore() else { return nil }
        return Self.project(scenarioName: projection.scenarioName, simulator: before)
    }

    func attemptElapsedTicks(for projection: SimulationProjection) -> UInt64 {
        projection.tick >= attemptStartTick ? projection.tick - attemptStartTick : 0
    }

    init(
        scenario: ScenarioDefinition = BuiltInScenarios.shapeTheBend,
        snapshotStore: any SnapshotStoring
    ) throws {
        let simulator = try Simulator(state: scenario.initialState)
        self.simulator = simulator
        self.selectedRockCell = nil
        self.comparisonBeforeSnapshot = nil
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
        requiresNewPlacement = false
        comparisonBeforeSnapshot = nil
        hasCommittedAttempt = false
        attemptClosed = false
        attemptStartTick = 0
        projection = Self.project(scenarioName: scenario.name, simulator: simulator)
        message = "Loaded \(scenario.name)"
    }

    // Shape the Bend (1): commit exactly twenty real fixed ticks and retain
    // each immutable projection produced directly after one authoritative step.
    func commitShapeTheBendAttempt() throws -> [SimulationProjection] {
        guard !attemptClosed else { throw ShapeTheBendAttemptError.attemptClosed }
        guard selectedRockCell != nil, !requiresNewPlacement else {
            throw ShapeTheBendAttemptError.stoneRequired
        }
        guard !hasCommittedAttempt else {
            throw ShapeTheBendAttemptError.attemptAlreadyCommitted
        }

        let before = projection
        attemptStartTick = projection.tick
        var frames: [SimulationProjection] = []
        frames.reserveCapacity(Int(Self.attemptTicks))
        for _ in 0..<Self.attemptTicks {
            simulator.step()
            frames.append(Self.project(
                scenarioName: projection.scenarioName,
                simulator: simulator,
                effectComparedWith: before,
                selectedRockCell: selectedRockCell
            ))
        }
        projection = frames[frames.count - 1]
        hasCommittedAttempt = true
        message = "Tested this spot for 20 creek seconds"
        return frames
    }

    // Shape the Bend (4): only authored effective seats may reach CreekCore.
    func placeRock(cell: Int = 2, resistance: Double = 0.8) throws {
        guard !attemptClosed else { throw ShapeTheBendAttemptError.attemptClosed }
        guard !hasCommittedAttempt else {
            throw ShapeTheBendAttemptError.attemptAlreadyCommitted
        }
        guard eligibleStoneCells.contains(cell) else {
            throw ShapeTheBendAttemptError.ineligibleCell(cell)
        }
        if comparisonBeforeSnapshot == nil {
            comparisonBeforeSnapshot = SimulationSnapshot(simulator: simulator)
        }
        try simulator.apply(ScheduledCommand(
            tick: simulator.state.tick,
            command: .moveRock(
                from: selectedRockCell,
                to: cell,
                resistance: resistance
            )
        ))
        selectedRockCell = cell
        requiresNewPlacement = false
        projection = Self.project(
            scenarioName: projection.scenarioName,
            simulator: simulator
        )
        message = "Placed rock at cell \(cell)"
    }

    // Shape the Bend (3): retry keeps the evolved authoritative reach. The
    // player must move the same stone before another bounded experiment.
    func tryAnotherSpot() throws {
        guard !attemptClosed else { throw ShapeTheBendAttemptError.attemptClosed }
        guard hasCommittedAttempt else {
            throw ShapeTheBendAttemptError.noAttemptToRetry
        }
        hasCommittedAttempt = false
        requiresNewPlacement = true
        comparisonBeforeSnapshot = SimulationSnapshot(simulator: simulator)
        message = "Move the stone to another spot"
    }

    // Shape the Bend (3): keeping preserves the committed final state and
    // closes this attempt against further placement or simulation.
    func keepCreek() throws {
        guard hasCommittedAttempt else { throw ShapeTheBendAttemptError.noAttemptToKeep }
        guard !attemptClosed else { throw ShapeTheBendAttemptError.attemptClosed }
        guard projection.poolObjective?.status == .holding else {
            throw ShapeTheBendAttemptError.objectiveNotHolding
        }
        requiresNewPlacement = false
        attemptClosed = true
        message = "Kept this creek"
    }

    func save() throws {
        let savedPhase: SavedAttemptPhase = if attemptClosed {
            .kept
        } else if hasCommittedAttempt {
            .outcome
        } else if requiresNewPlacement {
            .mustMove
        } else {
            .arranging
        }
        let snapshot = ClientSnapshot(
            scenarioName: projection.scenarioName,
            selectedRockCell: selectedRockCell,
            attemptPhase: savedPhase,
            simulation: SimulationSnapshot(simulator: simulator),
            comparisonBefore: comparisonBeforeSnapshot
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
        let restored = try snapshot.simulation.restore()
        let comparisonRestored = try snapshot.comparisonBefore?.restore()
        let rockCells = restored.state.cells.indices.filter {
            restored.state.cells[$0].rockResistance > 0
        }
        guard rockCells.count <= 1,
              rockCells.first == snapshot.selectedRockCell else {
            throw ShapeTheBendAttemptError.snapshotRockMismatch
        }
        if let comparisonRestored {
            let expectedTick: UInt64 = switch snapshot.attemptPhase {
            case .outcome, .kept:
                restored.state.tick >= Self.attemptTicks
                    ? restored.state.tick - Self.attemptTicks
                    : .max
            case .arranging, .mustMove:
                restored.state.tick
            }
            guard comparisonRestored.state.tick == expectedTick,
                  comparisonRestored.state.seed == restored.state.seed,
                  comparisonRestored.state.cells.count == restored.state.cells.count,
                  comparisonRestored.state.forcing == restored.state.forcing,
                  comparisonRestored.state.poolObjective == restored.state.poolObjective else {
                throw ShapeTheBendAttemptError.comparisonSnapshotMismatch
            }
        }
        // Both snapshots are restored and cross-validated before live state changes.
        simulator = restored
        selectedRockCell = snapshot.selectedRockCell
        comparisonBeforeSnapshot = snapshot.comparisonBefore
        requiresNewPlacement = snapshot.attemptPhase == .mustMove
        hasCommittedAttempt = snapshot.attemptPhase == .outcome
        attemptClosed = snapshot.attemptPhase == .kept
        attemptStartTick = restored.state.tick
        projection = Self.project(
            scenarioName: snapshot.scenarioName,
            simulator: restored
        )
        message = "Resumed tick \(simulator.state.tick)"
    }

    private static func project(
        scenarioName: String,
        simulator: Simulator,
        effectComparedWith previous: SimulationProjection? = nil,
        selectedRockCell: Int? = nil
    ) -> SimulationProjection {
        let diagnostics = simulator.diagnostics()
        let transfers = diagnostics.lastTick?.waterTransfers
            ?? simulator.state.lastTransfers
        let objective = simulator.state.poolObjectiveResult
        let cells = simulator.state.cells.enumerated().map { index, cell in
            CellProjection(
                id: index,
                bedElevation: cell.bedElevation,
                waterDepth: cell.waterDepth,
                suspendedSediment: cell.suspendedSediment,
                rockResistance: cell.rockResistance
            )
        }
        var rockEffect: RockEffectProjection?
        if let previous,
           let selectedRockCell,
           cells.indices.contains(selectedRockCell),
           cells[selectedRockCell].rockResistance > 0 {
            let rock = cells[selectedRockCell]
            rockEffect = RockEffectProjection(
                cell: rock.id,
                resistance: rock.rockResistance,
                elapsedTicks: simulator.state.tick - previous.tick,
                upstreamDepthChange: rock.waterDepth
                    - previous.cells[rock.id].waterDepth,
                downstreamDepthChange: cells.indices.contains(rock.id + 1)
                    ? cells[rock.id + 1].waterDepth
                        - previous.cells[rock.id + 1].waterDepth
                    : nil,
                flowPastRock: transfers.indices.contains(rock.id)
                    ? transfers[rock.id]
                    : nil
            )
        }
        return SimulationProjection(
            scenarioName: scenarioName,
            tick: simulator.state.tick,
            totalWater: simulator.state.totalWater,
            totalSediment: simulator.state.totalSediment,
            waterResidual: diagnostics.balance.waterResidual,
            sedimentResidual: diagnostics.balance.sedimentResidual,
            violations: diagnostics.violations,
            waterTransfers: transfers,
            cells: cells,
            rockEffect: rockEffect,
            poolObjective: objective.map {
                PoolObjectiveProjection(
                    targetCell: simulator.state.poolObjective!.targetCell,
                    status: $0.status,
                    progressTicks: $0.progressTicks,
                    requiredTicks: $0.requiredTicks,
                    depth: $0.depth,
                    transfer: $0.transfer,
                    calmness: $0.calmness
                )
            }
        )
    }
}
