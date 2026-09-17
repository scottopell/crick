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

`CreekCore/DiggingSurface.swift` is an isolated `20 × 26` cellular authority with compatibility ID `crick-digging-surface-v1`:

- an authored descending bend and raised inside shoulder establish a recognizable creek;
- all safe interior cells are equally eligible for excavation—there are no solution cells or route flags;
- every stroke lowers each touched cell once by `0.055`; repeated strokes deepen it, capped at `0.44`;
- each fixed tick derives cardinal edge proposals from one pre-transfer surface;
- every source cell's aggregate proposal is capped to `58%` of its available water before deltas apply simultaneously;
- source admission is bounded by a local depth cap;
- the outlet is a normal transfer participant, then drains a bounded amount;
- a ledger accounts for initial water, source inflow, and outlet outflow;
- one complete invariant gate validates construction and decoded snapshots (overflow-safe dimensions, boundaries, finite surface/cells/rates/ledger, excavation bounds, conservation, and measured edge transfers);
- the last fixed tick exposes completed signed cardinal edge transfers for projection/measurement only; it does not expose or influence routing;
- at `UInt64.max`, a fixed step is a no-op and returns `false` rather than wrapping or partially mutating authority.

The model intentionally excludes momentum, rain, erosion, sediment, spoil, materials, scoring, objectives, and wall-clock advancement. It is a deterministic surface-flow toy, not CFD or an engineering prediction.

Core tests cover coordinate/index round trips, every-cell digging eligibility, aggregate caps, dry-bed/sill behavior, long asymmetric conservation, batching determinism, tick overflow, corrupt JSON invariants, exact replay, and source-to-outlet flow. The reroute test accumulates real signed downstream edge flux from one identical baseline: two connected alternative strokes increase different gate columns and newly wet stroke/downstream patches, while an equally excavated disconnected pit leaves the gate unchanged.

## iOS experiment

The app projects actual cell ground height, water depth, and last-tick flux into a coarse-gravel creek. Blue wet cells join into a water body; sparse white arrowheads show true authoritative flux direction, newly exposed lowered ground is dark brown, and the latest stroke outline remains visible through response playback. There is no legacy centerline in this renderer.

- Tap or drag directly on gravel. A gesture digs each crossed cell once; another gesture digs it again.
- Completing a stroke synchronously computes 18 fixed ticks and captures every resulting world. The UI only plays those immutable frames; presentation sleeps never advance authority.
- **Let water flow** captures 30 more fixed ticks. **Skip animation** ends visual playback at the already-computed final world; it does not pause authority.
- Reduce Motion skips playback and shows the final world with static flux cues.
- Backgrounding freezes playback, settles to the committed final world, and atomically saves it. Foregrounding does not advance time.
- **Save this creek**, **Resume saved creek**, and **Reset fresh creek** live in the Creek menu.
- Digging persistence uses `digging-surface-v1.json` and a typed envelope separate from the legacy `current.crick.json` snapshot.
- VoiceOver sees one dynamically described creek surface plus named controls. Its factual summary reports dug patch count/location and measured newly wet patches without claiming success. **Show selected cell controls** exposes bounded directional selection and **Dig selected cell** instead of hundreds of low-value cell elements; controls wrap at large text sizes.
- Gesture state clears on end, cancellation/disappearance, and disable. If interrupted after excavation but before end, already lowered ground remains valid while no implicit flow batch is committed.

`DiggingSession` and the retained `SimulationSession` are app adapters; `CreekCore` remains platform-neutral and performs no persistence or rendering I/O.

## Legacy Shape the Bend

The menu opens the prior SwiftUI/Metal experience as a sheet. Its six-cell one-dimensional model, stone interaction, objective, bounded 20-tick playback, Before/After reading phase, Field Notes, and legacy snapshot file remain intact. Existing tests still exercise its full miss/retry/success/Keep path after entering through the new menu.

## Build and release status

The local app version is **0.1.0 (7)**. See [PLAYTEST_READINESS.md](PLAYTEST_READINESS.md) for the current exploratory phone check, exact verification matrix, durable artifact paths, and signing limitations.

No TestFlight, public upload, credential/profile creation, or physical-device installation is implied. Final artifact signing status and the constrained local archive attempt are recorded in `PLAYTEST_READINESS.md` and the durable artifact manifest.

## Known limitations

- Cardinal transfers make the water deliberately coarse; there is no diagonal edge, momentum, wake, or eddy model.
- One fixed tick has no calibrated real-world duration.
- Excavation removes height without retaining or placing spoil.
- The source and outlet are fixed; terrain is authored rather than generated.
- Canvas rendering favors a clear small experiment over mesh-level bank geometry.
- Snapshot migration between future digging compatibility IDs is not implemented.
- Automated tests establish mechanics, deterministic rerouting, persistence, and layout—not whether an uncoached person understands the interaction on a physical phone.
