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
                    firstUseGuide
                    controls

                    CreekCrossSection(
                        projection: session.projection,
                        placeRock: { cell in
                            perform { try session.placeRock(cell: cell) }
                        }
                    )

                    if let effect = session.projection.rockEffect {
                        RockEffectCard(effect: effect)
                    }

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

    private var firstUseGuide: some View {
        HStack(spacing: 12) {
            Label("1. Tap a +", systemImage: "plus.circle.fill")
            Image(systemName: "arrow.right")
                .foregroundStyle(.secondary)
            Label("2. Advance", systemImage: "forward.fill")
        }
        .font(.subheadline.weight(.semibold))
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("First, tap a plus in the creek to place a rock. Second, press Advance to run fixed ticks.")
        .accessibilityIdentifier("first-use-guide")
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
                Button("Save") {
                    perform(failure: "Couldn’t save this creek.") {
                        try session.save()
                    }
                }
                .accessibilityIdentifier("save-snapshot")
                Button("Resume") {
                    perform(failure: "Couldn’t resume. Your current creek is unchanged.") {
                        try session.resume()
                    }
                }
                .disabled(!session.canResume)
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

    private func perform(
        failure: String = "That change couldn’t be applied.",
        _ action: () throws -> Void
    ) {
        do {
            try action()
        } catch {
            errorMessage = failure
        }
    }
}
