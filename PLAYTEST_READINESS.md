## Delivery contract: main → Xcode Cloud → TestFlight

The user confirms that the existing Apple-hosted Xcode Cloud workflow publishes pushes to `main` to TestFlight. Use this established path; do not replace it with GitHub distribution infrastructure. GitHub Actions validates source/builds only and is not TestFlight evidence.

A delivery is complete when the corresponding Xcode Cloud source/build has uploaded, finished Apple processing, and is available to the intended existing TestFlight testers. A git push alone does not prove these downstream stages. Cloud configuration is hosted by Apple; absence of repository configuration or GitHub checks does not mean the workflow is absent. Preserve Cloud-managed unique build numbering; local development build 7 is not evidence of TestFlight build number 7.

Apple processing and tester availability for this iteration remain unverified. Earlier direct installs are historical, not proof of current TestFlight delivery.

---

# Dig / Fill exploratory readiness — 0.1.0 (11)

Updated 2026-09-19. Build 11 adds fixed-level ground filling to the live digging and erosion experiment.

Build 11 is the tested Dig/Fill source iteration. Dig captures one layer below the starting ground; Fill captures the starting ground as-is and raises only lower crossed cells. Ground edits preserve water depth, externally added fill is tracked as actual delta, and all fill enters the existing erodible material kernel. The whole world uses one fixed-tick clock; menus, legacy presentation, and inactive lifecycle phases pause it without catch-up. Current schema-3 authority strictly requires external-fill accounting; valid schema-1 and schema-2 snapshots migrate with zero external fill and are rewritten as current authority. No archive, cloud action, upload, signing, provisioning, credential, or physical-device operation was performed for build 11.

## What is ready

The app launches into **Dig / Fill the Bend**, an unscored 20 × 26 surface-water experiment. A compact accessible toggle keeps the active tool visible, and a ground-height target label appears after capture. The old **Shape the Bend** experience remains available from the Creek menu.

For an exact reproduction, leave the interesting creek visible, open **Creek menu → Copy debug state**, and paste the resulting plain JSON into the report. The copied tick is authoritative; the menu pauses simulation while capturing. The versioned `com.scottopell.crick.debug-state` envelope carries the complete nested save snapshot, selected cell, app version/build, and world compatibility ID, but no private device/account data. Copying does not save, overwrite, advance, or import anything. Developers replay a pasted file through `DiggingDebugStateCodec.decode` and `restoredWorld()`; no user import UI is present.

Automated readiness requires all of the following from final current code:

- `swift test -c release` and the simulator Release build pass;
- XcodeGen regeneration produces no uncommitted surprise beyond the generated project update;
- native and UI suites pass on the specified iPhone 15 and iPhone SE simulators;
- the primary UI journey performs actual dig and bank-to-wet fill strokes, records before/immediate/after-flow screenshots, exercises 2×, repeated menus, save/reset/resume, and proves a measured inactive interval does no work;
- the retained legacy UI journey enters through the Creek menu and still completes its miss/retry/success path;
- the simulator Release artifact succeeds with local build number 11;
- observed screenshots are described as state over time unless a paired intervention establishes causality;
- no archive, device build/install, upload, or product extension is part of this build-11 pass.

Final build-11 verification: 59 package tests passed; 42 Swift Testing native cases, 2 XCTest visual cases, and 2 UI journeys passed on each iPhone 15 Pro and iPhone SE (3rd generation), iOS 17.5, in Release with testability enabled. Before/immediate/post-response Fill screenshots were inspected on both sizes. Logs and images: `/Users/scottopell/dev/crick-builds/fill-build11`.

Final build-9 current-tree results: Swift package release tests **50/50**; native iOS tests **34/34** plus two visual-proof XCTest cases on both iPhone 15 and iPhone SE (3rd generation), both iOS 17.5; UI journeys **2/2** on each simulator; and the simulator Release build succeeded. The paired causal proof advances initially identical, sediment-free cut/control worlds to tick 1200 and records positive cut-minus-control downstream erosion, sediment flux, and deposition effects. This does not rename or attribute the control world's ordinary erosion to the cut. Exact logs, exported proof, and result bundle are under `/Users/scottopell/dev/crick-builds/live-erosion-build9-final`.

## Five-minute phone exploration

Do not coach a route and do not present a success condition.

1. Launch fresh. Ask what the person thinks the blue shape and brown/gravel field are, and where water is going.
2. Ask them to try changing the creek. Observe whether they discover tap or drag without being told exact cells.
3. After one dig stroke, ask what changed first and what changed as the live current continued.
4. Choose Fill, start on a visible bank level, and cross lower or wet ground. Ask which ground stayed unchanged, which rose, and what the water did over later ticks.
5. Hold **2×** briefly, then release or drag away from it. The same creek should visibly run faster only while held and return to 1× afterward.
6. Save, dig again, then Resume. Confirm the separate digging state returns. Reset should return a fresh authored creek whose whole world immediately continues live.
7. Background and foreground. It should pause/save while inactive, resume at 1×, and never convert elapsed wall time into simulation work.
8. Open **Shape the Bend** from the menu and confirm the historical experience remains usable.
9. With VoiceOver, use selected-cell controls for Dig. For Fill, capture a selected bank level, navigate, and apply the fixed target. The creek remains one useful described element rather than hundreds of noisy cells.
10. Check Reduce Motion, large text, portrait, and compact iPhone layout. Report clipping, illegible terrain/water contrast, heat, or confusing cause/effect.

Useful questions: “Where did you dig?”, “Where did water go afterward?”, “What would you try next?”, and “Did anything look like the one correct answer?” A problematic result is one where the person only detects change from tick text, mistakes the selected-cell outline for a goal, or sees an abstract heatmap rather than a gravel creek.

## Signing and distribution honesty

This iteration has Release simulator validation only; no new signed archive or direct phone install was performed. Pushes to main use the established Xcode Cloud/TestFlight path. GitHub CI success and simulator tests do not establish Apple processing or tester availability.

## Current limitations

- This is coarse cardinal surface transfer, not calibrated hydraulics.
- There is no momentum, rainfall, material inventory, score, or objective. Erosion/sediment/deposition are deterministic game mechanics, not calibrated physical predictions.
- Valid schema-1 and schema-2 snapshots migrate to schema 3 with explicit zero external fill. Before first overwrite, exact prior bytes are retained once in a versioned backup; unsupported or corrupt hybrids are rejected atomically.
- Simulator evidence cannot establish physical-device touch feel, performance, battery use, or uncoached comprehension.
- The Canvas presentation intentionally exposes some cellular coarseness; evaluation should determine whether it still reads as creek and gravel rather than debug visualization.
