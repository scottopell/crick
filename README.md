# Crick

Crick is an experimental, human-scale creek-tending game. Read [VISION.md](VISION.md) for the product direction.

The repository contains a first Scope 1 headless creek laboratory: a platform-independent deterministic Swift core, reproducible scenarios, a command-line runner, versioned snapshots, structured diagnostics, and tests. It also includes a native SwiftUI iOS laboratory for interactive playtesting. See [first playtest readiness](PLAYTEST_READINESS.md) for release preparation and Xcode Cloud steps.

## Requirements

- Swift 6.3 or later
- macOS or Linux

The initial environment was validated with:

- macOS 26.5.2 (arm64)
- Xcode 26.6 (build 17F113)
- Apple Swift 6.3.3
- Swift Package Manager 6.3.3

The package uses Swift tools version 6.3 and Swift 6 language mode. The core intentionally has no Apple-framework, wall-clock, file-I/O, or global-random-state dependency.

## Build and test

```sh
swift build
swift run crick list
swift run crick run baseline
swift run crick run rock --json /tmp/rock.json --csv /tmp/rock.csv \
  --snapshot /tmp/rock.snapshot.json
swift run crick resume /tmp/rock.snapshot.json --ticks 20
swift test
```

Each scenario prints its ending tick, water and sediment inventories, conservation residuals, and invariant-violation count. JSON evidence contains the complete scenario definition, initial state, tick-indexed commands, final state, and diagnostics. CSV exports final per-cell values.

The CLI reports and rejects unknown commands/options, extra positional arguments, duplicate options, missing option values, unknown scenarios, invalid tick counts, and normalized artifact-path collisions with usage on stderr and exit status 2. Artifact writes atomically replace individual destination files; a command requesting several artifacts is not a multi-file transaction.

GitHub Actions independently runs the build, executable, and tests with Swift 6.3.3 on Linux. Local commands are the development feedback loop; CI is a verification gate.

## Simulation contract

`CreekCore` owns a one-dimensional reach of cells with bed elevation, water depth, suspended sediment, and rock resistance. The caller advances integer ticks; one authoritative tick represents one second. Accelerated execution runs more fixed ticks rather than changing the timestep.

At the start of each tick, boundary water and sediment enter the upstream cell. Transfers are calculated in stable cell order from the pre-tick state, then sediment erodes or deposits according to local transport capacity, and water and suspended sediment may leave through the downstream boundary. Every external transfer is accumulated in a material ledger.

Commands carry an explicit tick. Commands sharing a tick execute in caller order before that tick advances. Invalid cells, quantities, past targets, past/future direct application, and schedules extending beyond their target are rejected. A scheduled run is transactional: if any command fails, no ticks or earlier commands from that run are committed.

### Determinism guarantee

The same determinism compatibility ID and platform, initial state or snapshot, and ordered command sequence produce exactly equal authoritative states. The current compatibility ID is `crick-sim-v4`. It must change when authoritative stepping semantics change incompatibly. The core uses fixed ticks, stable array traversal, and no wall clock, file I/O, global random state, or unordered collection traversal.

Cross-compatibility-ID and cross-architecture bit-identical floating-point replay is **not** guaranteed. Snapshots therefore contain schema, simulation, and determinism compatibility versions and reject unsupported values or invalid authoritative state.

## Current evidence

Built-in fixtures provide:

- `baseline`: ordinary flow through an unobstructed reach
- `rock`: a tick-indexed obstruction that creates measurable upstream backwater
- `flood`: a bounded high-flow pulse that causes persistent, conserved bed change

Tests cover exact replay, fixed-step partitioning, atomic command scheduling and rejection, water and sediment budgets, dry and extreme-flow states, non-negative finite state, snapshot round-trip/version/compatibility rejection, repeated save/resume equivalence, scenario behavior, strict CLI parsing, and JSON/CSV diagnostics. Conservation uses a relative tolerance of `1e-9 × max(1, expected inventory)` so diagnostics remain meaningful across scenario scales.

## Shape the Bend gameplay contract

`shape-the-bend` is the first narrow game scenario. Its authoritative objective asks the player to create a deep, calm pool at bend cell 2 and hold both conditions for five consecutive fixed ticks. Objective definition, progress, last authoritative transfers, and result are owned by `CreekCore` and persist in snapshots.

The current thresholds (`0.23` minimum depth and `0.028` maximum transfer) are provisional tuning discovered from the six available stone placements at tick 40. They produce two viable choices, one calm-but-shallow near miss, and three deep-but-quick near misses. Tests lock down this useful choice shape while visual and interaction tuning proceeds; changing authoritative semantics requires a new determinism compatibility ID.

A single authoritative `moveRock` command atomically removes the stone from its prior cell and places it in its destination at the command tick. Rendering, drag previews, and settle animation remain projections and cannot relocate the stone.

## Native iOS laboratory

The first native client is generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen) and targets iOS 17 or later:

```sh
xcodegen generate
xcodebuild -project Crick.xcodeproj -scheme CrickiOS \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro' test
```

The app is a projection and intent adapter, not a second simulation:

- A `@MainActor` `SimulationSession` privately owns the only `Simulator`.
- SwiftUI receives immutable cell and diagnostic projections; no mutable `WorldState` is exposed.
- State changes only through explicit load, fixed-tick advance, and rock-command intents. There are no timers or wall-clock inputs.
- `CreekCore` remains platform-neutral and performs no persistence I/O.
- The app-layer store writes a client envelope containing scenario presentation metadata and the versioned authoritative `SimulationSnapshot`.
- Resume replaces the private simulator only after shared snapshot decoding and invariant validation succeeds.

App-layer unit tests prove explicit tick counts, command routing, immutable projection updates, and snapshot recovery. An XCUITest drives the rendered controls through advance, rock placement, save, further advancement, and restoration. GitHub's macOS job regenerates the project and builds the app for a generic simulator; simulator tests run locally because hosted simulator availability varies.

### Metal creek viewport

The player surface is a custom MetalKit viewport under a fixed authored camera. Six authoritative cells are hidden sample stations along one curved creek centerline; smooth bank, gravel, and water ribbons project their state without exposing a grid. Water width derives from authoritative depth, placed stone location derives from resistance, and screen-space picking resolves to the nearest authored station before sending a tick-indexed intent.

A cosmetic shader clock animates only water glints. It is not an input to `SimulationSession`, objective evaluation, persistence, or replay. Xcode 26 requires its matching optional Metal toolchain (`xcodebuild -downloadComponent MetalToolchain`); iOS CI installs it before building.

The playable interaction begins with one stone on the near bank. A pan gesture visually lifts and moves that renderer-owned preview; releasing over the creek resolves the nearest authored station and submits one authoritative `moveRock` command. Invalid releases snap back to the last authoritative location. A named “Choose a spot” menu provides the same intents without spatial dragging.

“Let the water work” advances exactly 20 fixed ticks. The renderer eases water width toward the new authoritative depths over 0.7 seconds, but interpolation and haptics are cosmetic and never persisted. The player-facing objective text comes only from `PoolObjectiveResult`. Detailed conservation data and save/resume live in Field Notes rather than the main game surface.

Visual tuning remains projection-only: water depth controls width, color, and opacity; bank/gravel layers and stone shadows create depth; and an in-world ring marks the desired pool function. The canonical test places the stone below that ring, proving the goal marker is not a prescribed placement slot. Render geometry uses an `MTLBuffer` rather than transient constant bytes and validates the Swift/Metal vertex stride before pipeline creation; failure produces a visible accessible fallback instead of a blank viewport.

## Physical-device and TestFlight checklist

Simulator QA is the release gate for the current slice; a phone is not required to continue development. When a physical device or TestFlight group is available, run this bounded session:

- [ ] Fresh install launches to baseline tick 0 without an error or saved-state assumption.
- [ ] The two-step guide, both Advance controls, and upstream/downstream labels are understandable before explanation.
- [ ] Each of the six creek cells is comfortably tappable and the selected cell visibly changes from plus to rock.
- [ ] Rock placement does not advance the tick; Advance 1 and Advance 10 change it by exactly those amounts.
- [ ] After advancement, water pooling and downstream change are visually noticeable and the observation card names the selected rock and elapsed fixed ticks.
- [ ] Save enables Resume; advancing and resuming returns to the saved tick, selected rock, and creek state.
- [ ] Missing Resume is disabled; corrupt/unreadable recovery shows useful language and preserves the current creek.
- [ ] VoiceOver reads the guide, direction, cells in upstream-to-downstream order, controls, causal summary, diagnostics, and snapshot actions coherently.
- [ ] Largest accessibility text, Increase Contrast, Reduce Motion, portrait, and landscape preserve reachable controls without overlap.
- [ ] Background/foreground and process relaunch do not advance simulation or imply automatic restore.
- [ ] Record launch responsiveness, heat, battery impact, and any unexpected signing/storage behavior on device.

Top questions for first-time users:

1. Without coaching, what do you think the brown, blue, plus, rock, and arrows represent?
2. What do you expect to happen after tapping a plus? Is pressing Advance the next action you naturally choose?
3. Can you tell which side is upstream and where water is pooling after placing a rock?
4. Does the observed-change card help connect your intervention to the creek, or does it feel like developer data?
5. Is the difference between Advance 1 and Advance 10 useful and predictable?
6. What do you expect Save and Resume—and closing/reopening the app—to do?
7. Does this interaction feel like tending a creek, or only operating a diagnostic model? What single change would improve that feeling most?

Review has reached diminishing returns for simulator-only scope: fresh reviewers and direct reproduction found and closed first-use instruction placement, resume availability, recovery preservation, compact-screen execution, latest-rock attribution, and accessibility-summary issues. Remaining concerns require perception, touch, VoiceOver, and expectation evidence from people on physical hardware; expanding simulation or inventing answers in UI code would not be justified.

## Known limitations

This is a deliberately small behavioral model, not CFD or engineering software:

- The reach is one-dimensional and uses unit-width/unit-area cells.
- Water transfer, outlet flow, transport capacity, erosion, and deposition are game-oriented coefficients rather than calibrated hydraulics.
- Rocks are cell resistance values, not shaped rigid bodies; the seed is recorded but procedural generation is not yet implemented.
- Sediment has one continuous class; banks, gravel sorting, wakes, eddies, side channels, and rock mobility are not modeled.
- Feature evaluation for swimming holes and crossings is not implemented.
- Snapshot migration, optimized offline catch-up, and richer rendering remain future work. The native iOS laboratory uses explicit Save/Resume for local snapshots.
