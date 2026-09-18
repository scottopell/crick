import CreekCore
import SwiftUI

struct LiveClockState: Equatable {
    private(set) var isHoldingTwoX = false

    mutating func setHoldingTwoX(_ holding: Bool) {
        isHoldingTwoX = holding
    }

    /// Returns fixed physical steps for one scheduler pulse. Ineligible pulses do
    /// no work and cancel transient hold state; elapsed time is never an input.
    mutating func stepsForPulse(isEligible: Bool) -> Int {
        guard isEligible else {
            isHoldingTwoX = false
            return 0
        }
        return isHoldingTwoX ? 2 : 1
    }

    mutating func stop() {
        isHoldingTwoX = false
    }
}

struct DiggingContentView: View {
    @State private var session: DiggingSession
    @State private var displayedWorld: SurfaceWorld
    @State private var liveTask: Task<Void, Never>?
    @State private var liveClock = LiveClockState()
    @State private var showMenu = false
    @State private var showLegacy = false
    @State private var showAccessibilityDigging = false
    @State private var errorMessage: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    let legacySession: SimulationSession

    init(session: DiggingSession, legacySession: SimulationSession) {
        _session = State(initialValue: session)
        _displayedWorld = State(initialValue: session.world)
        self.legacySession = legacySession
    }

    var body: some View {
        ZStack {
            Color(red: 0.055, green: 0.072, blue: 0.045).ignoresSafeArea()
            VStack(spacing: 0) {
                header
                DiggingSurfaceView(
                    world: displayedWorld,
                    selectedCoordinate: showAccessibilityDigging
                        ? session.selectedCoordinate : nil,
                    reduceMotion: reduceMotion,
                    interactionEnabled: scenePhase == .active && !showLegacy && !showMenu,
                    accessibilitySummary: session.sceneSummary,
                    onDigCells: dig,
                    onGestureEnded: flowAfterDig
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                controls
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showLegacy) {
            ContentView(session: legacySession)
        }
        .confirmationDialog("Creek menu", isPresented: $showMenu, titleVisibility: .visible) {
            Button("Save this creek") {
                do { try session.save() } catch { errorMessage = "This creek could not be saved." }
            }
            .accessibilityIdentifier("save-digging")
            Button("Resume saved creek") {
                do {
                    try session.resume()
                    displayedWorld = session.world
                } catch { errorMessage = "The separate digging snapshot is missing or damaged." }
            }
            .accessibilityIdentifier("resume-digging")
            Button("Reset fresh creek", role: .destructive) {
                session.reset()
                displayedWorld = session.world
            }
            .accessibilityIdentifier("reset-digging")
            Button("Open legacy Shape the Bend") { showLegacy = true }
            .accessibilityIdentifier("open-legacy")
            Button("Cancel", role: .cancel) {}
        }
        .alert("Creek moment unavailable", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .task { startLiveIfNeeded() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                startLiveIfNeeded()
            } else {
                stopLive()
                try? session.save()
            }
        }
        .onChange(of: showLegacy) { _, shown in
            if shown { stopLive() } else { startLiveIfNeeded() }
        }
        // This transition is the sole owner of menu pause/resume. Dialog actions
        // only mutate model state; dismissal consistently restarts the guarded clock.
        .onChange(of: showMenu) { _, shown in
            if shown { stopLive() } else { startLiveIfNeeded() }
        }
        .onDisappear { stopLive() }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("DIG THE BEND")
                    .font(.caption.weight(.bold))
                    .tracking(1.35)
                    .foregroundStyle(.mint)
                Text("Make your own way for water")
                    .font(.title3.weight(.semibold))
                Text(liveClock.isHoldingTwoX ? "Creek running · 2× held" : session.message)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.68))
                    .lineLimit(1)
                    .accessibilityIdentifier("digging-status")
            }
            Spacer(minLength: 4)
            Button {
                showMenu = true
            } label: {
                Image(systemName: "ellipsis.circle.fill")
                    .font(.title2)
                    .frame(width: 36, height: 36)
            }
            .accessibilityLabel("Creek menu")
            .accessibilityIdentifier("digging-menu")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(.black.opacity(0.24))
    }

    private var controls: some View {
        VStack(spacing: 7) {
            HStack(spacing: 8) {
                Label("Tick \(displayedWorld.tick)", systemImage: "water.waves")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.cyan.opacity(0.9))
                    .accessibilityIdentifier("digging-tick")
                Spacer()
                Text("\(excavatedCellCount) lowered cells")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.orange.opacity(0.9))
                    .accessibilityIdentifier("excavated-cell-count")
            }

            if showAccessibilityDigging {
                accessibilityDigControls
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 9) { primaryControls }
                VStack(spacing: 7) { primaryControls }
            }
            Text("A stroke cuts to one captured layer. Hold 2× to watch the same creek steps faster.")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.58))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 9)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private var primaryControls: some View {
        Label(liveClock.isHoldingTwoX ? "2× flowing" : "Hold for 2×", systemImage: "forward.fill")
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(.cyan.opacity(liveClock.isHoldingTwoX ? 0.72 : 0.34), in: Capsule())
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in liveClock.setHoldingTwoX(true) }
                    .onEnded { _ in liveClock.setHoldingTwoX(false) }
            )
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("Hold for twice speed")
            .accessibilityIdentifier("hold-two-x")

        Button {
            showAccessibilityDigging.toggle()
        } label: {
            Image(systemName: "scope")
                .frame(width: 34)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(showAccessibilityDigging ? "Hide selected cell controls" : "Show selected cell controls")
        .accessibilityIdentifier("selected-cell-controls")
        .disabled(scenePhase != .active)
    }

    private var accessibilityDigControls: some View {
        VStack(spacing: 5) {
            Text("Selected column \(session.selectedCoordinate.column + 1), row \(session.selectedCoordinate.row + 1)")
                .font(.caption.weight(.medium))
                .accessibilityIdentifier("selected-cell-position")
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 7) { selectionControls }
                VStack(spacing: 6) {
                    HStack(spacing: 7) {
                        selectionButton("Left", icon: "arrow.left", columns: -1, rows: 0)
                        selectionButton("Up", icon: "arrow.up", columns: 0, rows: -1)
                        selectionButton("Down", icon: "arrow.down", columns: 0, rows: 1)
                        selectionButton("Right", icon: "arrow.right", columns: 1, rows: 0)
                    }
                    digSelectedButton
                }
            }
            .font(.caption)
        }
    }

    @ViewBuilder
    private var selectionControls: some View {
        selectionButton("Left", icon: "arrow.left", columns: -1, rows: 0)
        selectionButton("Up", icon: "arrow.up", columns: 0, rows: -1)
        digSelectedButton
        selectionButton("Down", icon: "arrow.down", columns: 0, rows: 1)
        selectionButton("Right", icon: "arrow.right", columns: 1, rows: 0)
    }

    private var digSelectedButton: some View {
        Button("Dig selected cell") {
            if session.excavateSelected() { displayedWorld = session.world }
        }
        .buttonStyle(.borderedProminent)
        .tint(.brown.opacity(0.9))
        .accessibilityIdentifier("dig-selected-cell")
    }

    private func selectionButton(
        _ label: String,
        icon: String,
        columns: Int,
        rows: Int
    ) -> some View {
        Button {
            session.moveSelection(columns: columns, rows: rows)
        } label: {
            Image(systemName: icon).frame(width: 18, height: 20)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel("Move selected cell \(label.lowercased())")
    }

    private var excavatedCellCount: Int {
        displayedWorld.cells.count(where: { $0.excavationDepth > 0.000_001 })
    }

    private func dig(_ coordinates: [SurfaceCoordinate], floor: Double) {
        guard session.excavate(coordinates, toFloor: floor) else { return }
        displayedWorld = session.world
    }

    private func flowAfterDig() {
        // Live authority is already running; gesture end commits no hidden batch.
    }

    /// A clock pulse commits at most two identical physical fixed steps. Sleep is
    /// presentation pacing only; elapsed inactive time is never converted to work.
    private func startLiveIfNeeded() {
        guard liveTask == nil, scenePhase == .active, !showLegacy, !showMenu else { return }
        liveTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(110))
                let eligible = !Task.isCancelled && scenePhase == .active && !showLegacy && !showMenu
                let steps = liveClock.stepsForPulse(isEligible: eligible)
                guard steps > 0 else { continue }
                _ = session.advanceLive(steps: steps)
                displayedWorld = session.world
            }
        }
    }

    private func stopLive() {
        liveClock.stop()
        liveTask?.cancel()
        liveTask = nil
        displayedWorld = session.world
    }
}
