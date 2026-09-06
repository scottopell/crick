import CreekCore
import CreekRunner
import Foundation
import Testing

@Test("Same initial state and commands reproduce exact state")
func exactReplay() throws {
    let first = try BuiltInScenarios.rock.run()
    let replay = try BuiltInScenarios.rock.run()

    #expect(first.state == replay.state)
    #expect(first.commandLog == replay.commandLog)
    #expect(first.diagnostics() == replay.diagnostics())
}

@Test("Fixed-step batching is equivalent to individual ticks")
func fixedStepPartitioning() throws {
    var batched = try Simulator(state: BuiltInScenarios.baseline.initialState)
    var individual = try Simulator(state: BuiltInScenarios.baseline.initialState)

    batched.step(count: 50)
    for _ in 0..<50 { individual.step() }

    #expect(batched.state == individual.state)
    #expect(batched.diagnostics() == individual.diagnostics())
}

@Test("Commands execute at their declared tick in stable order")
func tickIndexedCommands() throws {
    var simulator = try Simulator(state: BuiltInScenarios.baseline.initialState)
    let commands = [
        ScheduledCommand(tick: 5, command: .placeRock(cell: 2, resistance: 0.3)),
        ScheduledCommand(tick: 5, command: .placeRock(cell: 2, resistance: 0.8)),
    ]

    try simulator.run(until: 6, commands: commands)

    #expect(simulator.state.cells[2].rockResistance == 0.8)
    #expect(simulator.commandLog == commands)
}

@Test("Commands reject invalid time, cells, and quantities")
func invalidCommands() throws {
    var simulator = try Simulator(state: BuiltInScenarios.baseline.initialState)

    #expect(throws: CommandError.commandInFuture(currentTick: 0, commandTick: 1)) {
        try simulator.apply(ScheduledCommand(tick: 1, command: .removeRock(cell: 0)))
    }
    #expect(throws: CommandError.invalidCell(99)) {
        try simulator.apply(ScheduledCommand(tick: 0, command: .removeRock(cell: 99)))
    }
    #expect(throws: CommandError.invalidAmount) {
        try simulator.apply(ScheduledCommand(
            tick: 0,
            command: .setForcing(waterPerTick: -.infinity, sedimentPerTick: 0)
        ))
    }
    simulator.step()
    #expect(throws: CommandError.commandInPast(currentTick: 1, commandTick: 0)) {
        try simulator.apply(ScheduledCommand(tick: 0, command: .removeRock(cell: 0)))
    }
}

@Test("A run rejects commands beyond its target tick")
func commandBeyondTarget() throws {
    var simulator = try Simulator(state: BuiltInScenarios.baseline.initialState)

    #expect(throws: CommandError.commandBeyondTarget(
        targetTick: 5,
        commandTick: 6
    )) {
        try simulator.run(
            until: 5,
            commands: [ScheduledCommand(tick: 6, command: .removeRock(cell: 0))]
        )
    }
    #expect(simulator.state.tick == 0)
    #expect(simulator.commandLog.isEmpty)
}

@Test("Past targets and failing schedules do not mutate state")
func atomicScheduleFailure() throws {
    var simulator = try Simulator(state: BuiltInScenarios.baseline.initialState)
    simulator.step(count: 4)
    let before = simulator

    #expect(throws: CommandError.targetInPast(currentTick: 4, targetTick: 3)) {
        try simulator.run(until: 3)
    }
    #expect(simulator.state == before.state)

    #expect(throws: CommandError.insufficientSediment) {
        try simulator.run(until: 8, commands: [
            ScheduledCommand(tick: 5, command: .placeRock(cell: 2, resistance: 0.5)),
            ScheduledCommand(tick: 7, command: .excavate(cell: 1, sediment: 100)),
        ])
    }
    #expect(simulator.state == before.state)
    #expect(simulator.commandLog == before.commandLog)
}

@Test("Initial invalid state is rejected before stepping")
func invalidInitialState() {
    let invalid = WorldState(
        seed: 1,
        cells: [
            Cell(bedElevation: 1, waterDepth: 0, rockResistance: 2),
            Cell(bedElevation: 0, waterDepth: 0),
        ],
        forcing: BoundaryForcing(waterPerTick: .infinity)
    )

    #expect(throws: StateError.self) {
        _ = try Simulator(state: invalid)
    }
}

@Test("Water and sediment account for boundaries and player excavation")
func conservation() throws {
    var simulator = try BuiltInScenarios.flood.run()
    try simulator.apply(ScheduledCommand(
        tick: simulator.state.tick,
        command: .excavate(cell: 1, sediment: 0.02)
    ))
    simulator.step(count: 100)
    let diagnostics = simulator.diagnostics()

    #expect(abs(diagnostics.balance.waterResidual) < Simulator.balanceTolerance)
    #expect(abs(diagnostics.balance.sedimentResidual) < Simulator.balanceTolerance)
    #expect(diagnostics.violations.isEmpty)
    #expect(simulator.state.cells.allSatisfy {
        $0.waterDepth >= 0 && $0.bedElevation >= 0
            && $0.suspendedSediment >= 0
    })
}

@Test("Conservation remains bounded over a long accelerated run")
func longRunConservation() throws {
    var simulator = try Simulator(state: BuiltInScenarios.baseline.initialState)
    simulator.step(count: 10_000)
    let diagnostics = simulator.diagnostics()

    #expect(abs(diagnostics.balance.waterResidual) < Simulator.balanceTolerance)
    #expect(abs(diagnostics.balance.sedimentResidual) < Simulator.balanceTolerance)
    #expect(diagnostics.violations.isEmpty)
}

@Test("Versioned snapshot round-trips exactly")
func snapshotRoundTrip() throws {
    let simulator = try BuiltInScenarios.rock.run()
    let snapshot = SimulationSnapshot(simulator: simulator)
    let data = try SnapshotCodec.encode(snapshot)
    let decoded = try SnapshotCodec.decode(data)
    let restored = try decoded.restore()

    #expect(decoded == snapshot)
    #expect(restored.state == simulator.state)
    #expect(restored.commandLog == simulator.commandLog)
}

@Test("Unsupported snapshots are rejected")
func snapshotVersionRejection() throws {
    let simulator = try BuiltInScenarios.baseline.run()
    var snapshot = SimulationSnapshot(simulator: simulator)
    snapshot.schemaVersion += 1

    #expect(throws: SnapshotError.unsupportedSchema(found: 3)) {
        _ = try snapshot.restore()
    }
}

@Test("Snapshot restore rejects corrupt authoritative state")
func corruptSnapshotRejection() throws {
    let simulator = try BuiltInScenarios.baseline.run()
    var snapshot = SimulationSnapshot(simulator: simulator)
    snapshot.state = WorldState(
        seed: 42,
        cells: [
            Cell(bedElevation: 1, waterDepth: -1),
            Cell(bedElevation: 0, waterDepth: 0),
        ],
        forcing: BoundaryForcing(waterPerTick: 0)
    )

    #expect(throws: SnapshotError.self) {
        _ = try snapshot.restore()
    }
}

@Test("Save and resume equals uninterrupted advancement")
func saveResumeEquivalence() throws {
    var uninterrupted = try Simulator(state: BuiltInScenarios.baseline.initialState)
    uninterrupted.step(count: 120)

    var firstSession = try Simulator(state: BuiltInScenarios.baseline.initialState)
    firstSession.step(count: 45)
    let data = try SnapshotCodec.encode(SimulationSnapshot(simulator: firstSession))
    var resumed = try SnapshotCodec.decode(data).restore()
    resumed.step(count: 75)

    #expect(resumed.state == uninterrupted.state)
    #expect(resumed.diagnostics() == uninterrupted.diagnostics())
}

@Test("Repeated serialization boundaries equal uninterrupted advancement")
func repeatedResumeEquivalence() throws {
    var uninterrupted = try Simulator(state: BuiltInScenarios.baseline.initialState)
    uninterrupted.step(count: 120)

    var resumed = try Simulator(state: BuiltInScenarios.baseline.initialState)
    for _ in 0..<3 {
        resumed.step(count: 40)
        let data = try SnapshotCodec.encode(SimulationSnapshot(simulator: resumed))
        resumed = try SnapshotCodec.decode(data).restore()
    }

    #expect(resumed.state == uninterrupted.state)
}

@Test("Snapshot rejects incompatible determinism contract")
func incompatibleDeterminismContract() throws {
    let simulator = try BuiltInScenarios.baseline.run()
    var snapshot = SimulationSnapshot(simulator: simulator)
    snapshot.determinismCompatibilityID = "other-build"

    #expect(throws: SnapshotError.self) {
        _ = try snapshot.restore()
    }
}

@Test("Dry and extreme-flow states remain finite and conserved")
func dryAndExtremeFlow() throws {
    let dry = WorldState(
        seed: 7,
        cells: [
            Cell(bedElevation: 1, waterDepth: 0),
            Cell(bedElevation: 0, waterDepth: 0),
        ],
        forcing: BoundaryForcing(waterPerTick: 0)
    )
    var drySimulator = try Simulator(state: dry)
    drySimulator.step(count: 1_000)
    #expect(drySimulator.diagnostics().violations.isEmpty)

    var flood = try Simulator(state: BuiltInScenarios.baseline.initialState)
    try flood.apply(ScheduledCommand(
        tick: 0,
        command: .setForcing(waterPerTick: 1_000_000, sedimentPerTick: 10_000)
    ))
    flood.step(count: 1_000)
    #expect(flood.diagnostics().violations.isEmpty)
}

@Test("CLI parser rejects ambiguous and malformed invocations")
func strictCommandLine() throws {
    #expect(throws: CommandLineError.duplicateOption("--json")) {
        _ = try CommandLineRequest.parse([
            "run", "baseline", "--json", "a", "--json", "b",
        ])
    }
    #expect(throws: CommandLineError.missingOptionValue("--json")) {
        _ = try CommandLineRequest.parse(["run", "baseline", "--json"])
    }
    #expect(throws: CommandLineError.unknownOption("extra")) {
        _ = try CommandLineRequest.parse(["run", "baseline", "extra"])
    }
    #expect(throws: CommandLineError.invalidTickCount("-1")) {
        _ = try CommandLineRequest.parse(["resume", "save.json", "--ticks", "-1"])
    }
    #expect(throws: CommandLineError.self) {
        _ = try CommandLineRequest.parse([
            "run", "baseline", "--json", "out", "--csv", "./out",
        ])
    }
    let parsed = try CommandLineRequest.parse([
        "run", "rock", "--csv", "cells.csv", "--json", "result.json",
    ])
    guard case let .run(request) = parsed else {
        Issue.record("Expected a run request")
        return
    }
    #expect(request.scenario.name == "rock")
    #expect(request.csvPath == "cells.csv")
    #expect(request.jsonPath == "result.json")
}

@Test("Shape the Bend is achievable by a stone at the bend")
func poolObjectiveSuccess() throws {
    var simulator = try Simulator(state: BuiltInScenarios.shapeTheBend.initialState)
    try simulator.apply(ScheduledCommand(
        tick: 0,
        command: .moveRock(from: nil, to: 2, resistance: 0.8)
    ))
    simulator.step(count: 40)

    #expect(simulator.state.poolObjectiveResult?.status == .holding)
    #expect(simulator.state.poolObjectiveResult?.progressTicks == 5)
    #expect(simulator.diagnostics().violations.isEmpty)
}

@Test("The pool does not succeed without the intervention")
func poolObjectiveRequiresIntervention() throws {
    var simulator = try Simulator(state: BuiltInScenarios.shapeTheBend.initialState)
    simulator.step(count: 40)

    #expect(simulator.state.poolObjectiveResult?.status != .holding)
}

@Test("Moving the stone is atomic and survives snapshot recovery")
func moveRockAndRecover() throws {
    var simulator = try Simulator(state: BuiltInScenarios.shapeTheBend.initialState)
    try simulator.apply(ScheduledCommand(
        tick: 0,
        command: .moveRock(from: nil, to: 1, resistance: 0.8)
    ))
    try simulator.apply(ScheduledCommand(
        tick: 0,
        command: .moveRock(from: 1, to: 2, resistance: 0.8)
    ))
    simulator.step(count: 20)
    let restored = try SnapshotCodec.decode(
        SnapshotCodec.encode(SimulationSnapshot(simulator: simulator))
    ).restore()

    #expect(restored.state.cells[1].rockResistance == 0)
    #expect(restored.state.cells[2].rockResistance == 0.8)
    #expect(restored.state.poolObjectiveResult == simulator.state.poolObjectiveResult)
}

@Test("A failed stone move preserves its prior authoritative location")
func failedMoveRockIsAtomic() throws {
    var simulator = try Simulator(state: BuiltInScenarios.shapeTheBend.initialState)
    try simulator.apply(ScheduledCommand(
        tick: 0,
        command: .moveRock(from: nil, to: 1, resistance: 0.8)
    ))
    let before = simulator.state

    #expect(throws: CommandError.invalidCell(99)) {
        try simulator.apply(ScheduledCommand(
            tick: 0,
            command: .moveRock(from: 1, to: 99, resistance: 0.8)
        ))
    }
    #expect(simulator.state == before)
}

@Test("Pool objective has viable choices and readable near misses")
func poolPlacementOutcomes() throws {
    var statuses: [PoolObjectiveStatus] = []
    for cell in 0..<6 {
        var simulator = try Simulator(state: BuiltInScenarios.shapeTheBend.initialState)
        try simulator.apply(ScheduledCommand(
            tick: 0,
            command: .moveRock(from: nil, to: cell, resistance: 0.8)
        ))
        simulator.step(count: 40)
        statuses.append(simulator.state.poolObjectiveResult!.status)
    }

    #expect(statuses == [
        .deepButQuick,
        .calmButShallow,
        .holding,
        .holding,
        .deepButQuick,
        .deepButQuick,
    ])
}

@Test("An obstruction creates measurable upstream backwater")
func rockCreatesBackwater() throws {
    let baseline = try BuiltInScenarios.baseline.run()
    let obstructed = try BuiltInScenarios.rock.run()

    #expect(obstructed.state.cells[2].rockResistance == 0.8)
    #expect(obstructed.state.cells[2].waterDepth > baseline.state.cells[2].waterDepth)
    #expect(obstructed.state.cells[3].waterDepth < baseline.state.cells[3].waterDepth)
}

@Test("Higher flow causes persistent, conserved bed change")
func floodChangesBed() throws {
    let baseline = try BuiltInScenarios.baseline.run()
    let flood = try BuiltInScenarios.flood.run()
    let baselineBed = baseline.state.cells.map(\.bedElevation)
    let floodBed = flood.state.cells.map(\.bedElevation)

    #expect(floodBed != baselineBed)
    #expect(flood.state.forcing == BoundaryForcing(
        waterPerTick: 0.05,
        sedimentPerTick: 0.001
    ))
    #expect(flood.diagnostics().violations.isEmpty)
}

@Test("Diagnostics export stable structured JSON and tabular cells")
func diagnosticExports() throws {
    let scenario = BuiltInScenarios.rock
    let simulator = try scenario.run()
    let result = ScenarioResult(scenario: scenario, simulator: simulator)
    let json = try DiagnosticExporter.json(result)
    let decoded = try JSONDecoder().decode(ScenarioResult.self, from: json)
    let csv = DiagnosticExporter.cellsCSV(simulator.state)

    #expect(decoded == result)
    #expect(csv.hasPrefix("cell,bed_elevation,water_depth"))
    #expect(csv.split(separator: "\n").count == simulator.state.cells.count + 1)
}
