# First playtest: 0.1.0 (1)

Updated 2026-09-05. Xcode 26.6 (17F113), iOS 26.5 SDK.

## Ready locally

- Signed Release archive succeeds: `/tmp/crick-beta-ready.xcarchive`.
- The archived app includes version `0.1.0`, build `1`, display name `Crick`, opaque app icon, generated launch/scene configuration, and declared iPhone/iPad orientations.
- Signing team `X2ULA6KJUN` is preserved in both `project.yml` and the checked-in Xcode project.
- All 20 Swift package tests and 8 app-session tests passed during this preparation.
- The unchanged interactive UI test now passes on iPhone 17 Pro / iOS 26.5, including rock placement, Advance 10, Save, Advance 1, and Resume.
- All 9 app/UI tests also pass on iPhone SE (3rd generation) / iOS 17.5 and iPad Pro 11-inch (M5) / iOS 26.5: 18 additional test runs, zero failures or skips.

The original UI failure ran in a legacy 320×480 application window on an iPhone 17 Pro. Adding launch/scene configuration and supported orientations made the unchanged test pass. No simulation code or test assertions were changed.

The beta icon is a reproducible CoreGraphics drawing; source: `scripts/generate-app-icon.swift`. Its checked-in 1024×1024 PNG has no alpha channel. Xcode's asset compiler generates the device renditions.

`ITSAppUsesNonExemptEncryption` is false: this slice stores snapshots locally, includes no remote service or third-party SDK, and implements no custom cryptography. Revisit this declaration if dependencies or networking change.

## Next: Xcode Cloud → your phone

The screenshot confirms Xcode Cloud setup, not a completed cloud archive or TestFlight upload. Local changes must reach the remote branch before Cloud can build them.

1. Use the remote branch containing these fixes in **Start Build**. Confirm the workflow uses `Crick.xcodeproj` and scheme `CrickiOS`.
2. Select Xcode 26.6 or a compatible version with Swift 6.3 or later. `Package.swift` requires Swift tools 6.3.
3. Include an **Archive** action for iOS. For a build that can later go to friends, select **TestFlight and App Store** as the distribution preparation. An internal-only build cannot later be used for external testing.
4. Include a **Test** action on an available iPhone simulator. The scheme contains app-session and UI tests.
5. In App Store Connect → the Crick app → **TestFlight**, create an internal group (for example, `First playtest`) with only your eligible App Store Connect account initially. Add a TestFlight internal-testing post-action to the Cloud workflow if you want successful archives assigned automatically, or assign the processed build manually.
6. Start the cloud build. Wait for Archive to succeed and for the build to finish processing in TestFlight. If it fails, inspect the first actual error in the failed action; a successful Build action alone is not the distribution gate.
7. Add the build to your internal group. Complete any requested test information or export-compliance questions. Install Apple's TestFlight app on your iPhone using the invited Apple Account, then install Crick.
8. Complete the phone check below before adding other testers.

Cloud can manage signing, but App Store Connect upload, processing, and installation are not yet verified. Cloud may assign its own build number; use the number shown on the processed build. Keep the marketing version `0.1.0` for this beta series.

Apple references: [Cloud distribution](https://developer.apple.com/documentation/xcode/distributing-your-xcode-cloud-builds-through-testflight), [distribution workflow](https://developer.apple.com/documentation/xcode/creating-a-workflow-that-builds-your-app-for-distribution), [test information](https://developer.apple.com/help/app-store-connect/test-a-beta-version/provide-test-information).

## Five-minute phone check

- Fresh launch: normal full-screen layout, baseline tick 0, no error.
- Tap a plus: a rock appears and tick stays 0.
- Advance 10: tick becomes 10 and the observed-change card appears.
- Save, Advance 1, Resume: tick goes 10 → 11 → 10 and the rock remains.
- Background/reopen: time does not advance itself. Relaunch starts fresh; Resume explicitly restores the saved creek.
- Rotate and scroll: all controls remain reachable. Check large text and VoiceOver. If retaining iPad support, check an iPad too.

The broader physical-device checklist and first-user questions remain in README.md. Touch, accessibility, heat/battery, and user understanding still need real-device evidence.

## Tester copy

Beta description:

> Crick is an early creek-tending simulation. Place rocks, advance time in fixed steps, and observe changes in water depth and flow. This first beta focuses on a small interactive creek and local Save/Resume.

What to Test:

> Explore without instructions first and tell us what you thought the colors, arrows, and controls meant. Place a rock, press Advance 10 a few times, and describe where water pools. Save, advance again, and Resume. Report confusing behavior, clipped controls, or crashes, including your device and iOS version. Time advances only when you press Advance; reopening starts a fresh creek until you press Resume.

Use your feedback email and review contact in App Store Connect. Friends outside your App Store Connect team require external testing and the first external build goes through TestFlight App Review. See [Apple's beta testing guide](https://developer.apple.com/tutorials/develop-in-swift/test-your-beta-app).

## Local verification artifacts

- Final archive: `/tmp/crick-beta-ready.xcarchive`
- Final archive log: `/tmp/crick-beta-ready-archive.log`
- Passing iPhone UI/app tests: `/tmp/crick-playtest-fixed-tests.xcresult`
- Core tests: `/tmp/crick-playtest-swift-test.log`
- Additional device tests: `/tmp/crick-playtest-device-coverage.xcresult`

These are local temporary artifacts, not uploaded builds.
