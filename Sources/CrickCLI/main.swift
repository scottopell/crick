import CreekCore
import CreekRunner
import Foundation

func usage() -> Never {
    FileHandle.standardError.write(Data("""
    Usage:
      crick list
      crick run <baseline|rock|flood> [--json PATH] [--csv PATH] [--snapshot PATH]
      crick resume SNAPSHOT --ticks COUNT [--snapshot PATH]

    """.utf8))
    exit(2)
}

func value(after option: String, in arguments: [String]) -> String? {
    guard let index = arguments.firstIndex(of: option),
          arguments.indices.contains(index + 1) else { return nil }
    return arguments[index + 1]
}

func write(_ data: Data, to path: String) throws {
    try data.write(to: URL(fileURLWithPath: path), options: .atomic)
}

func printSummary(name: String, simulator: Simulator) {
    let diagnostics = simulator.diagnostics()
    print("scenario=\(name)")
    print("tick=\(simulator.state.tick)")
    print("water=\(simulator.state.totalWater)")
    print("sediment=\(simulator.state.totalSediment)")
    print("water_residual=\(diagnostics.balance.waterResidual)")
    print("sediment_residual=\(diagnostics.balance.sedimentResidual)")
    print("violations=\(diagnostics.violations.count)")
}

let arguments = Array(CommandLine.arguments.dropFirst())
do {
    guard let command = arguments.first else { usage() }
    switch command {
    case "list":
        for scenario in BuiltInScenarios.all {
            print("\(scenario.name)\t\(scenario.summary)")
        }
    case "run":
        guard arguments.count >= 2,
              let scenario = BuiltInScenarios.named(arguments[1]) else { usage() }
        let simulator = try scenario.run()
        let result = ScenarioResult(scenario: scenario, simulator: simulator)
        if let path = value(after: "--json", in: arguments) {
            try write(DiagnosticExporter.json(result), to: path)
        }
        if let path = value(after: "--csv", in: arguments) {
            try write(Data(DiagnosticExporter.cellsCSV(simulator.state).utf8), to: path)
        }
        if let path = value(after: "--snapshot", in: arguments) {
            try write(
                SnapshotCodec.encode(SimulationSnapshot(simulator: simulator)),
                to: path
            )
        }
        printSummary(name: scenario.name, simulator: simulator)
    case "resume":
        guard arguments.count >= 2,
              let tickText = value(after: "--ticks", in: arguments),
              let tickCount = UInt64(tickText) else { usage() }
        let data = try Data(contentsOf: URL(fileURLWithPath: arguments[1]))
        let snapshot = try SnapshotCodec.decode(data)
        var simulator = try snapshot.restore()
        simulator.step(count: tickCount)
        if let path = value(after: "--snapshot", in: arguments) {
            try write(
                SnapshotCodec.encode(SimulationSnapshot(simulator: simulator)),
                to: path
            )
        }
        printSummary(name: "resumed", simulator: simulator)
    default:
        usage()
    }
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(1)
}
