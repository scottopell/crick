import CreekCore
import SwiftUI
import UIKit

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
    @State private var debugCopyConfirmation: String?
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
                    editMode: session.editMode,
                    accessibilitySummary: session.sceneSummary,
                    onEditBegan: session.beginEdit,
                    onEditCells: edit,
                    onGestureEnded: flowAfterDig
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                controls
                if let debugCopyConfirmation {
                    Text(debugCopyConfirmation)
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.mint)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity)
                        .background(.black.opacity(0.7))
                        .accessibilityLabel(debugCopyConfirmation)
                        .accessibilityIdentifier("debug-state-copy-confirmation")
                }
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
            Button("Copy debug state") { copyDebugState() }
                .accessibilityIdentifier("copy-debug-state")
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
                Text("SHAPE THE BEND")
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
                Text("\(session.lastFillChangedCellCount) stroke-filled · \(session.lastFillWetCellCount) wet · \(displayedWorld.materialLedger.externallyAddedFill.formatted(.number.precision(.fractionLength(6)))) added")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.mint.opacity(0.9))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .accessibilityIdentifier("fill-evidence")
            }

            Picker("Ground tool", selection: $session.editMode) {
                Label("Dig", systemImage: "arrow.down.to.line.compact").tag(SurfaceEditMode.dig)
                Label("Fill", systemImage: "arrow.up.to.line.compact").tag(SurfaceEditMode.fill)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("ground-tool")

            HStack(spacing: 8) {
                Text(session.editMode == .dig ? "DIG · one layer below start" : "FILL · ground level at start")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(session.editMode == .dig ? .orange : .mint)
                    .accessibilityIdentifier("ground-tool-status")
                Spacer()
                if let target = session.lastEditTarget {
                    Text("Target ground \(target.formatted(.number.precision(.fractionLength(2))))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.72))
                        .accessibilityIdentifier("ground-target")
                }
            }

            if showAccessibilityDigging {
                accessibilityDigControls
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 9) { primaryControls }
                VStack(spacing: 7) { primaryControls }
            }
            Text(session.editMode == .dig
                 ? "Start a stroke to capture one lower ground layer."
                 : "Start on a level; only lower ground rises to that fixed target.")
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
                    selectedEditButtons
                }
            }
            .font(.caption)
        }
    }

    @ViewBuilder
    private var selectionControls: some View {
        selectionButton("Left", icon: "arrow.left", columns: -1, rows: 0)
        selectionButton("Up", icon: "arrow.up", columns: 0, rows: -1)
        selectedEditButtons
        selectionButton("Down", icon: "arrow.down", columns: 0, rows: 1)
        selectionButton("Right", icon: "arrow.right", columns: 1, rows: 0)
    }

    @ViewBuilder
    private var selectedEditButtons: some View {
        if session.editMode == .fill {
            Button("Capture selected level") {
                _ = session.captureSelectedFillTarget()
            }
            .buttonStyle(.bordered)
            .tint(.mint)
            .accessibilityIdentifier("capture-fill-level")
        }
        Button(session.editMode == .dig ? "Dig selected cell" : "Fill selected cell") {
            if session.applySelectedEdit() { displayedWorld = session.world }
        }
        .buttonStyle(.borderedProminent)
        .tint(session.editMode == .dig ? .brown.opacity(0.9) : .mint.opacity(0.75))
        .disabled(session.editMode == .fill && session.capturedAccessibilityFillTarget == nil)
        .accessibilityHint(session.editMode == .fill && session.capturedAccessibilityFillTarget == nil
            ? "Capture selected level first" : "Applies the captured ground target")
        .accessibilityIdentifier(session.editMode == .dig ? "dig-selected-cell" : "fill-selected-cell")
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

    private func edit(
        _ coordinates: [SurfaceCoordinate],
        target: Double,
        mode: SurfaceEditMode
    ) {
        guard session.apply(coordinates, target: target, mode: mode) else { return }
        displayedWorld = session.world
    }

    private func flowAfterDig() {
        // Live authority is already running; gesture end commits no hidden batch.
    }

    private func copyDebugState() {
        do {
            let tick = session.world.tick
            let data = try session.debugStateData()
            guard let json = String(data: data, encoding: .utf8) else {
                throw DiggingSessionError.unsupportedDebugState
            }
            UIPasteboard.general.string = json
            debugCopyConfirmation = "Copied \(data.count) bytes · tick \(tick)"
            UIAccessibility.post(notification: .announcement, argument: debugCopyConfirmation)
        } catch {
            errorMessage = "The debug state could not be copied."
        }
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
