import CreekRunner
import SwiftUI

struct ContentView: View {
    @State private var session: SimulationSession
    @State private var errorMessage: String?
    @State private var showFieldNotes = false

    init(session: SimulationSession) {
        _session = State(initialValue: session)
    }

    var body: some View {
        ZStack {
            Color(red: 0.055, green: 0.085, blue: 0.06)
                .ignoresSafeArea()
            VStack(spacing: 0) {
                header
                CreekSceneView(
                    projection: session.projection,
                    onPlaceStone: { cell in
                        perform { try session.placeRock(cell: cell) }
                    }
                )
                .accessibilityIdentifier("creek-scene")
                .accessibilityLabel("Creek bend from upstream left to downstream right. Drag the bank stone into the water.")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                actionBar
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showFieldNotes) {
            FieldNotesView(session: session)
        }
        .alert("The creek is unchanged", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .sensoryFeedback(
            .success,
            trigger: session.projection.poolObjective?.status == .holding
        )
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("SHAPE THE BEND")
                        .font(.caption.weight(.bold))
                        .tracking(1.4)
                        .foregroundStyle(.mint)
                    Text("Make a calm pool at the bend")
                        .font(.title2.weight(.semibold))
                }
                Spacer()
                Button {
                    showFieldNotes = true
                } label: {
                    Image(systemName: "ellipsis.circle.fill")
                        .font(.title2)
                }
                .accessibilityLabel("Open field notes")
                .accessibilityIdentifier("field-notes")
            }
            Text(objectiveMessage)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.72))
                .accessibilityIdentifier("objective-message")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.black.opacity(0.24))
    }

    private var actionBar: some View {
        VStack(spacing: 9) {
            if session.projection.cells.allSatisfy({ $0.rockResistance == 0 }) {
                Label("Drag the bank stone into the creek", systemImage: "hand.draw.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.82))
                    .accessibilityIdentifier("placement-prompt")
            } else {
                Text("The stone is set. Watch what the water does.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.76))
            }
            HStack {
                Text(session.projection.cells.allSatisfy({ $0.rockResistance == 0 })
                    ? "Lift the stone from the lower bank." : "Drag the stone again to try another place.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.58))
                Spacer()
                placementMenu
            }
            Button {
                session.advance(ticks: 20)
            } label: {
                Label("Let the water work", systemImage: "water.waves")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(.cyan.opacity(0.78))
            .accessibilityIdentifier("let-water-work")
            .disabled(session.projection.cells.allSatisfy { $0.rockResistance == 0 })
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(.ultraThinMaterial)
    }

    private var placementMenu: some View {
        Menu("Choose a spot") {
            ForEach(0..<session.projection.cells.count, id: \.self) { cell in
                Button(placementName(cell)) {
                    perform { try session.placeRock(cell: cell) }
                }
                .accessibilityIdentifier("place-stone-\(cell)")
            }
        }
        .font(.caption.weight(.semibold))
        .accessibilityHint("Alternative to dragging the stone")
        .accessibilityIdentifier("choose-stone-position")
    }

    private func placementName(_ cell: Int) -> String {
        switch cell {
        case 0: "Upstream entrance"
        case 1: "Above the bend"
        case 2: "Inside the bend"
        case 3: "Below the bend"
        case 4: "Lower run"
        default: "Downstream exit"
        }
    }

    private var objectiveMessage: String {
        guard let objective = session.projection.poolObjective else {
            return "Read the current, place one stone, and observe."
        }
        switch objective.status {
        case .gathering:
            return "Find a place where water can gather and slow."
        case .deepButQuick:
            return "A deeper pocket is forming, but the current is still quick."
        case .calmButShallow:
            return "The current softened, but the pool needs more depth."
        case .holding:
            return "A calm pool is holding."
        }
    }

    private func perform(_ action: () throws -> Void) {
        do { try action() } catch {
            errorMessage = "That stone could not be placed."
        }
    }
}

private struct FieldNotesView: View {
    let session: SimulationSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Creek") {
                    LabeledContent("Fixed ticks") {
                        Text("\(session.projection.tick)")
                            .accessibilityIdentifier("authoritative-tick")
                    }
                    LabeledContent("Water", value: session.projection.totalWater.formatted())
                    LabeledContent("Sediment", value: session.projection.totalSediment.formatted())
                }
                Section("Conservation") {
                    LabeledContent("Water residual", value: session.projection.waterResidual.formatted())
                    LabeledContent("Sediment residual", value: session.projection.sedimentResidual.formatted())
                    LabeledContent("Violations", value: "\(session.projection.violations.count)")
                }
                Section("This creek") {
                    Button("Save this moment") {
                        try? session.save()
                    }
                    .accessibilityIdentifier("save-snapshot")
                    Button("Return to saved moment") {
                        try? session.resume()
                    }
                    .disabled(!session.canResume)
                    .accessibilityIdentifier("resume-snapshot")
                    Button("Begin again", role: .destructive) {
                        try? session.load(BuiltInScenarios.shapeTheBend)
                        dismiss()
                    }
                }
            }
            .navigationTitle("Field Notes")
            .toolbar {
                Button("Done") { dismiss() }
            }
        }
    }
}
