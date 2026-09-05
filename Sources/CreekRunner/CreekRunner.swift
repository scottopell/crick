import CreekCore
import Foundation

public enum SnapshotError: Error, Equatable, Sendable {
    case unsupportedSchema(found: Int)
    case unsupportedSimulation(found: Int)
    case invalidState(violations: [String])
}

public struct SimulationSnapshot: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var simulationVersion: Int
    public var determinismCompatibilityID: String
    public var state: WorldState
    public var commandLog: [ScheduledCommand]

    public init(simulator: Simulator) {
        self.schemaVersion = Self.currentSchemaVersion
        self.simulationVersion = WorldState.simulationVersion
        self.determinismCompatibilityID = DeterminismGuarantee.compatibilityID
        self.state = simulator.state
        self.commandLog = simulator.commandLog
    }

    public func restore() throws -> Simulator {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw SnapshotError.unsupportedSchema(found: schemaVersion)
        }
        guard simulationVersion == WorldState.simulationVersion,
              determinismCompatibilityID == DeterminismGuarantee.compatibilityID else {
            throw SnapshotError.unsupportedSimulation(found: simulationVersion)
        }
        do {
            return try Simulator(state: state, commandLog: commandLog)
        } catch let StateError.invalid(violations) {
            throw SnapshotError.invalidState(violations: violations)
        }
    }
}

public enum SnapshotCodec {
    public static func encode(_ snapshot: SimulationSnapshot) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(snapshot)
    }

    public static func decode(_ data: Data) throws -> SimulationSnapshot {
        try JSONDecoder().decode(SimulationSnapshot.self, from: data)
    }
}

public struct ScenarioDefinition: Codable, Equatable, Sendable {
    public var name: String
    public var summary: String
    public var initialState: WorldState
    public var commands: [ScheduledCommand]
    public var endTick: UInt64

    public init(
        name: String,
        summary: String,
        initialState: WorldState,
        commands: [ScheduledCommand],
        endTick: UInt64
    ) {
        self.name = name
        self.summary = summary
        self.initialState = initialState
        self.commands = commands
        self.endTick = endTick
    }

    public func run() throws -> Simulator {
        var simulator = try Simulator(state: initialState)
        try simulator.run(until: endTick, commands: commands)
        return simulator
    }
}

public enum BuiltInScenarios {
    public static let baseline = ScenarioDefinition(
        name: "baseline",
        summary: "Ordinary flow through an unobstructed sloping reach",
        initialState: ordinaryReach(seed: 42),
        commands: [],
        endTick: 80
    )

    public static let rock = ScenarioDefinition(
        name: "rock",
        summary: "A resistant rock placed at tick 10 backs up upstream water",
        initialState: ordinaryReach(seed: 42),
        commands: [
            ScheduledCommand(
                tick: 10,
                command: .placeRock(cell: 2, resistance: 0.8)
            ),
        ],
        endTick: 80
    )

    public static let flood = ScenarioDefinition(
        name: "flood",
        summary: "A bounded high-flow pulse leaves persistent bed change",
        initialState: ordinaryReach(seed: 42),
        commands: [
            ScheduledCommand(
                tick: 20,
                command: .setForcing(waterPerTick: 0.22, sedimentPerTick: 0.006)
            ),
            ScheduledCommand(
                tick: 40,
                command: .setForcing(waterPerTick: 0.05, sedimentPerTick: 0.001)
            ),
        ],
        endTick: 80
    )

    public static let all = [baseline, rock, flood]

    public static func named(_ name: String) -> ScenarioDefinition? {
        all.first { $0.name == name }
    }

    private static func ordinaryReach(seed: UInt64) -> WorldState {
        WorldState(
            seed: seed,
            cells: [
                Cell(bedElevation: 1.00, waterDepth: 0.24),
                Cell(bedElevation: 0.94, waterDepth: 0.21),
                Cell(bedElevation: 0.88, waterDepth: 0.19),
                Cell(bedElevation: 0.81, waterDepth: 0.17),
                Cell(bedElevation: 0.74, waterDepth: 0.15),
                Cell(bedElevation: 0.66, waterDepth: 0.13),
            ],
            forcing: BoundaryForcing(
                waterPerTick: 0.05,
                sedimentPerTick: 0.001
            )
        )
    }
}

public struct ScenarioResult: Codable, Equatable, Sendable {
    public var scenario: ScenarioDefinition
    public var determinismGuarantee: String
    public var determinismCompatibilityID: String
    public var fixedStepSeconds: Double
    public var state: WorldState
    public var diagnostics: SimulationDiagnostics

    public init(scenario: ScenarioDefinition, simulator: Simulator) {
        self.scenario = scenario
        self.determinismGuarantee = DeterminismGuarantee.text
        self.determinismCompatibilityID = DeterminismGuarantee.compatibilityID
        self.fixedStepSeconds = Simulator.fixedStepSeconds
        self.state = simulator.state
        self.diagnostics = simulator.diagnostics()
    }
}

public enum DiagnosticExporter {
    public static func json(_ result: ScenarioResult) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(result)
    }

    public static func cellsCSV(_ state: WorldState) -> String {
        var rows = [
            "cell,bed_elevation,water_depth,suspended_sediment,rock_resistance",
        ]
        for (index, cell) in state.cells.enumerated() {
            rows.append([
                String(index),
                decimal(cell.bedElevation),
                decimal(cell.waterDepth),
                decimal(cell.suspendedSediment),
                decimal(cell.rockResistance),
            ].joined(separator: ","))
        }
        return rows.joined(separator: "\n") + "\n"
    }

    private static func decimal(_ value: Double) -> String {
        String(format: "%.12g", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}
