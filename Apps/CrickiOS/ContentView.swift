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
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header

                    CreekCrossSection(
                        projection: session.projection,
                        placeRock: { cell in
                            perform { try session.placeRock(cell: cell) }
                        }
                    )

                    if let effect = session.projection.rockEffect {
                        RockEffectCard(effect: effect)
                    }

                    controls
                    diagnostics
                    snapshotControls
                }
                .padding()
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(session.projection.scenarioName, systemImage: "leaf.fill")
                Spacer()
                Text("Tick \(session.projection.tick)")
                    .font(.headline.monospacedDigit())
                    .accessibilityIdentifier("tick-value")
            }
            HStack {
                metric("Water", session.projection.totalWater)
                metric("Sediment", session.projection.totalSediment)
            }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Fixed-step controls").font(.headline)
            HStack {
                Button("Advance 1") { session.advance(ticks: 1) }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("advance-one")
                Button("Advance 10") { session.advance(ticks: 10) }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("advance-ten")
                Spacer()
                Menu("Scenario") {
                    Button("Baseline") {
                        perform { try session.load(BuiltInScenarios.baseline) }
                    }
                    Button("Rock fixture") {
                        perform { try session.load(BuiltInScenarios.rock) }
                    }
                    Button("Flood fixture") {
                        perform { try session.load(BuiltInScenarios.flood) }
                    }
                }
            }
            Text("Nothing advances unless you press an Advance button.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var diagnostics: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Diagnostics").font(.headline)
            LabeledContent("Water residual", value: session.projection.waterResidual.formatted())
            LabeledContent("Sediment residual", value: session.projection.sedimentResidual.formatted())
            LabeledContent("Violations", value: "\(session.projection.violations.count)")
                .accessibilityIdentifier("violation-count")
        }
    }

    private var snapshotControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Snapshot").font(.headline)
            HStack {
                Button("Save") { perform { try session.save() } }
                    .accessibilityIdentifier("save-snapshot")
                Button("Resume") { perform { try session.resume() } }
                    .accessibilityIdentifier("resume-snapshot")
            }
            .buttonStyle(.bordered)
            Text(session.message)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("session-message")
        }
    }

    private func metric(_ name: String, _ value: Double) -> some View {
        VStack(alignment: .leading) {
            Text(name).font(.caption).foregroundStyle(.secondary)
            Text(value.formatted(.number.precision(.fractionLength(4))))
                .font(.body.monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func perform(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            errorMessage = String(describing: error)
        }
    }
}
