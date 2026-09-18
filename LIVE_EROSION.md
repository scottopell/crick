# Live erosion — build 9 brief

## Product contract

- One deterministic 20×26 material heightfield couples water transfer, bed erosion, carried sediment, deposition, and changed terrain every fixed tick.
- A pointer stroke captures one cut floor at finger-down: one layer below the starting cell, clamped to the world's safe global floor. Every cell in that gesture is cut only down to that same floor; no cell is raised and the floor is never recalculated. VoiceOver uses a separate one-cell scoop.
- The whole world runs live at 1×. Holding 2× runs the same physical fixed steps twice as often; releasing, leaving, opening menus/legacy, saving, or resuming restores 1×/paused state. Inactive elapsed time is discarded, never caught up.
- Sediment follows actual water-edge transfers synchronously from a snapshot. A small bounded flux/slope carrying-capacity proxy drives erosion or deposition; it is a game model, not a calibrated claim. Source water brings no sediment. Outlet sediment is exported.
- Conservation invariant: ground + carried sediment + exported sediment + deliberately excavated material equals the initial ground-material ledger (within floating-point tolerance).
- Rendering uses authoritative carried sediment, bed accumulation/height, water, and flow. It does not decorate a scripted outcome.

## Persistence

- Build 9 writes digging envelope/world schema 2 and validates dimensions, finite bounds, water and material ledgers before atomic replacement of live state.
- Schema-1 snapshots explicitly migrate their exact ground and water values, add zero carried/exported sediment, and derive the excavated ledger from saved authored-minus-ground values. Before the first overwrite, the original v1 file is retained byte-for-byte once as a backup—even if launch/background saving occurs before Resume.
- Unsupported/hostile snapshots fail without mutating the running world.

## Milestones

1. Core v2 state, migration, coupled fixed step, conservation and causal tests.
2. Persistent per-gesture floor plus separate VoiceOver scoop tests.
3. Main-actor capped live scheduler, hold-2× lifecycle, pause/no-catch-up tests.
4. Actual-value sediment/bed visuals and real-interaction UI snapshots.
5. Serial Swift/full release/XcodeGen verification and raw 520-cell timing notes/artifacts.

## Build 9 verification record

- Swift package release suite: **50/50** passed, including paired material-effect, migration, conservation, determinism, and fixture regressions.
- Native iOS suite: **34/34** Swift Testing cases plus **2/2** XCTest visual-proof cases passed on both iPhone 15 and iPhone SE (3rd generation), iOS 17.5 simulators.
- UI suite: **2/2** passed on each simulator. The digging journey uses a real connected drag and physical hold/release, checks repeated menu pause/restart without duplicate clocks, save/reset/resume, a measured inactive interval with zero work, and post-activation ticking. The retained legacy journey completes miss/retry/success/Keep and lifecycle presentation.
- Paired proof: identical sediment-free worlds were advanced to tick 1200. Cutting only the intervention world produced positive cut-minus-control erosion (`0.0018053616599598143`), downstream sediment flux (`0.00018265203896129702`), and deposition (`0.00027451368533548681`). These are causal differences, not a claim that the cut caused the control world's ordinary baseline erosion. Labeled control/intervention PNGs and the measured JSON were exported and inspected.
- Swift package release and simulator Release builds succeeded. No archive, iPhoneOS product, upload, device action, or product extension was performed.
- Raw host timing (release, 20×26 wet/eroding world, 520 fixed ticks; five independent runs): 0.047069834, 0.048856125, 0.047707416, 0.047602916, 0.049866625 seconds. These are host wall timings only—not phone performance, calibrated physical duration, or real-world-time claims.
- Artifacts/logs are under `/Users/scottopell/dev/crick-builds/live-erosion-build9-final`; paired proof is under its `paired-proof/` directory and in `paired-proof.xcresult`. The untouched external feedback fixtures remain byte-identical at SHA-256 `045122fd88a85090d041d172862a76b4283a12b65bcffce7fe4cdafcf0a6a504`.
