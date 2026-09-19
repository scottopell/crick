> **Beta delivery:** pushes to `main` use the existing Apple-hosted **Xcode Cloud → TestFlight** workflow (user-confirmed). GitHub Actions and local signed installs are not substitutes for a processed TestFlight build available to the existing testers. Do not create a replacement pipeline or infer Cloud is missing from absent GitHub checks. See [delivery contract and current evidence](PLAYTEST_READINESS.md). Local development build numbers must not be confused with Cloud/TestFlight build numbers.

# Crick

Crick is an experimental, human-scale creek-tending game. Read [VISION.md](VISION.md) for the long-term direction and [DIGGING_EXPERIMENT.md](DIGGING_EXPERIMENT.md) for the commissioned experiment's brief, limits, and work log.

The default iOS scene is a small **Dig / Fill the Bend** exploration: lower or raise visible gravel and watch deterministic two-dimensional surface water respond. It has no objective, score, prescribed route, or result screen. The earlier one-dimensional **Shape the Bend** experience is preserved intact under **Creek menu → Open legacy Shape the Bend**.

## Requirements and commands

- Swift 6.3 or later
- XcodeGen and Xcode 26.x for the iOS app
- iOS 17 or later

```sh
swift build
swift test
swift run crick list
swift run crick run baseline

xcodegen generate
xcodebuild -project Crick.xcodeproj -scheme CrickiOS \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro' test
```

`CrickCLI` and the original scenarios remain available. Their JSON/CSV diagnostics, versioned snapshots, command scheduling, conservation tests, and `crick-sim-v5` behavior are unchanged by the digging experiment.

## Digging surface contract

`CreekCore/DiggingSurface.swift` is an isolated `20 × 26` cellular authority with compatibility ID `crick-digging-surface-v3`:

- an authored descending bend and raised inside shoulder establish a recognizable creek;
- all safe interior cells are equally eligible for excavation—there are no solution cells or route flags;
- finger-down captures one cut floor exactly one layer below the starting cell (bounded by the safe global floor); every cell crossed during that gesture is cut only to that floor, while a later gesture may capture a deeper floor;
- fill captures the starting cell's current ground height; crossed cells below that fixed target rise to it, while cells already at or above it stay unchanged;
- ground edits preserve water depth. Submerged fill raises the local water surface, and subsequent ordinary fixed ticks redistribute that water;
- each fixed tick derives cardinal edge proposals from one pre-transfer surface;
- every source cell's aggregate proposal is capped to `58%` of its available water before deltas apply simultaneously;
- source admission is bounded by a local depth cap;
- the outlet is a normal transfer participant, then drains a bounded amount;
- water-edge transfers synchronously advect carried sediment; a bounded game-scale carrying-capacity rule erodes or deposits bed material, source water adds no sediment, and the outlet exports what it drains;
- separate ledgers account for water and conserved ground/carried/exported/excavated material plus actual externally added fill;
- one complete invariant gate validates construction and decoded snapshots (overflow-safe dimensions, boundaries, finite surface/cells/rates/ledgers, excavation bounds, conservation, and measured edge transfers);
- the last fixed tick exposes completed signed cardinal edge transfers for projection/measurement only; it does not expose or influence routing;
- at `UInt64.max`, a fixed step is a no-op and returns `false` rather than wrapping or partially mutating authority.

The model intentionally excludes momentum, rain, scoring, objectives, and wall-clock-derived advancement. Fill is ordinary single-material ground, not a stockpile or protected terrain. Its erosion, sediment transport, and deposition are bounded deterministic game mechanics, not calibrated physical time, CFD, or an engineering prediction.

Core tests cover coordinate/index round trips, every-cell digging eligibility, aggregate caps, dry-bed/sill behavior, long water/material conservation, deterministic fixed-step partitioning, tick overflow, schema migration and corrupt JSON invariants, exact replay, and source-to-outlet flow. A paired intervention test begins with identical sediment-free worlds, cuts only one world, advances both to the same tick, and measures positive **cut-minus-control** downstream erosion, sediment flux, and deposition effects. Those names describe causal differences; they do not claim that all erosion in the baseline was caused by the cut.

## iOS experiment

The app projects actual cell ground height, water depth, and last-tick flux into a coarse-gravel creek. Blue wet cells join into a water body; sparse white arrowheads show true authoritative flux direction; exposed-gravel tone and cut edges scale from actual relief; and short orange lips show visibly wet cells blocked by higher excavated neighbors (which may hold shallow water below the visual wet threshold), using the solver's surface comparison and tolerance. The gesture outline exists only while the finger is down. There is no legacy centerline or suggested route in this renderer.

- Choose **Dig** or **Fill**, then tap or drag directly on gravel. The mode and captured ground target remain visible; changing mode clears transient gesture state.
- The entire world runs continuously at 1× while the digging scene is active. Completing a stroke commits no hidden batch; instead, the session observes the next 18 physical fixed ticks before finalizing its factual post-dig summary.
- Hold **2×** to execute two identical physical fixed steps per scheduler pulse; release, leaving the control, opening a menu or legacy sheet, and lifecycle changes clear the transient hold.
- Backgrounding pauses and atomically saves. Foregrounding resumes from saved authority without converting elapsed inactive time into catch-up work.
- A fixed tick has no calibrated real-world duration; scheduler sleeps only pace presentation and are not physics input.
- **Save this creek**, **Resume saved creek**, and **Reset fresh creek** live in the Creek menu.
- **Copy debug state** pauses with the existing Creek menu and copies compact, plain, versioned JSON. It contains the exact authoritative world (including tick, terrain/water/sediment, ledgers, and last transfers), selected cell, app version/build, and compatibility ID—no device or account data. The confirmation reports byte count and captured tick; copying neither advances the world nor writes the saved creek.
- Persistence uses `digging-surface-v1.json` as its historical filename but writes typed envelope/world schema 3, separate from legacy `current.crick.json`. Valid schema-1 and schema-2 files migrate to current authority with zero external fill; the first replacement preserves exact prior bytes once in a versioned backup, including launch/background saves before Resume.
- VoiceOver sees one dynamically described creek surface plus named controls. **Show selected cell controls** exposes bounded navigation and selected-cell editing instead of hundreds of low-value cell elements. Fill users explicitly capture one selected ground level, navigate, then apply that unchanged target; capturing and applying at the same cell is a no-op.
- Gesture state clears on end, cancellation/disappearance, and disable. If interrupted after excavation but before end, already lowered ground remains valid while no implicit flow batch is committed.

`DiggingSession` and the retained `SimulationSession` are app adapters; `CreekCore` remains platform-neutral and performs no persistence or rendering I/O.

### Exact debug-state replay

For a report, open **Creek menu → Copy debug state** while the interesting state is visible, then paste the JSON into a text file. The JSON is human-portable and intentionally not Base64. Developer tests replay it with `DiggingDebugStateCodec.decode(Data(contentsOf: url))`, then call `restoredWorld()` on the decoded envelope; this uses the same nested `DiggingSnapshotEnvelope` compatibility/migration gate as Resume. There is intentionally no user-facing import command.

## Legacy Shape the Bend

The menu opens the prior SwiftUI/Metal experience as a sheet. Its six-cell one-dimensional model, stone interaction, objective, bounded 20-tick playback, Before/After reading phase, Field Notes, and legacy snapshot file remain intact. Existing tests still exercise its full miss/retry/success/Keep path after entering through the new menu.

## Build and release status

The local app version is **0.1.0 (11)**. See [PLAYTEST_READINESS.md](PLAYTEST_READINESS.md) for the exact verification matrix and durable artifact paths. Local numbering remains separate from Cloud/TestFlight numbering.

No TestFlight, public upload, credential/profile creation, archive, signing-account change, or physical-device installation was performed for build 11.

## Known limitations

- Cardinal transfers make the water deliberately coarse; there is no diagonal edge, momentum, wake, or eddy model.
- One fixed tick has no calibrated real-world duration.
- Excavation and external fill are scalar ledger terms; there is no player material inventory.
- The source and outlet are fixed; terrain is authored rather than generated.
- Canvas rendering favors a clear small experiment over mesh-level bank geometry.
- Valid schema-1 and schema-2 digging snapshots migrate to schema 3; unknown future schemas and compatibility IDs are rejected.
- Automated tests establish mechanics, deterministic rerouting, persistence, and layout—not whether an uncoached person understands the interaction on a physical phone.
