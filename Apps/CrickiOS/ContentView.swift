import CreekRunner
import SwiftUI

struct ContentView: View {
    @State private var session: SimulationSession
    @State private var errorMessage: String?

    init(session: SimulationSession) {
        _session = State(initialValue: session)
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Authoritative state") {
                    LabeledContent("Scenario", value: session.projection.scenarioName)
                    LabeledContent("Tick") {
                        Text("\(session.projection.tick)")
                            .accessibilityIdentifier("tick-value")
                    }
                    LabeledContent("Water", value: session.projection.totalWater.formatted(.number.precision(.fractionLength(4))))
                    LabeledContent("Sediment", value: session.projection.totalSediment.formatted(.number.precision(.fractionLength(4))))
                }

                Section("Explicit controls") {
                    Button("Advance 1 Tick") { session.advance(ticks: 1) }
                        .accessibilityIdentifier("advance-one")
                    Button("Advance 10 Ticks") { session.advance(ticks: 10) }
                    Button("Place Rock in Cell 2") { perform { try session.placeRock() } }
                        .accessibilityIdentifier("place-rock")
                    Button("Load Baseline") { perform { try session.load(BuiltInScenarios.baseline) } }
                    Button("Load Rock Scenario") { perform { try session.load(BuiltInScenarios.rock) } }
                }

                Section("Snapshot") {
                    Button("Save") { perform { try session.save() } }
                        .accessibilityIdentifier("save-snapshot")
                    Button("Resume") { perform { try session.resume() } }
                        .accessibilityIdentifier("resume-snapshot")
                    Text(session.message)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("session-message")
                }

                Section("Diagnostics") {
                    LabeledContent("Water residual", value: session.projection.waterResidual.formatted())
                    LabeledContent("Sediment residual", value: session.projection.sedimentResidual.formatted())
                    LabeledContent("Violations", value: "\(session.projection.violations.count)")
                        .accessibilityIdentifier("violation-count")
                }

                Section("Cells") {
                    ForEach(session.projection.cells) { cell in
                        VStack(alignment: .leading) {
                            Text("Cell \(cell.id)").font(.headline)
                            Text("depth \(cell.waterDepth.formatted(.number.precision(.fractionLength(3)))) · bed \(cell.bedElevation.formatted(.number.precision(.fractionLength(3))))")
                            Text("sediment \(cell.suspendedSediment.formatted(.number.precision(.fractionLength(4)))) · rock \(cell.rockResistance.formatted(.number.precision(.fractionLength(1))))")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Crick Lab")
            .alert("Error", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func perform(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            errorMessage = String(describing: error)
        }
    }
}
