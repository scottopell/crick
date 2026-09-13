import CreekRunner
import SwiftUI

enum ShapeTheBendPhase: Equatable {
    case arranging
    case playing
    case outcome
    case kept
}

struct ContentView: View {
    @State private var session: SimulationSession
    @State private var displayedProjection: SimulationProjection
    @State private var phase: ShapeTheBendPhase = .arranging
    @State private var presentationTask: Task<Void, Never>?
    @State private var presentationID = UUID()
    @State private var errorMessage: String?
    @State private var showFieldNotes = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    init(session: SimulationSession) {
        _session = State(initialValue: session)
        _displayedProjection = State(initialValue: session.projection)
    }

    var body: some View {
        ZStack {
            Color(red: 0.055, green: 0.085, blue: 0.06)
                .ignoresSafeArea()
            VStack(spacing: 0) {
                header
                CreekSceneView(
                    projection: displayedProjection,
                    eligibleStoneCells: phase == .arranging ? session.eligibleStoneCells : [],
                    allowsDragging: phase == .arranging,
                    onPlaceStone: placeStone
                )
                .accessibilityIdentifier("creek-scene")
                .accessibilityLabel(sceneAccessibilityLabel)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                actionBar
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showFieldNotes) {
            FieldNotesView(
                session: session,
                onResume: synchronizeFromSession,
                onBeginAgain: synchronizeFromSession
            )
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
            trigger: phase == .outcome
                && displayedProjection.poolObjective?.status == .holding
        )
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase != .active {
                settlePresentation()
            }
        }
        .onDisappear {
            settlePresentation()
        }
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
                .disabled(phase == .playing)
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

    @ViewBuilder
    private var actionBar: some View {
        VStack(spacing: 10) {
            switch phase {
            case .arranging:
                arrangingControls
            case .playing:
                Label(
                    "Creek second \(session.attemptElapsedTicks(for: displayedProjection)) of \(SimulationSession.attemptTicks)",
                    systemImage: "water.waves"
                )
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .accessibilityIdentifier("water-playing")
            case .outcome:
                outcomeControls
            case .kept:
                Label("Creek kept", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.mint)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .accessibilityIdentifier("creek-kept")
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(.ultraThinMaterial)
    }

    private var arrangingControls: some View {
        VStack(spacing: 9) {
            if !hasPlacedStone {
                Label("Drag the bank stone into the creek", systemImage: "hand.draw.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.82))
                    .accessibilityIdentifier("placement-prompt")
            } else if session.mustMoveStone {
                Label("The changed creek remains — move the stone", systemImage: "arrow.left.and.right")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.82))
                    .accessibilityIdentifier("move-stone-prompt")
            } else {
                Text("The stone is set. Test what the water does.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.76))
                    .accessibilityIdentifier("stone-set")
            }
            HStack {
                Text(session.mustMoveStone
                    ? "Choose a different seat and test what happens next."
                    : hasPlacedStone
                        ? "Move it to another available seat, or test this spot."
                        : "Lift the stone from the lower bank.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.58))
                Spacer()
                placementMenu
            }
            Button(action: startAttempt) {
                Label("Test this spot · 20 creek seconds", systemImage: "water.waves")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(.cyan.opacity(0.78))
            .accessibilityIdentifier("let-water-work")
            .disabled(!session.canCommitAttempt)
        }
    }

    private var outcomeControls: some View {
        VStack(spacing: 10) {
            Text(resultCopy)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("result-copy")
            HStack(spacing: 12) {
                Button("Try another spot") {
                    do {
                        try session.tryAnotherSpot()
                        displayedProjection = session.projection
                        phase = .arranging
                    } catch {
                        errorMessage = "This attempt could not be restored."
                    }
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("try-another-spot")

                if displayedProjection.poolObjective?.status == .holding {
                    Button("Keep this pool") {
                        do {
                            try session.keepCreek()
                            displayedProjection = session.projection
                            phase = .kept
                        } catch {
                            errorMessage = "This creek could not be kept."
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.mint.opacity(0.78))
                    .accessibilityIdentifier("keep-creek")
                }
            }
        }
    }

    private var placementMenu: some View {
        Menu("Choose a spot") {
            ForEach(session.eligibleStoneCells, id: \.self) { cell in
                Button(placementName(cell)) {
                    _ = placeStone(cell)
                }
                .accessibilityIdentifier("place-stone-\(cell)")
            }
        }
        .font(.caption.weight(.semibold))
        .accessibilityHint("Alternative to dragging the stone. Only effective, unoccupied seats are listed.")
        .accessibilityIdentifier("choose-stone-position")
    }

    private var hasPlacedStone: Bool {
        session.projection.cells.contains { $0.rockResistance > 0 }
    }

    // Shape the Bend (2): all twenty authoritative frames already exist before
    // this approximately three-second presentation begins. Time never steps the model.
    private func startAttempt() {
        do {
            let frames = try session.commitShapeTheBendAttempt()
            let final = session.projection
            phase = .playing
            if reduceMotion {
                displayedProjection = final
                phase = .outcome
                return
            }

            let id = UUID()
            presentationID = id
            presentationTask?.cancel()
            presentationTask = Task { @MainActor in
                for frame in frames {
                    guard !Task.isCancelled, presentationID == id else { return }
                    displayedProjection = frame
                    try? await Task.sleep(for: .milliseconds(150))
                }
                guard !Task.isCancelled, presentationID == id else { return }
                displayedProjection = final
                phase = .outcome
                presentationTask = nil
            }
        } catch {
            errorMessage = "Place the stone before testing the creek."
        }
    }

    // Shape the Bend (2): lifecycle interruption cancels only presentation and
    // immediately reveals the already-committed authoritative final projection.
    private func settlePresentation() {
        guard phase == .playing else { return }
        presentationID = UUID()
        presentationTask?.cancel()
        presentationTask = nil
        displayedProjection = session.projection
        phase = .outcome
    }

    @discardableResult
    private func placeStone(_ cell: Int) -> Bool {
        do {
            try session.placeRock(cell: cell)
            displayedProjection = session.projection
            return true
        } catch {
            errorMessage = "That location cannot affect the creek."
            return false
        }
    }

    private func placementName(_ cell: Int) -> String {
        switch cell {
        case 0: "Upstream entrance"
        case 1: "Above the bend"
        case 2: "Inside the bend"
        case 3: "Below the bend"
        default: "Lower run"
        }
    }

    private var objectiveMessage: String {
        switch phase {
        case .arranging:
            return "Find a place where water can gather and slow."
        case .playing:
            return "Watch depth and current change through the bend."
        case .outcome, .kept:
            return displayedProjection.poolObjective?.title
                ?? "The creek has settled into its new shape."
        }
    }

    private var resultCopy: String {
        guard let objective = displayedProjection.poolObjective else {
            return "The creek settled. Try another spot or keep this shape."
        }
        switch objective.status {
        case .holding:
            return "A deep, calm pool is holding. Try another spot or keep this pool."
        case .deepButQuick:
            return "The water is deep enough, but the current is still quick. Keep this changed creek and move the stone."
        case .calmButShallow:
            return "The current slowed, but the pool is still shallow. Keep this changed creek and move the stone."
        case .gathering:
            return "A deep, calm pool did not form here. Keep this changed creek and move the stone."
        }
    }

    private func synchronizeFromSession() {
        settlePresentation()
        displayedProjection = session.projection
        phase = session.attemptClosed ? .kept
            : session.hasCommittedAttempt ? .outcome
            : .arranging
    }

    private var sceneAccessibilityLabel: String {
        let stone = session.projection.cells.firstIndex { $0.rockResistance > 0 }
            .map { "Stone at \(placementName($0))." } ?? "Stone on the lower bank."
        let state: String
        switch phase {
        case .arranging: state = "Arranging."
        case .playing: state = "Water working."
        case .outcome: state = "Outcome: \(resultCopy)"
        case .kept: state = "Kept. \(resultCopy)"
        }
        return "Creek bend from upstream left to downstream right. \(stone) \(state)"
    }
}

private struct FieldNotesView: View {
    let session: SimulationSession
    let onResume: () -> Void
    let onBeginAgain: () -> Void
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
                    Button("Save this moment") { try? session.save() }
                        .accessibilityIdentifier("save-snapshot")
                    Button("Return to saved moment") {
                        guard (try? session.resume()) != nil else { return }
                        onResume()
                        dismiss()
                    }
                    .disabled(!session.canResume)
                    .accessibilityIdentifier("resume-snapshot")
                    Button("Begin again", role: .destructive) {
                        guard (try? session.load(BuiltInScenarios.shapeTheBend)) != nil else { return }
                        onBeginAgain()
                        dismiss()
                    }
                }
            }
            .navigationTitle("Field Notes")
            .toolbar { Button("Done") { dismiss() } }
        }
    }
}
