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
    switch try CommandLineRequest.parse(arguments) {
    case .list:
        for scenario in BuiltInScenarios.all {
            print("\(scenario.name)\t\(scenario.summary)")
        }
    case let .run(request):
        let simulator = try request.scenario.run()
        let result = ScenarioResult(
            scenario: request.scenario,
            simulator: simulator
        )
        if let path = request.jsonPath {
            try write(DiagnosticExporter.json(result), to: path)
        }
        if let path = request.csvPath {
            try write(
                Data(DiagnosticExporter.cellsCSV(simulator.state).utf8),
                to: path
            )
        }
        if let path = request.snapshotPath {
            try write(
                SnapshotCodec.encode(SimulationSnapshot(simulator: simulator)),
                to: path
            )
        }
        printSummary(name: request.scenario.name, simulator: simulator)
    case let .resume(request):
        let data = try Data(contentsOf: URL(fileURLWithPath: request.snapshotPath))
        let snapshot = try SnapshotCodec.decode(data)
        var simulator = try snapshot.restore()
        simulator.step(count: request.tickCount)
        if let path = request.outputSnapshotPath {
            try write(
                SnapshotCodec.encode(SimulationSnapshot(simulator: simulator)),
                to: path
            )
        }
        printSummary(name: "resumed", simulator: simulator)
    }
} catch let error as CommandLineError {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    usage()
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(1)
}
