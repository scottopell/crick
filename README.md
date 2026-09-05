# Crick

Crick is an experimental, human-scale creek-tending game. Read [VISION.md](VISION.md) for the product direction.

The repository contains a first Scope 1 headless creek laboratory: a platform-independent deterministic Swift core, reproducible scenarios, a command-line runner, versioned snapshots, structured diagnostics, and tests. It does not contain an iOS client.

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

The CLI rejects unknown commands/options, extra positional arguments, duplicate options, missing option values, unknown scenarios, and invalid tick counts with usage on stderr and exit status 2. Artifact writes atomically replace individual destination files; a command requesting several artifacts is not a multi-file transaction.

GitHub Actions independently runs the build, executable, and tests with Swift 6.3.3 on Linux. Local commands are the development feedback loop; CI is a verification gate.

## Simulation contract

`CreekCore` owns a one-dimensional reach of cells with bed elevation, water depth, suspended sediment, and rock resistance. The caller advances integer ticks; one authoritative tick represents one second. Accelerated execution runs more fixed ticks rather than changing the timestep.

At the start of each tick, boundary water and sediment enter the upstream cell. Transfers are calculated in stable cell order from the pre-tick state, then sediment erodes or deposits according to local transport capacity, and water and suspended sediment may leave through the downstream boundary. Every external transfer is accumulated in a material ledger.

Commands carry an explicit tick. Commands sharing a tick execute in caller order before that tick advances. Invalid cells, quantities, past targets, past/future direct application, and schedules extending beyond their target are rejected. A scheduled run is transactional: if any command fails, no ticks or earlier commands from that run are committed.

### Determinism guarantee

The same determinism compatibility ID and platform, initial state or snapshot, and ordered command sequence produce exactly equal authoritative states. The current compatibility ID is `crick-sim-v1`. It must change when authoritative stepping semantics change incompatibly. The core uses fixed ticks, stable array traversal, and no wall clock, file I/O, global random state, or unordered collection traversal.

Cross-compatibility-ID and cross-architecture bit-identical floating-point replay is **not** guaranteed. Snapshots therefore contain schema, simulation, and determinism compatibility versions and reject unsupported values or invalid authoritative state.

## Current evidence

Built-in fixtures provide:

- `baseline`: ordinary flow through an unobstructed reach
- `rock`: a tick-indexed obstruction that creates measurable upstream backwater
- `flood`: a bounded high-flow pulse that causes persistent, conserved bed change

Tests cover exact replay, fixed-step partitioning, atomic command scheduling and rejection, water and sediment budgets, dry and extreme-flow states, non-negative finite state, snapshot round-trip/version/compatibility rejection, repeated save/resume equivalence, scenario behavior, strict CLI parsing, and JSON/CSV diagnostics. Conservation uses a relative tolerance of `1e-9 × max(1, expected inventory)` so diagnostics remain meaningful across scenario scales.

## Known limitations

This is a deliberately small behavioral model, not CFD or engineering software:

- The reach is one-dimensional and uses unit-width/unit-area cells.
- Water transfer, outlet flow, transport capacity, erosion, and deposition are game-oriented coefficients rather than calibrated hydraulics.
- Rocks are cell resistance values, not shaped rigid bodies; the seed is recorded but procedural generation is not yet implemented.
- Sediment has one continuous class; banks, gravel sorting, wakes, eddies, side channels, and rock mobility are not modeled.
- Feature evaluation for swimming holes and crossings is not implemented.
- Snapshot migration, optimized offline catch-up, rendering, persistence I/O policy, and the native iOS client remain future work.
