## Delivery contract: main → Xcode Cloud → TestFlight

The user confirms that the existing Apple-hosted Xcode Cloud workflow publishes pushes to `main` to TestFlight. Use this established path; do not replace it with GitHub distribution infrastructure. GitHub Actions validates source/builds only and is not TestFlight evidence.

A delivery is complete when the corresponding Xcode Cloud source/build has uploaded, finished Apple processing, and is available to the intended existing TestFlight testers. A git push alone does not prove these downstream stages. Cloud configuration is hosted by Apple; absence of repository configuration or GitHub checks does not mean the workflow is absent. Preserve Cloud-managed unique build numbering; local development build 7 is not evidence of TestFlight build number 7.

The development-signed 0.1.0 (7) artifact from source `687ca314355a0369f1ab4fab8148e50e118654c2` was reinstalled on the paired Scott iPhone on 2026-09-17 at the user's request, without uninstalling or clearing app data. Device inventory confirms build 7. This is temporary access, not fulfillment of TestFlight delivery; phone launch and acceptance are not claimed.

The delivery-documentation commit carrying this section is an intentional new push to the existing Cloud trigger, with no product/source changes. The prior product commit was already on remote main; a no-op push would not retrigger it. Apple run/processing/tester availability remains unverified from this agent's unauthenticated portal session.

---

# Digging experiment exploratory readiness — 0.1.0 (9)

Updated 2026-09-18. This document replaces the stale build-8 candidate status; historical text remains in git.

Build 9 is a local, uncommitted live-erosion candidate only. The whole digging world runs continuously while active, couples water to bounded game-scale erosion, carried sediment, and deposition, and writes schema-2 authority. Its 2× control changes how many identical physical fixed steps each scheduler pulse commits; a tick has no calibrated real-world duration. Menus, legacy presentation, and lifecycle transitions pause the guarded clock and discard elapsed inactive time rather than catching up. No archive, cloud, upload, signing, provisioning, credential, or physical-device operation was performed for build 9; the installed-phone statement above remains about build 7 only.

## What is ready

The app launches into **Dig the Bend**, an unscored 20 × 26 surface-water experiment. The old **Shape the Bend** experience remains available from the Creek menu. The experiment is intended for personal exploratory evaluation, not cohort acceptance. Its normal delivery channel is the existing main-to-TestFlight workflow described above; the local development-signed build is only a temporary alternative.

Automated readiness requires all of the following from final current code:

- `swift test -c release` and the simulator Release build pass;
- XcodeGen regeneration produces no uncommitted surprise beyond the generated project update;
- native and UI suites pass on the specified iPhone 15 and iPhone SE simulators;
- the digging UI test performs an actual surface drag (not the selected-cell fallback or menu), observes lowered cells, exercises physical hold/release 2×, repeats to deepen, verifies menu pause/restart without duplicate clocks, verifies save/reset/resume, and proves a measured inactive interval does no work;
- the retained legacy UI journey enters through the Creek menu and still completes its miss/retry/success path;
- the simulator Release artifact succeeds with build number 9;
- paired same-tick cut/control screenshots and measured JSON are exported outside the repository and inspected;
- no archive, device build/install, upload, or product extension is part of this build-9 pass.

Final build-9 current-tree results: Swift package release tests **50/50**; native iOS tests **34/34** plus two visual-proof XCTest cases on both iPhone 15 and iPhone SE (3rd generation), both iOS 17.5; UI journeys **2/2** on each simulator; and the simulator Release build succeeded. The paired causal proof advances initially identical, sediment-free cut/control worlds to tick 1200 and records positive cut-minus-control downstream erosion, sediment flux, and deposition effects. This does not rename or attribute the control world's ordinary erosion to the cut. Exact logs, exported proof, and result bundle are under `/Users/scottopell/dev/crick-builds/live-erosion-build9-final`.

## Five-minute phone exploration

Do not coach a route and do not present a success condition.

1. Launch fresh. Ask what the person thinks the blue shape and brown/gravel field are, and where water is going.
2. Ask them to try changing the creek. Observe whether they discover tap or drag without being told exact cells.
3. After one stroke, ask what changed first (exposed lowered ground) and what changed as the live current continued (wet cells/direction).
4. Ask them to make a different route somewhere else. Repeated strokes should deepen a chosen path; there is no required answer.
5. Hold **2×** briefly, then release or drag away from it. The same creek should visibly run faster only while held and return to 1× afterward.
6. Save, dig again, then Resume. Confirm the separate digging state returns. Reset should return a fresh authored creek whose whole world immediately continues live.
7. Background and foreground. It should pause/save while inactive, resume at 1×, and never convert elapsed wall time into simulation work.
8. Open **Shape the Bend** from the menu and confirm the historical experience remains usable.
9. With VoiceOver, open selected-cell controls, move selection, and use **Dig selected cell**. The creek should be one useful described element rather than hundreds of noisy cells.
10. Check Reduce Motion, large text, portrait, and compact iPhone layout. Report clipping, illegible terrain/water contrast, heat, or confusing cause/effect.

Useful questions: “Where did you dig?”, “Where did water go afterward?”, “What would you try next?”, and “Did anything look like the one correct answer?” A problematic result is one where the person only detects change from tick text, mistakes the selected-cell outline for a goal, or sees an abstract heatmap rather than a gravel creek.

## Signing and distribution honesty

For historical build 7, `security find-identity -v -p codesigning` reported two valid local identities, including **Apple Development: Scott Opell (SAJR9U4DL2)**; the project team was `X2ULA6KJUN`. That build-7 archive succeeded using only the existing setup, without `-allowProvisioningUpdates`, credential/account changes, new profiles, or upload. Strict `codesign` verification passed. Its wildcard development profile expires 2027-07-06 and contains two provisioned-device entries; the paired Scott iPhone was confirmed eligible and build 7 was installed successfully. Device app inventory confirmed 0.1.0 (7). Build 9 performed none of these signing, archive, or device steps.

The build-9 durable artifact set contains final package/native/UI/simulator-Release logs, UI `.xcresult` evidence, and an explicit paired-proof `.xcresult` with exported same-tick cut/control screenshots and JSON. It intentionally contains no archive, iPhoneOS product, install, upload, or signing action. Earlier signed build-7 artifacts described above are historical and are not build-9 evidence.

There is no TestFlight or public upload and no claim of physical-device validation. A successful development-signed archive is phone-installable only on devices allowed by its embedded profile; it is not an App Store distribution artifact. Build 7 is installed on the paired Scott iPhone, but launch and hands-on comprehension remain for the user to verify.

## Current limitations

- This is coarse cardinal surface transfer, not calibrated hydraulics.
- There is no momentum, rainfall, placeable spoil, score, or objective. Erosion/sediment/deposition are deterministic game mechanics, not calibrated physical predictions.
- Valid schema-1 digging snapshots migrate to schema 2. Before the first overwrite, exact v1 bytes are retained once as a backup—even if the first write is a launch/background save before Resume; unsupported or corrupt hybrids are rejected atomically.
- Simulator evidence cannot establish physical-device touch feel, performance, battery use, or uncoached comprehension.
- The Canvas presentation intentionally exposes some cellular coarseness; evaluation should determine whether it still reads as creek and gravel rather than debug visualization.
