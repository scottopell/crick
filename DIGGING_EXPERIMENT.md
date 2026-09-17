# Digging reroute experiment

## Brief

Build a deliberately small exploratory creek where digging the visible bed can redirect real simulated surface water. Keep the existing **Shape the Bend** one-dimensional experience intact and available from the app menu; the digging scene is the default launch surface.

The new authority is an isolated deterministic 2D heightfield in `CreekCore`, approximately 20 × 26 cells. It has an authored recognizable bend and inside shoulder, but no marked answer cells or preselected routes. Every safe interior cell is diggable in equal increments. A fixed tick computes simultaneous four-neighbor surface-height transfers, caps each source's aggregate outflow by its available water, admits bounded source water, and lets the outlet participate in transfer and drainage. The experiment intentionally has no momentum, rain, erosion, sediment transport, material types, scoring, objectives, or wall-clock authority.

The UI should make cause and effect legible: a tap/drag brush lowers each touched cell once per gesture; another stroke deepens it again. Lowered exposed ground appears immediately, then bounded fixed-tick playback shows water occupying and moving through the changed heightfield. Observe/Skip animation (or a bounded **Let water flow** action), Reset, Save/Resume, and a Legacy menu entry must fit a compact phone. VoiceOver gets named controls and a selected-cell digging alternative rather than hundreds of cell elements. Reduce Motion shows static, source-derived direction cues.

## Limits and honesty

- This is a cellular surface-flow toy, not CFD and not a prediction tool.
- Cells are coarse, transfers are cardinal only, and one tick has no calibrated real-world duration.
- Digging removes height without tracking spoil; water alone is conserved and ledgered.
- The source and outlet are fixed boundaries. The authored terrain suggests a creek but does not encode a solution route.
- Playback timing only reveals already-computed fixed-tick frames. Backgrounding freezes presentation and never advances authority.
- Persistence uses a separate typed digging snapshot/file. Existing legacy snapshots remain untouched.
- Release artifacts produced for this experiment are local and unsigned unless a pre-existing signing identity is available; no credentials, provisioning updates, TestFlight, or public upload are part of this work.

## Work log

- Baseline confirmed clean at recovery commit `70277a0`; no commit will be created before review.
- Implemented isolated `crick-digging-surface-v1`: 20 × 26 authored bend, freely diggable safe interior, simultaneous conservative cardinal transfers, bounded source, participating/draining outlet, water ledger, and Codable validation.
- Added the default unscored SwiftUI digging scene, real tap/drag brush (once per cell per gesture), 18-tick post-stroke capture, 30-tick Observe action, Skip animation presentation, Reduce Motion behavior, actual height/water/flux rendering, separate persistence, background freeze/save, selected-cell VoiceOver alternative, and retained legacy menu path.
- Initial drag smoke exposed a timing-sensitive assertion and a false suggested-route cue. Kept the meaningful drag/tick assertions, hid selection until its accessibility controls are opened, softened grid seams, and settled the generic fixture long enough to connect to its outlet. No coordinate-outcome solver special case was added.
- Final reroute authority accumulates signed completed edge transfers through a downstream gate from identical no-dig baselines. After three connected strokes and 100 ticks, west adds `0.284079` flux through column 12 and east adds `0.124574` through column 15 (both baseline `0`), each creates newly wet stroke/downstream patches, while a disconnected pit changes the gate by exactly `0`.
- Final verification passed: Swift package tests 40/40; both iPhone 15 Pro and iPhone SE (3rd generation) iOS 17.5 simulator runs 28/28 (26 native plus 2 UI), including an interrupted-brush reset seam test; Swift production, simulator Release, and unsigned iPhoneOS Release builds succeeded.
- The post-test generic Release archive succeeded using the existing Apple Development identity and wildcard team profile for `X2ULA6KJUN`, without `-allowProvisioningUpdates` or credential/profile changes. Independent strict `codesign` verification passed; the embedded development profile expires 2027-07-06 and lists two provisioned devices. This is not App Store distribution. Parent verified the paired phone is listed in the profile, installed build 7 successfully, and confirmed version 0.1.0 (7) in device inventory.
- Durable artifact set: `/Users/scottopell/dev/crick-builds/digging-build7` (fresh zipped simulator, unsigned iPhoneOS, development-signed iPhoneOS, and signed `.xcarchive` outputs; logs; two `.xcresult` bundles; four inspected screenshots; SHA-256 list; and an inspected 21.18-second H.264 simulator recording of the connected-stroke UI evidence). The screenshots/video honestly predate the final two nonvisual authority/lifecycle fixes; both current-tree UI suites passed unchanged afterward.
- No TestFlight/public upload, provisioning update, or credentials operation was performed. The local signed app was installed on the paired phone; launch and hands-on validation remain pending. Simulator evidence does not replace personal phone evaluation of touch feel, visual understanding, performance, or accessibility.
