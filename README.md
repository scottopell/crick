> **Beta delivery:** pushes to `main` use the existing Apple-hosted **Xcode Cloud → TestFlight** workflow (user-confirmed). GitHub Actions and local signed installs are not substitutes for a processed TestFlight build available to the existing testers. Do not create a replacement pipeline or infer Cloud is missing from absent GitHub checks. See [delivery contract and current evidence](PLAYTEST_READINESS.md). Local development build numbers must not be confused with Cloud/TestFlight build numbers.

# Crick

Crick is an experimental, human-scale creek-tending game. Read [VISION.md](VISION.md) for the long-term direction and [DIGGING_EXPERIMENT.md](DIGGING_EXPERIMENT.md) for the commissioned experiment's brief, limits, and work log.

The default iOS scene is now a small **Dig the Bend** exploration: lower visible gravel and watch deterministic two-dimensional surface water find a changed path. It has no objective, score, prescribed route, or result screen. The earlier one-dimensional **Shape the Bend** experience is preserved intact under **Creek menu → Open legacy Shape the Bend**.

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

`CreekCore/DiggingSurface.swift` is an isolated `20 × 26` cellular authority with compatibility ID `crick-digging-surface-v2`:

- an authored descending bend and raised inside shoulder establish a recognizable creek;
- all safe interior cells are equally eligible for excavation—there are no solution cells or route flags;
- finger-down captures one cut floor exactly one layer below the starting cell (bounded by the safe global floor); every cell crossed during that gesture is cut only to that floor, while a later gesture may capture a deeper floor;
- each fixed tick derives cardinal edge proposals from one pre-transfer surface;
- every source cell's aggregate proposal is capped to `58%` of its available water before deltas apply simultaneously;
- source admission is bounded by a local depth cap;
- the outlet is a normal transfer participant, then drains a bounded amount;
- water-edge transfers synchronously advect carried sediment; a bounded game-scale carrying-capacity rule erodes or deposits bed material, source water adds no sediment, and the outlet exports what it drains;
- separate ledgers account for water and conserved ground/carried/exported/excavated material;
- one complete invariant gate validates construction and decoded snapshots (overflow-safe dimensions, boundaries, finite surface/cells/rates/ledgers, excavation bounds, conservation, and measured edge transfers);
- the last fixed tick exposes completed signed cardinal edge transfers for projection/measurement only; it does not expose or influence routing;
- at `UInt64.max`, a fixed step is a no-op and returns `false` rather than wrapping or partially mutating authority.

The model intentionally excludes momentum, rain, placed spoil, scoring, objectives, and wall-clock-derived advancement. Its erosion, sediment transport, and deposition are bounded deterministic game mechanics, not calibrated physical time, CFD, or an engineering prediction.

Core tests cover coordinate/index round trips, every-cell digging eligibility, aggregate caps, dry-bed/sill behavior, long water/material conservation, deterministic fixed-step partitioning, tick overflow, schema migration and corrupt JSON invariants, exact replay, and source-to-outlet flow. A paired intervention test begins with identical sediment-free worlds, cuts only one world, advances both to the same tick, and measures positive **cut-minus-control** downstream erosion, sediment flux, and deposition effects. Those names describe causal differences; they do not claim that all erosion in the baseline was caused by the cut.

## iOS experiment

The app projects actual cell ground height, water depth, and last-tick flux into a coarse-gravel creek. Blue wet cells join into a water body; sparse white arrowheads show true authoritative flux direction; exposed-gravel tone and cut edges scale from actual relief; and short orange lips show visibly wet cells blocked by higher excavated neighbors (which may hold shallow water below the visual wet threshold), using the solver's surface comparison and tolerance. The gesture outline exists only while the finger is down. There is no legacy centerline or suggested route in this renderer.

- Tap or drag directly on gravel. A gesture digs each crossed cell once; another gesture digs it again.
- The entire world runs continuously at 1× while the digging scene is active. Completing a stroke commits no hidden batch; instead, the session observes the next 18 physical fixed ticks before finalizing its factual post-dig summary.
- Hold **2×** to execute two identical physical fixed steps per scheduler pulse; release, leaving the control, opening a menu or legacy sheet, and lifecycle changes clear the transient hold.
- Backgrounding pauses and atomically saves. Foregrounding resumes from saved authority without converting elapsed inactive time into catch-up work.
- A fixed tick has no calibrated real-world duration; scheduler sleeps only pace presentation and are not physics input.
- **Save this creek**, **Resume saved creek**, and **Reset fresh creek** live in the Creek menu.
- Digging persistence uses `digging-surface-v1.json` as its historical filename but writes typed envelope/world schema 2, separate from legacy `current.crick.json`. A validated schema-1 file migrates on read; the first write that would replace one preserves its exact bytes once as `digging-surface-v1.v1-backup.json`, including when launch/background saving occurs before Resume.
- VoiceOver sees one dynamically described creek surface plus named controls. Its factual summary reports dug patch count/location and measured newly wet patches without claiming success. **Show selected cell controls** exposes bounded directional selection and **Dig selected cell** instead of hundreds of low-value cell elements; controls wrap at large text sizes.
- Gesture state clears on end, cancellation/disappearance, and disable. If interrupted after excavation but before end, already lowered ground remains valid while no implicit flow batch is committed.

`DiggingSession` and the retained `SimulationSession` are app adapters; `CreekCore` remains platform-neutral and performs no persistence or rendering I/O.

## Legacy Shape the Bend

The menu opens the prior SwiftUI/Metal experience as a sheet. Its six-cell one-dimensional model, stone interaction, objective, bounded 20-tick playback, Before/After reading phase, Field Notes, and legacy snapshot file remain intact. Existing tests still exercise its full miss/retry/success/Keep path after entering through the new menu.

## Build and release status

The local app version is **0.1.0 (9)**. See [PLAYTEST_READINESS.md](PLAYTEST_READINESS.md) for the current exploratory phone check, exact verification matrix, durable artifact paths, and signing limitations.

No TestFlight, public upload, credential/profile creation, archive, or physical-device installation was performed for build 9. Historical build-7 signing/device evidence and current build-9 simulator-only evidence are separated in `PLAYTEST_READINESS.md`.

## Known limitations

- Cardinal transfers make the water deliberately coarse; there is no diagonal edge, momentum, wake, or eddy model.
- One fixed tick has no calibrated real-world duration.
- Excavated material is conserved in the material ledger but cannot be retained or placed as spoil.
- The source and outlet are fixed; terrain is authored rather than generated.
- Canvas rendering favors a clear small experiment over mesh-level bank geometry.
- Schema-1 digging snapshots migrate to schema 2; unknown future schemas and compatibility IDs are rejected.
- Automated tests establish mechanics, deterministic rerouting, persistence, and layout—not whether an uncoached person understands the interaction on a physical phone.
