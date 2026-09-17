import CreekCore
import SwiftUI

struct DiggingContentView: View {
    @State private var session: DiggingSession
    @State private var displayedWorld: SurfaceWorld
    @State private var playbackTask: Task<Void, Never>?
    @State private var playbackID = UUID()
    @State private var isPlaying = false
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
                    interactionEnabled: !isPlaying && scenePhase == .active,
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
        .alert("Creek moment unavailable", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                settlePlayback()
                try? session.save()
            }
        }
        .onDisappear { settlePlayback() }
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
                Text(isPlaying ? "Watching captured fixed ticks…" : session.message)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.68))
                    .lineLimit(1)
                    .accessibilityIdentifier("digging-status")
            }
            Spacer(minLength: 4)
            Menu {
                Button("Save this creek", systemImage: "square.and.arrow.down") {
                    do { try session.save() } catch { errorMessage = "This creek could not be saved." }
                }
                .accessibilityIdentifier("save-digging")
                Button("Resume saved creek", systemImage: "arrow.counterclockwise") {
                    settlePlayback()
                    do {
                        try session.resume()
                        displayedWorld = session.world
                    } catch {
                        errorMessage = "The separate digging snapshot is missing or damaged."
                    }
                }
                .disabled(!session.canResume)
                .accessibilityIdentifier("resume-digging")
                Divider()
                Button("Reset fresh creek", systemImage: "arrow.triangle.2.circlepath", role: .destructive) {
                    settlePlayback()
                    session.reset()
                    displayedWorld = session.world
                }
                .accessibilityIdentifier("reset-digging")
                Button("Open legacy Shape the Bend", systemImage: "clock.arrow.circlepath") {
                    settlePlayback()
                    showLegacy = true
                }
                .accessibilityIdentifier("open-legacy")
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
            Text("Drag once to lower each touched patch. Repeat a stroke to dig deeper.")
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
        Button {
            if isPlaying {
                settlePlayback()
            } else {
                play(session.advanceCaptured())
            }
        } label: {
            Label(
                isPlaying ? "Skip animation" : "Let water flow",
                systemImage: isPlaying ? "forward.end.fill" : "play.fill"
            )
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(isPlaying ? .orange.opacity(0.82) : .cyan.opacity(0.76))
        .accessibilityIdentifier(isPlaying ? "skip-water-animation" : "let-water-flow")

        Button {
            showAccessibilityDigging.toggle()
        } label: {
            Image(systemName: "scope")
                .frame(width: 34)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(showAccessibilityDigging ? "Hide selected cell controls" : "Show selected cell controls")
        .accessibilityIdentifier("selected-cell-controls")
        .disabled(isPlaying)
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
            play(session.excavateSelected())
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

    private func dig(_ coordinates: [SurfaceCoordinate]) {
        guard session.excavate(coordinates) else { return }
        displayedWorld = session.world
    }

    private func flowAfterDig() {
        play(session.advanceCaptured(count: DiggingSession.automaticTicks))
    }

    /// Authority advances synchronously above. This task only reveals immutable
    /// captured fixed-tick states; sleep duration is never a simulation input.
    private func play(_ frames: [SurfaceWorld]) {
        guard !frames.isEmpty else { return }
        playbackTask?.cancel()
        let id = UUID()
        playbackID = id
        isPlaying = true
        if reduceMotion {
            displayedWorld = frames[frames.count - 1]
            isPlaying = false
            return
        }
        playbackTask = Task { @MainActor in
            for frame in frames {
                guard !Task.isCancelled, playbackID == id else { return }
                displayedWorld = frame
                try? await Task.sleep(for: .milliseconds(58))
            }
            guard !Task.isCancelled, playbackID == id else { return }
            displayedWorld = session.world
            isPlaying = false
            playbackTask = nil
        }
    }

    private func settlePlayback() {
        playbackID = UUID()
        playbackTask?.cancel()
        playbackTask = nil
        displayedWorld = session.world
        isPlaying = false
    }
}
