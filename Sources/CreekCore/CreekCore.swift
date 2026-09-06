/// Crick's authoritative simulation model.
///
/// Determinism guarantee:
/// - A supported Crick build, platform, initial snapshot, and ordered command
///   sequence produce exactly equal states.
/// - The core uses fixed ticks, seeded state, stable array traversal, and no
///   wall clock, file I/O, global randomness, or unordered collections.
/// - Cross-build and cross-architecture bit-identical floating-point replay is
///   not promised. Snapshots declare their schema and simulation versions.
public enum DeterminismGuarantee {
    /// Bump whenever authoritative stepping semantics change incompatibly.
    public static let compatibilityID = "crick-sim-v3"
    public static let text = "Exact replay within the same determinism compatibility ID and platform"
}

public struct Cell: Codable, Equatable, Sendable {
    public internal(set) var bedElevation: Double
    public internal(set) var waterDepth: Double
    public internal(set) var suspendedSediment: Double
    public internal(set) var rockResistance: Double

    public init(
        bedElevation: Double,
        waterDepth: Double,
        suspendedSediment: Double = 0,
        rockResistance: Double = 0
    ) {
        self.bedElevation = bedElevation
        self.waterDepth = waterDepth
        self.suspendedSediment = suspendedSediment
        self.rockResistance = rockResistance
    }
}

public struct BoundaryForcing: Codable, Equatable, Sendable {
    public internal(set) var waterPerTick: Double
    public internal(set) var sedimentPerTick: Double

    public init(waterPerTick: Double, sedimentPerTick: Double = 0) {
        self.waterPerTick = waterPerTick
        self.sedimentPerTick = sedimentPerTick
    }
}

public struct MaterialLedger: Codable, Equatable, Sendable {
    public internal(set) var initialWater: Double
    public internal(set) var waterIn: Double
    public internal(set) var waterOut: Double
    public internal(set) var initialSediment: Double
    public internal(set) var sedimentIn: Double
    public internal(set) var sedimentOut: Double
    public internal(set) var playerSedimentAdded: Double
    public internal(set) var playerSedimentRemoved: Double

    public init(initialWater: Double, initialSediment: Double) {
        self.initialWater = initialWater
        self.waterIn = 0
        self.waterOut = 0
        self.initialSediment = initialSediment
        self.sedimentIn = 0
        self.sedimentOut = 0
        self.playerSedimentAdded = 0
        self.playerSedimentRemoved = 0
    }
}

public struct PoolObjective: Codable, Equatable, Sendable {
    public let targetCell: Int
    public let minimumDepth: Double
    public let maximumTransfer: Double
    public let requiredTicks: UInt64

    public init(
        targetCell: Int,
        minimumDepth: Double,
        maximumTransfer: Double,
        requiredTicks: UInt64
    ) {
        self.targetCell = targetCell
        self.minimumDepth = minimumDepth
        self.maximumTransfer = maximumTransfer
        self.requiredTicks = requiredTicks
    }
}

public enum PoolObjectiveStatus: String, Codable, Equatable, Sendable {
    case gathering
    case deepButQuick
    case calmButShallow
    case holding
}

public struct PoolObjectiveResult: Codable, Equatable, Sendable {
    public let status: PoolObjectiveStatus
    public let progressTicks: UInt64
    public let requiredTicks: UInt64
    public let depth: Double
    public let transfer: Double
}

public struct WorldState: Codable, Equatable, Sendable {
    public static let simulationVersion = 3

    public internal(set) var tick: UInt64
    public internal(set) var seed: UInt64
    public internal(set) var cells: [Cell]
    public internal(set) var forcing: BoundaryForcing
    public internal(set) var ledger: MaterialLedger
    public internal(set) var poolObjective: PoolObjective?
    public internal(set) var poolObjectiveProgress: UInt64
    public internal(set) var lastTransfers: [Double]

    public init(
        seed: UInt64,
        cells: [Cell],
        forcing: BoundaryForcing,
        poolObjective: PoolObjective? = nil
    ) {
        precondition(cells.count >= 2, "A reach requires at least two cells")
        self.tick = 0
        self.seed = seed
        self.cells = cells
        self.forcing = forcing
        self.poolObjective = poolObjective
        self.poolObjectiveProgress = 0
        self.lastTransfers = []
        self.ledger = MaterialLedger(
            initialWater: cells.reduce(0) { $0 + $1.waterDepth },
            initialSediment: cells.reduce(0) {
                $0 + $1.bedElevation + $1.suspendedSediment
            }
        )
    }

    public var totalWater: Double {
        cells.reduce(0) { $0 + $1.waterDepth }
    }

    public var totalSediment: Double {
        cells.reduce(0) { $0 + $1.bedElevation + $1.suspendedSediment }
    }

    public var poolObjectiveResult: PoolObjectiveResult? {
        guard let objective = poolObjective,
              cells.indices.contains(objective.targetCell) else { return nil }
        let depth = cells[objective.targetCell].waterDepth
        let transfer = lastTransfers.indices.contains(objective.targetCell)
            ? lastTransfers[objective.targetCell] : 0
        let depthMet = depth >= objective.minimumDepth
        let flowMet = transfer <= objective.maximumTransfer
        let status: PoolObjectiveStatus
        if tick == 0 || lastTransfers.isEmpty {
            status = .gathering
        } else if poolObjectiveProgress >= objective.requiredTicks {
            status = .holding
        } else if depthMet && !flowMet {
            status = .deepButQuick
        } else if !depthMet && flowMet {
            status = .calmButShallow
        } else {
            status = .gathering
        }
        return PoolObjectiveResult(
            status: status,
            progressTicks: poolObjectiveProgress,
            requiredTicks: objective.requiredTicks,
            depth: depth,
            transfer: transfer
        )
    }
}

public enum WorldCommand: Codable, Equatable, Sendable {
    case setForcing(waterPerTick: Double, sedimentPerTick: Double)
    case placeRock(cell: Int, resistance: Double)
    case removeRock(cell: Int)
    case moveRock(from: Int?, to: Int, resistance: Double)
    case excavate(cell: Int, sediment: Double)
}

public struct ScheduledCommand: Codable, Equatable, Sendable {
    public var tick: UInt64
    public var command: WorldCommand

    public init(tick: UInt64, command: WorldCommand) {
        self.tick = tick
        self.command = command
    }
}

public enum CommandError: Error, Equatable, Sendable {
    case targetInPast(currentTick: UInt64, targetTick: UInt64)
    case commandInPast(currentTick: UInt64, commandTick: UInt64)
    case commandInFuture(currentTick: UInt64, commandTick: UInt64)
    case commandBeyondTarget(targetTick: UInt64, commandTick: UInt64)
    case invalidCell(Int)
    case invalidAmount
    case insufficientSediment
}

public enum StateError: Error, Equatable, Sendable {
    case invalid(violations: [String])
}

public struct BalanceReport: Codable, Equatable, Sendable {
    public var expectedWater: Double
    public var actualWater: Double
    public var waterResidual: Double
    public var expectedSediment: Double
    public var actualSediment: Double
    public var sedimentResidual: Double
}

public struct TickDiagnostics: Codable, Equatable, Sendable {
    public var tick: UInt64
    public var waterIn: Double
    public var waterOut: Double
    public var sedimentIn: Double
    public var sedimentOut: Double
    public var waterTransfers: [Double]
    public var sedimentTransfers: [Double]
    public var erosion: [Double]
    public var deposition: [Double]
}

public struct SimulationDiagnostics: Codable, Equatable, Sendable {
    public var balance: BalanceReport
    public var lastTick: TickDiagnostics?
    public var violations: [String]
}

public struct Simulator: Sendable {
    public static let fixedStepSeconds = 1.0
    public static let balanceTolerance = 1e-9

    public private(set) var state: WorldState
    public private(set) var commandLog: [ScheduledCommand]
    public private(set) var lastTickDiagnostics: TickDiagnostics?

    public init(state: WorldState, commandLog: [ScheduledCommand] = []) throws {
        self.state = state
        self.commandLog = commandLog
        self.lastTickDiagnostics = nil
        let violations = diagnostics().violations
        guard violations.isEmpty else {
            throw StateError.invalid(violations: violations)
        }
    }

    public mutating func run(
        until targetTick: UInt64,
        commands: [ScheduledCommand] = []
    ) throws {
        guard targetTick >= state.tick else {
            throw CommandError.targetInPast(
                currentTick: state.tick,
                targetTick: targetTick
            )
        }
        // A failed schedule is atomic: validate and execute against a value copy.
        var candidate = self
        try candidate.runValidated(until: targetTick, commands: commands)
        self = candidate
    }

    private mutating func runValidated(
        until targetTick: UInt64,
        commands: [ScheduledCommand]
    ) throws {
        if let command = commands.first(where: { $0.tick < state.tick }) {
            throw CommandError.commandInPast(
                currentTick: state.tick,
                commandTick: command.tick
            )
        }
        if let command = commands.first(where: { $0.tick > targetTick }) {
            throw CommandError.commandBeyondTarget(
                targetTick: targetTick,
                commandTick: command.tick
            )
        }
        let indexed = commands.enumerated().sorted {
            if $0.element.tick == $1.element.tick { return $0.offset < $1.offset }
            return $0.element.tick < $1.element.tick
        }
        var commandIndex = 0
        while state.tick < targetTick {
            while commandIndex < indexed.count,
                  indexed[commandIndex].element.tick == state.tick {
                try apply(indexed[commandIndex].element)
                commandIndex += 1
            }
            step()
        }
        while commandIndex < indexed.count,
              indexed[commandIndex].element.tick == state.tick {
            try apply(indexed[commandIndex].element)
            commandIndex += 1
        }
    }

    public mutating func apply(_ scheduled: ScheduledCommand) throws {
        guard scheduled.tick >= state.tick else {
            throw CommandError.commandInPast(
                currentTick: state.tick,
                commandTick: scheduled.tick
            )
        }
        guard scheduled.tick == state.tick else {
            throw CommandError.commandInFuture(
                currentTick: state.tick,
                commandTick: scheduled.tick
            )
        }

        switch scheduled.command {
        case let .setForcing(water, sediment):
            guard water >= 0, sediment >= 0,
                  water.isFinite, sediment.isFinite else {
                throw CommandError.invalidAmount
            }
            state.forcing = BoundaryForcing(
                waterPerTick: water,
                sedimentPerTick: sediment
            )
        case let .placeRock(cell, resistance):
            try validate(cell: cell)
            guard resistance >= 0, resistance <= 1, resistance.isFinite else {
                throw CommandError.invalidAmount
            }
            state.cells[cell].rockResistance = resistance
        case let .removeRock(cell):
            try validate(cell: cell)
            state.cells[cell].rockResistance = 0
        case let .moveRock(from, to, resistance):
            try validate(cell: to)
            if let from { try validate(cell: from) }
            guard resistance > 0, resistance <= 1, resistance.isFinite else {
                throw CommandError.invalidAmount
            }
            if let from { state.cells[from].rockResistance = 0 }
            state.cells[to].rockResistance = resistance
        case let .excavate(cell, sediment):
            try validate(cell: cell)
            guard sediment > 0, sediment.isFinite else {
                throw CommandError.invalidAmount
            }
            guard state.cells[cell].bedElevation >= sediment else {
                throw CommandError.insufficientSediment
            }
            state.cells[cell].bedElevation -= sediment
            state.ledger.playerSedimentRemoved += sediment
        }
        commandLog.append(scheduled)
    }

    public mutating func step(count: UInt64 = 1) {
        for _ in 0..<count { step() }
    }

    public func diagnostics() -> SimulationDiagnostics {
        let expectedWater = state.ledger.initialWater
            + state.ledger.waterIn - state.ledger.waterOut
        let expectedSediment = state.ledger.initialSediment
            + state.ledger.sedimentIn
            + state.ledger.playerSedimentAdded
            - state.ledger.sedimentOut
            - state.ledger.playerSedimentRemoved
        let report = BalanceReport(
            expectedWater: expectedWater,
            actualWater: state.totalWater,
            waterResidual: state.totalWater - expectedWater,
            expectedSediment: expectedSediment,
            actualSediment: state.totalSediment,
            sedimentResidual: state.totalSediment - expectedSediment
        )
        var violations: [String] = []
        if state.cells.count < 2 {
            violations.append("A reach requires at least two cells")
        }
        if let objective = state.poolObjective {
            if !state.cells.indices.contains(objective.targetCell)
                || !objective.minimumDepth.isFinite
                || !objective.maximumTransfer.isFinite
                || objective.minimumDepth < 0
                || objective.maximumTransfer < 0
                || objective.requiredTicks == 0 {
                violations.append("Pool objective is invalid")
            }
            if state.poolObjectiveProgress > objective.requiredTicks {
                violations.append("Pool objective progress is invalid")
            }
        } else if state.poolObjectiveProgress != 0 {
            violations.append("Pool progress exists without an objective")
        }
        if state.lastTransfers.count != 0
            && state.lastTransfers.count != max(0, state.cells.count - 1) {
            violations.append("Last transfer count does not match reach")
        }
        if state.lastTransfers.contains(where: { !$0.isFinite || $0 < 0 }) {
            violations.append("Last transfers are invalid")
        }
        if !state.forcing.waterPerTick.isFinite
            || !state.forcing.sedimentPerTick.isFinite
            || state.forcing.waterPerTick < 0
            || state.forcing.sedimentPerTick < 0 {
            violations.append("Boundary forcing is invalid")
        }
        if state.cells.contains(where: {
            !$0.waterDepth.isFinite || !$0.bedElevation.isFinite
                || !$0.suspendedSediment.isFinite || !$0.rockResistance.isFinite
        }) {
            violations.append("State contains a non-finite value")
        }
        if state.cells.contains(where: {
            $0.waterDepth < 0 || $0.bedElevation < 0
                || $0.suspendedSediment < 0
        }) {
            violations.append("State contains a negative inventory")
        }
        if state.cells.contains(where: {
            $0.rockResistance < 0 || $0.rockResistance > 1
        }) {
            violations.append("Rock resistance is outside zero through one")
        }
        let ledgerValues = [
            state.ledger.initialWater, state.ledger.waterIn,
            state.ledger.waterOut, state.ledger.initialSediment,
            state.ledger.sedimentIn, state.ledger.sedimentOut,
            state.ledger.playerSedimentAdded,
            state.ledger.playerSedimentRemoved,
        ]
        if ledgerValues.contains(where: { !$0.isFinite || $0 < 0 }) {
            violations.append("Material ledger is invalid")
        }
        let waterTolerance = Self.balanceTolerance
            * max(1, abs(report.expectedWater))
        let sedimentTolerance = Self.balanceTolerance
            * max(1, abs(report.expectedSediment))
        if abs(report.waterResidual) > waterTolerance {
            violations.append("Water balance residual exceeds tolerance")
        }
        if abs(report.sedimentResidual) > sedimentTolerance {
            violations.append("Sediment balance residual exceeds tolerance")
        }
        return SimulationDiagnostics(
            balance: report,
            lastTick: lastTickDiagnostics,
            violations: violations
        )
    }

    private mutating func step() {
        let before = state.cells
        let count = before.count
        var waterTransfers = Array(repeating: 0.0, count: count - 1)
        var sedimentTransfers = Array(repeating: 0.0, count: count - 1)
        var erosion = Array(repeating: 0.0, count: count)
        var deposition = Array(repeating: 0.0, count: count)

        state.cells[0].waterDepth += state.forcing.waterPerTick
        state.cells[0].suspendedSediment += state.forcing.sedimentPerTick
        state.ledger.waterIn += state.forcing.waterPerTick
        state.ledger.sedimentIn += state.forcing.sedimentPerTick

        for index in 0..<(count - 1) {
            let surface = before[index].bedElevation + before[index].waterDepth
            let downstreamSurface = before[index + 1].bedElevation
                + before[index + 1].waterDepth
            let head = max(0, surface - downstreamSurface)
            let conductivity = 0.22 * (1 - before[index].rockResistance)
            waterTransfers[index] = min(before[index].waterDepth, head * conductivity)
        }

        for index in 0..<(count - 1) {
            let transfer = waterTransfers[index]
            state.cells[index].waterDepth -= transfer
            state.cells[index + 1].waterDepth += transfer

            let concentration = before[index].waterDepth > 0
                ? before[index].suspendedSediment / before[index].waterDepth
                : 0
            let transported = min(
                before[index].suspendedSediment,
                transfer * concentration
            )
            sedimentTransfers[index] = transported
            state.cells[index].suspendedSediment -= transported
            state.cells[index + 1].suspendedSediment += transported
        }

        for index in 0..<count {
            let localFlow: Double
            if index < count - 1 {
                localFlow = waterTransfers[index]
            } else {
                localFlow = waterTransfers.last ?? 0
            }
            let capacity = localFlow * 0.08
            let suspended = state.cells[index].suspendedSediment
            if suspended > capacity {
                let amount = min(suspended - capacity, 0.01)
                deposition[index] = amount
                state.cells[index].suspendedSediment -= amount
                state.cells[index].bedElevation += amount
            } else if suspended < capacity {
                let amount = min(
                    capacity - suspended,
                    state.cells[index].bedElevation,
                    0.004
                )
                erosion[index] = amount
                state.cells[index].bedElevation -= amount
                state.cells[index].suspendedSediment += amount
            }
        }

        let outletCapacity = max(0, state.cells[count - 1].waterDepth * 0.18)
        let waterOut = min(state.cells[count - 1].waterDepth, outletCapacity)
        let outletConcentration = state.cells[count - 1].waterDepth > 0
            ? state.cells[count - 1].suspendedSediment
                / state.cells[count - 1].waterDepth
            : 0
        let sedimentOut = min(
            state.cells[count - 1].suspendedSediment,
            waterOut * outletConcentration
        )
        state.cells[count - 1].waterDepth -= waterOut
        state.cells[count - 1].suspendedSediment -= sedimentOut
        state.ledger.waterOut += waterOut
        state.ledger.sedimentOut += sedimentOut
        state.lastTransfers = waterTransfers
        updatePoolObjective()
        state.tick += 1
        lastTickDiagnostics = TickDiagnostics(
            tick: state.tick,
            waterIn: state.forcing.waterPerTick,
            waterOut: waterOut,
            sedimentIn: state.forcing.sedimentPerTick,
            sedimentOut: sedimentOut,
            waterTransfers: waterTransfers,
            sedimentTransfers: sedimentTransfers,
            erosion: erosion,
            deposition: deposition
        )
    }

    private mutating func updatePoolObjective() {
        guard let objective = state.poolObjective,
              state.cells.indices.contains(objective.targetCell) else { return }
        let depth = state.cells[objective.targetCell].waterDepth
        let transfer = state.lastTransfers.indices.contains(objective.targetCell)
            ? state.lastTransfers[objective.targetCell] : 0
        if depth >= objective.minimumDepth
            && transfer <= objective.maximumTransfer {
            state.poolObjectiveProgress = min(
                objective.requiredTicks,
                state.poolObjectiveProgress + 1
            )
        } else {
            state.poolObjectiveProgress = 0
        }
    }

    private func validate(cell: Int) throws {
        guard state.cells.indices.contains(cell) else {
            throw CommandError.invalidCell(cell)
        }
    }
}
