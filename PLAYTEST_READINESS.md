# Digging experiment exploratory readiness — 0.1.0 (7)

Updated 2026-09-16. This document replaces the stale build-1 distribution checklist; historical text remains in git.

## What is ready

The app launches into **Dig the Bend**, an unscored 20 × 26 surface-water experiment. The old **Shape the Bend** experience remains available from the Creek menu. Build 7 is intended for one-person exploratory evaluation, not cohort acceptance and not TestFlight distribution.

Automated readiness requires all of the following from final current code:

- `swift test` and `swift build -c release` pass;
- XcodeGen regeneration produces no uncommitted surprise beyond the generated project update;
- native and UI suites pass on the specified iPhone 15 Pro and iPhone SE simulators;
- the digging UI test performs an actual surface drag (not the selected-cell fallback or menu), observes lowered cells, verifies 18 real ticks per stroke, repeats to deepen, and verifies save/reset/resume;
- the retained legacy UI journey enters through the Creek menu and still completes its miss/retry/success path;
- generic unsigned iPhoneOS and simulator Release artifacts succeed with build number 7;
- after all tests, a constrained signed generic iOS Release archive succeeds with team `X2ULA6KJUN`, existing settings, and no provisioning updates;
- final screenshots and a short simulator recording are inspected and stored outside the repository.

Final current-tree results: Swift package tests **40/40**; iPhone 15 Pro and iPhone SE (3rd generation), both iOS 17.5, **28/28 each** (**26 native + 2 UI**); Swift production, simulator Release, unsigned iPhoneOS Release, and development-signed generic archive all succeeded. The added native seam test verifies an interrupted brush resets when interaction is disabled. Exact evidence and artifact paths are recorded in `DIGGING_EXPERIMENT.md` and the durable manifest.

## Five-minute phone exploration

Do not coach a route and do not present a success condition.

1. Launch fresh. Ask what the person thinks the blue shape and brown/gravel field are, and where water is going.
2. Ask them to try changing the creek. Observe whether they discover tap or drag without being told exact cells.
3. After one stroke, ask what changed first (exposed lowered ground) and what changed after the bounded playback (wet cells/direction).
4. Ask them to make a different route somewhere else. Repeated strokes should deepen a chosen path; there is no required answer.
5. Use **Let water flow**, then **Skip animation** if caught during playback. Confirm the authoritative tick advances in fixed batches only.
6. Save, dig or flow again, then Resume. Confirm the separate digging state returns. Reset should return a fresh tick-0 authored creek.
7. Background and foreground during playback. It should settle to the already-computed final frame, save, and never use elapsed wall time.
8. Open **Shape the Bend** from the menu and confirm the historical experience remains usable.
9. With VoiceOver, open selected-cell controls, move selection, and use **Dig selected cell**. The creek should be one useful described element rather than hundreds of noisy cells.
10. Check Reduce Motion, large text, portrait, and compact iPhone layout. Report clipping, illegible terrain/water contrast, heat, or confusing cause/effect.

Useful questions: “Where did you dig?”, “Where did water go afterward?”, “What would you try next?”, and “Did anything look like the one correct answer?” A problematic result is one where the person only detects change from tick text, mistakes the selected-cell outline for a goal, or sees an abstract heatmap rather than a gravel creek.

## Signing and distribution honesty

`security find-identity -v -p codesigning` reports two valid local identities, including **Apple Development: Scott Opell (SAJR9U4DL2)**; the project team is `X2ULA6KJUN`. The final archive succeeded using only this existing setup, without `-allowProvisioningUpdates`, credential/account changes, new profiles, or upload. Strict `codesign` verification passed. Its wildcard development profile expires 2027-07-06 and contains two provisioned-device entries; the paired Scott iPhone was confirmed eligible and build 7 was installed successfully. Device app inventory confirms 0.1.0 (7).

The durable artifact set contains:

- a zipped simulator `.app`, usable only with a compatible Simulator;
- an explicitly labeled **unsigned** iPhoneOS Release `.app`, not installable on a physical phone as-is;
- a verified Apple Development-signed iPhoneOS `.app` and its `.xcarchive` (not an App Store artifact);
- final test/build/signing logs and two `.xcresult` bundles;
- four inspected screenshots and an inspected 21.18-second simulator video retained from immediately before the final two nonvisual authority/lifecycle fixes; current-tree UI suites confirm appearance-facing journeys still pass.

There is no TestFlight or public upload and no claim of physical-device validation. A successful development-signed archive is phone-installable only on devices allowed by its embedded profile; it is not an App Store distribution artifact. Build 7 is installed on the paired Scott iPhone, but launch and hands-on comprehension remain for the user to verify.

## Current limitations

- This is coarse cardinal surface transfer, not calibrated hydraulics.
- There is no momentum, rainfall, erosion, sediment, spoil placement, material mechanic, score, or objective.
- Digging snapshot migration is not implemented beyond schema/compatibility rejection.
- Simulator evidence cannot establish physical-device touch feel, performance, battery use, or uncoached comprehension.
- The Canvas presentation intentionally exposes some cellular coarseness; evaluation should determine whether it still reads as creek and gravel rather than debug visualization.
