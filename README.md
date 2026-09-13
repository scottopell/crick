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

The same determinism compatibility ID and platform, initial state or snapshot, and ordered command sequence produce exactly equal authoritative states. The current compatibility ID is `crick-sim-v5`. It must change when authoritative stepping semantics change incompatibly. The core uses fixed ticks, stable array traversal, and no wall clock, file I/O, global random state, or unordered collection traversal.

Cross-compatibility-ID and cross-architecture bit-identical floating-point replay is **not** guaranteed. Snapshots therefore contain schema, simulation, and determinism compatibility versions and reject unsupported values or invalid authoritative state.

## Current evidence

Built-in fixtures provide:

- `baseline`: ordinary flow through an unobstructed reach
- `rock`: a tick-indexed obstruction that creates measurable upstream backwater
- `flood`: a bounded high-flow pulse that causes persistent, conserved bed change

Tests cover exact replay, fixed-step partitioning, atomic command scheduling and rejection, water and sediment budgets, dry and extreme-flow states, non-negative finite state, snapshot round-trip/version/compatibility rejection, repeated save/resume equivalence, scenario behavior, strict CLI parsing, and JSON/CSV diagnostics. Conservation uses a relative tolerance of `1e-9 × max(1, expected inventory)` so diagnostics remain meaningful across scenario scales.

## Shape the Bend gameplay contract

`shape-the-bend` is the first narrow game scenario. Its authoritative objective asks the player to create a deep, calm pool at bend cell 2 and hold both conditions for five consecutive fixed ticks. Objective definition, progress, last authoritative transfers, and result are owned by `CreekCore` and persist in snapshots.

The scenario starts from a deterministic flowing fixture rebased from 40 ordinary authoritative ticks. Calmness is the local speed proxy `transfer leaving target / target water depth`, not total discharge. Current provisional thresholds are `0.50` minimum depth and `0.060` maximum calmness. Five effective stone seats are offered; the outlet is excluded because its resistance cannot affect this solver. At the first 20-tick horizon cells 2 and 3 hold, cell 4 is deep but still quick, and cells 0 and 1 do not form the pool. Tests lock outcomes at 20, 40, and 80 ticks. Moving the stone clears stale objective evidence before the next tick; changing these semantics requires a new determinism compatibility ID.

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
- State changes only through explicit load, fixed-tick experiments, and rock-command intents. Presentation time selects among already-computed immutable projections and never enters authoritative simulation.
- `CreekCore` remains platform-neutral and performs no persistence I/O.
- The app-layer store writes a client envelope containing scenario presentation metadata and the versioned authoritative `SimulationSnapshot`.
- Resume replaces the private simulator only after shared snapshot decoding and invariant validation succeeds.

App-layer unit tests prove exact per-tick experiment projections, effective-seat routing, evolved-reach retry, Keep closure, immutable projection updates, and snapshot recovery. An XCUITest drives a deep-but-quick near miss, moves the same stone on the evolved reach, reaches success, handles background presentation settlement, keeps the pool, and verifies the authoritative tick. GitHub's macOS job regenerates the project and builds the app for a generic simulator; simulator tests run locally because hosted simulator availability varies.

### Metal creek viewport

The player surface is a custom MetalKit viewport under a fixed authored camera. Six authoritative cells are hidden sample stations along one curved creek centerline; five effective stone seats are available without exposing a grid. Smooth bank, gravel, and water ribbons project state, water width derives monotonically from authoritative depth, and animated current cues derive from transfer/depth. Screen-space picking considers only effective unoccupied seats before sending a tick-indexed intent.

A cosmetic shader clock animates only water glints. It is not an input to `SimulationSession`, objective evaluation, persistence, or replay. Xcode 26 requires its matching optional Metal toolchain (`xcodebuild -downloadComponent MetalToolchain`); iOS CI installs it before building.

The playable interaction begins with one stone on the near bank. A pan gesture visually lifts and moves that renderer-owned preview; releasing over the creek resolves the nearest authored station and submits one authoritative `moveRock` command. Invalid releases snap back to the last authoritative location. A named “Choose a spot” menu provides the same intents without spatial dragging.

“Test this spot · 20 creek seconds” synchronously commits exactly 20 fixed ticks and captures one immutable projection after every real tick. The UI presents those projections over about three seconds; cancellation or backgrounding settles to the already-committed final projection, and Reduce Motion presents it immediately. A near miss permits moving the same stone on the evolved reach before another bounded experiment. Only authoritative success offers “Keep this pool.” The player-facing objective text comes only from `PoolObjectiveResult`; detailed conservation data and save/resume remain in Field Notes.

Visual tuning remains projection-only: water depth controls width, color, and opacity; bank/gravel layers and stone shadows create depth; and an in-world ring marks the desired pool function. The canonical test places the stone below that ring, proving the goal marker is not a prescribed placement slot. Render geometry uses an `MTLBuffer` rather than transient constant bytes and validates the Swift/Metal vertex stride before pipeline creation; failure produces a visible accessible fallback instead of a blank viewport.

## Physical-device and TestFlight checklist

Simulator QA proves deterministic behavior and layout, but renewed physical-device comprehension is the final product gate for this revised slice. The prior `crick-sim-v4` device session failed because the response was too subtle and lacked agency, consequence, progress, failure, and payoff. Do not claim the revision resolves that failure until fresh physical-device players complete this bounded session:

- [ ] Fresh install opens on a visibly flowing reach at player tick 0 without an error or saved-state assumption.
- [ ] Without coaching, the player identifies the stone, marked bend, creek direction, and need for both depth and calm.
- [ ] Dragging reveals effective landing seats and confirms the accepted position; the outlet is never offered.
- [ ] “Test this spot · 20 creek seconds” presents perceptible depth and current changes over one bounded observation.
- [ ] A cell-4 near miss reads as deep but quick in the creek itself, not only in result text.
- [ ] The player moves the same stone for a stated reason, understands the evolved reach was retained, and can reach a cell-2 or cell-3 success.
- [ ] Failure offers retry, success alone offers Keep, and neither invites meaningless repeated test taps.
- [ ] Save/Resume preserves the selected rock, creek authority, and attempt closure without creating a second stone.
- [ ] Missing Resume is disabled; corrupt/unreadable recovery shows useful language and preserves the current creek.
- [ ] VoiceOver reads the guide, direction, cells in upstream-to-downstream order, controls, causal summary, diagnostics, and snapshot actions coherently.
- [ ] Largest accessibility text, Increase Contrast, Reduce Motion, portrait, and landscape preserve reachable controls without overlap.
- [ ] Background/foreground and process relaunch do not advance simulation or imply automatic restore.
- [ ] Record launch responsiveness, heat, battery impact, and any unexpected signing/storage behavior on device.

Fresh-device acceptance requires at least 5/6 players to complete one test and correctly explain both the depth and current change, at least 5/6 to identify success or the missed condition without Field Notes, and at least 4/6 to choose a retry location for a stated causal reason. No more than 1/6 should repeat the test because the first run felt unfinished. If players can read the result text but cannot point to matching creek evidence, the revised thesis has failed; progression or broader simulation is not an acceptable substitute.

## Known limitations

This is a deliberately small behavioral model, not CFD or engineering software:

- The reach is one-dimensional and uses unit-width/unit-area cells.
- Water transfer, outlet flow, transport capacity, erosion, and deposition are game-oriented coefficients rather than calibrated hydraulics.
- Rocks are cell resistance values, not shaped rigid bodies; the seed is recorded but procedural generation is not yet implemented.
- Sediment has one continuous class; banks, gravel sorting, wakes, eddies, side channels, and rock mobility are not modeled.
- Feature evaluation for swimming holes and crossings is not implemented.
- Snapshot migration, optimized offline catch-up, and richer rendering remain future work. The native iOS laboratory uses explicit Save/Resume for local snapshots.
