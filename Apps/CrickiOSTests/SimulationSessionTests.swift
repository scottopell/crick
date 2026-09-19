import CreekCore
import CreekRunner
import Foundation
import SwiftUI
import Testing
import UIKit
import XCTest
@testable import CrickiOS

private final class MemorySnapshotStore: SnapshotStoring {
    var data: Data?
    func exists() -> Bool { data != nil }
    func save(_ data: Data) { self.data = data }
    func load() throws -> Data {
        guard let data else { throw CocoaError(.fileNoSuchFile) }
        return data
    }
}

private func point(for anchor: SIMD2<Float>, in viewport: CGSize) -> CGPoint {
    CGPoint(
        x: CGFloat((anchor.x + 1) * 0.5) * viewport.width,
        y: CGFloat((1 - anchor.y) * 0.5) * viewport.height
    )
}

@MainActor
@Test("Digging session captures fixed frames and restores its separate envelope")
func diggingSessionPersistence() throws {
    let store = MemorySnapshotStore()
    let session = DiggingSession(snapshotStore: store)
    let coordinate = SurfaceCoordinate(column: 7, row: 10)
    #expect(session.excavate([coordinate]))
    let lowered = session.world
    let frames = session.advanceCaptured(count: 18)
    #expect(frames.count == 18)
    #expect(frames.map(\.tick) == Array(1...18).map(UInt64.init))
    #expect(session.world == frames.last)
    try session.save()
    session.reset()
    #expect(session.world != frames.last)
    try session.resume()
    #expect(session.world == frames.last)
    #expect(session.world != lowered)
}

@MainActor
@Test("Digging session resumes the captured barrier fixture through its native envelope path")
func diggingSessionCapturedFixtureResume() throws {
    let fixture = try #require(Bundle(for: MemorySnapshotStore.self).url(
        forResource: "barrier-snapshot-tick-540",
        withExtension: "json"
    ))
    let data = try Data(contentsOf: fixture)
    let store = MemorySnapshotStore()
    store.data = data
    let expected = try JSONDecoder().decode(DiggingSnapshotEnvelope.self, from: data).world
    let session = DiggingSession(snapshotStore: store)

    #expect(session.canResume)
    try session.resume()
    #expect(session.world == expected)
    #expect(session.world.tick == 540)
    #expect(session.sceneSummary == "Resumed at tick 540 with 30 lowered patches.")
}

    @MainActor
    final class DiggingFixtureVisualProofTests: XCTestCase {
    func testExactCapturedBarrierBeforeAndAfterMeasuredLowerRouteFlow() throws {
    let fixture = try #require(Bundle(for: MemorySnapshotStore.self).url(
        forResource: "barrier-snapshot-tick-540",
        withExtension: "json"
    ))
    let originalData = try Data(contentsOf: fixture)
    let store = MemorySnapshotStore()
    store.data = originalData
    let session = DiggingSession(snapshotStore: store)
    try session.resume()

    let footprint = session.world.cells.indices.filter {
        session.world.cells[$0].excavationDepth > 0.000_001
    }.compactMap(session.world.coordinate)
    XCTAssertEqual(footprint.count, 30)
    XCTAssertFalse(session.world.dryExcavationBarriers().isEmpty)
    attachRenderedDigging(session: session, named: "Exact tick-540 fixture — visible barriers before")

    let initiallyWet = session.world.cells.map { $0.waterDepth > 0.004 }
    var measuredLowerRouteFlow = false
    var newlyWetFootprint = Set<SurfaceCoordinate>()

    func inspect(_ frames: [SurfaceWorld]) {
        for world in frames {
            if world.lastEdgeTransfers.contains(where: {
                $0.from == SurfaceCoordinate(column: 8, row: 20)
                    && $0.to == SurfaceCoordinate(column: 8, row: 21)
                    && $0.amount > 0
            }) {
                measuredLowerRouteFlow = true
            }
            for coordinate in footprint {
                let index = world.index(of: coordinate)!
                if !initiallyWet[index], world.cells[index].waterDepth > 0.004 {
                    newlyWetFootprint.insert(coordinate)
                }
            }
        }
    }

    for _ in 0..<3 {
        let start = try XCTUnwrap(footprint.first)
        let floor = try XCTUnwrap(session.cutFloor(startingAt: start))
        let alreadyLower = footprint.first { coordinate in
            let index = session.world.index(of: coordinate)!
            return session.world.cells[index].groundHeight < floor
        }
        let lowerBefore = alreadyLower.map { session.world.cells[session.world.index(of: $0)!].groundHeight }
        XCTAssertTrue(session.excavate(footprint, toFloor: floor))
        if let alreadyLower, let lowerBefore {
            XCTAssertEqual(
                session.world.cells[session.world.index(of: alreadyLower)!].groundHeight,
                lowerBefore,
                accuracy: 1e-12,
                "one captured gesture floor must never raise an already lower cell"
            )
        }
        inspect(session.advanceCaptured(count: DiggingSession.automaticTicks))
    }
    var observeActions = 0
    while !measuredLowerRouteFlow && observeActions < 15 {
        inspect(session.advanceCaptured(count: DiggingSession.observationTicks))
        observeActions += 1
    }

    XCTAssertTrue(measuredLowerRouteFlow, "three strokes must create actual flow across the captured lower route")
    XCTAssertFalse(newlyWetFootprint.isEmpty, "the exact captured footprint must gain visibly wet cells")
    XCTAssertLessThan(observeActions, 15, "lower-route flow must occur inside the bounded user Observe sequence")
    XCTAssertGreaterThanOrEqual(session.world.tick, 594)
    // Build 8 required repeated per-cell scoops. Build 9 intentionally cuts the
    // connected gesture to one captured floor, so the same route opens earlier.
    attachRenderedDigging(session: session, named: "Exact fixture — after three strokes and lower-route flow")
    XCTAssertEqual(try Data(contentsOf: fixture), originalData, "visual proof must not mutate its bundled fixture")
}

private func attachRenderedDigging(session: DiggingSession, named name: String) {
    let legacy = try! SimulationSession(snapshotStore: MemorySnapshotStore())
    let controller = UIHostingController(rootView: DiggingContentView(session: session, legacySession: legacy))
    let size = CGSize(width: 393, height: 852)
    controller.view.bounds = CGRect(origin: .zero, size: size)
    controller.view.backgroundColor = .black
    controller.view.setNeedsLayout()
    controller.view.layoutIfNeeded()
    let renderer = UIGraphicsImageRenderer(size: size)
    let image = renderer.image { _ in
        controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
    }
    let attachment = XCTAttachment(image: image)
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
}
}

@MainActor
final class CausalErosionVisualProofTests: XCTestCase {
    func testPairedCutAndUncutWorldsRenderAtSameTickWithMeasuredDifferences() throws {
        let initial = DiggingExperimentTerrain.newWorld(settlingTicks: 0)
        var uncut = initial
        var cutWorld = initial
        let cut = SurfaceCoordinate(column: 6, row: 5)
        XCTAssertEqual(uncut.totalCarriedSediment, 0, accuracy: 1e-12)
        XCTAssertEqual(cutWorld.totalCarriedSediment, 0, accuracy: 1e-12)
        let removed = try cutWorld.excavate(cut, toFloor: cutWorld.cutFloor(startingAt: cut))

        struct Measures {
            var erosion: [Double]
            var deposition: [Double]
            var flux: [Double]
        }
        func run(_ world: inout SurfaceWorld) -> Measures {
            var value = Measures(
                erosion: .init(repeating: 0, count: world.cells.count),
                deposition: .init(repeating: 0, count: world.cells.count),
                flux: .init(repeating: 0, count: world.cells.count)
            )
            for _ in 0..<1_200 {
                let water = world.cells.map(\.waterDepth)
                let sediment = world.cells.map(\.sediment)
                let ground = world.cells.map(\.groundHeight)
                XCTAssertTrue(world.step())
                for transfer in world.lastEdgeTransfers where transfer.to.row > transfer.from.row {
                    let donor = world.index(of: transfer.from)!
                    let receiver = world.index(of: transfer.to)!
                    if water[donor] > 0 {
                        value.flux[receiver] += sediment[donor] * transfer.amount / water[donor]
                    }
                }
                for index in world.cells.indices {
                    let delta = world.cells[index].groundHeight - ground[index]
                    if delta < 0 { value.erosion[index] -= delta }
                    if delta > 0 { value.deposition[index] += delta }
                }
            }
            return value
        }
        let baseline = run(&uncut)
        let intervention = run(&cutWorld)
        let erosionIndex = cutWorld.index(of: .init(column: 6, row: 6))!
        let fluxIndex = cutWorld.index(of: .init(column: 5, row: 6))!
        let depositionIndex = cutWorld.index(of: .init(column: 5, row: 6))!
        let erosionEffect = intervention.erosion[erosionIndex] - baseline.erosion[erosionIndex]
        let fluxEffect = intervention.flux[fluxIndex] - baseline.flux[fluxIndex]
        let depositionEffect = intervention.deposition[depositionIndex] - baseline.deposition[depositionIndex]
        XCTAssertEqual(uncut.tick, cutWorld.tick)
        XCTAssertEqual(cutWorld.tick, 1_200)
        XCTAssertGreaterThan(erosionEffect, 0)
        XCTAssertGreaterThan(fluxEffect, 0)
        XCTAssertGreaterThan(depositionEffect, 0)
        XCTAssertEqual(cutWorld.materialLedger.excavated - uncut.materialLedger.excavated, removed, accuracy: 1e-12)

        attachRenderedWorld(uncut, metadata: "CONTROL · uncut · t1200", named: "Paired causal control — uncut at tick 1200")
        attachRenderedWorld(cutWorld, metadata: "INTERVENTION · floor cut (6,5) · t1200", named: "Paired causal intervention — cut at tick 1200")
        let evidence: [String: Any] = [
            "initial_worlds_equal": true,
            "initial_sediment_each": 0,
            "tick_each": 1_200,
            "cut": ["column": cut.column, "row": cut.row, "removed": removed],
            "erosion_cut_minus_control": erosionEffect,
            "downstream_sediment_flux_cut_minus_control": fluxEffect,
            "deposition_cut_minus_control": depositionEffect,
            "excavated_ledger_cut_minus_control": cutWorld.materialLedger.excavated - uncut.materialLedger.excavated,
            "exported_ledger_cut_minus_control": cutWorld.materialLedger.exported - uncut.materialLedger.exported,
        ]
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: evidence, options: [.prettyPrinted, .sortedKeys]), uniformTypeIdentifier: "public.json")
        attachment.name = "paired-causal-evidence.json"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func attachRenderedWorld(_ world: SurfaceWorld, metadata: String, named name: String) {
        let root = VStack(spacing: 6) {
            Text(metadata)
                .font(.caption2.monospaced())
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
            DiggingSurfaceView(
                world: world,
                selectedCoordinate: nil,
                reduceMotion: true,
                interactionEnabled: false,
                accessibilitySummary: metadata,
                onDigCells: { _, _ in },
                onGestureEnded: {}
            )
        }
        .background(Color(red: 0.055, green: 0.072, blue: 0.045))
        .preferredColorScheme(.dark)
        let controller = UIHostingController(rootView: root)
        let size = CGSize(width: 393, height: 852)
        controller.view.bounds = CGRect(origin: .zero, size: size)
        controller.view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(size: size).image { _ in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

@MainActor
@Test("Live observation finalizes after eighteen physical ticks at either pulse factor")
func liveObservationUsesPhysicalTicks() {
    let coordinate = SurfaceCoordinate(column: 7, row: 10)
    let one = DiggingSession(snapshotStore: MemorySnapshotStore())
    let two = DiggingSession(snapshotStore: MemorySnapshotStore())
    #expect(one.excavate([coordinate]))
    #expect(two.excavate([coordinate]))
    let pending = one.sceneSummary

    for _ in 0..<17 { _ = one.advanceLive(steps: 1) }
    _ = two.advanceLive(steps: 2)
    for _ in 0..<7 { _ = two.advanceLive(steps: 2) }
    _ = two.advanceLive(steps: 1)
    #expect(one.sceneSummary == pending)
    #expect(two.sceneSummary == pending)

    _ = one.advanceLive(steps: 1)
    _ = two.advanceLive(steps: 1)
    #expect(one.world == two.world)
    #expect(one.sceneSummary == two.sceneSummary)
    #expect(one.sceneSummary != pending)
    #expect(one.message == "Water responded for 18 physical ticks")
    #expect(two.message == "Water responded for 18 physical ticks")
}

@Test("Live clock hold, release, and ineligible dialog pulses are deterministic")
func liveClockStateDriver() {
    var clock = LiveClockState()
    #expect(clock.stepsForPulse(isEligible: true) == 1)
    clock.setHoldingTwoX(true)
    #expect(clock.stepsForPulse(isEligible: true) == 2)
    clock.setHoldingTwoX(false)
    #expect(clock.stepsForPulse(isEligible: true) == 1)
    clock.setHoldingTwoX(true)
    #expect(clock.stepsForPulse(isEligible: false) == 0)
    #expect(!clock.isHoldingTwoX)
    #expect(clock.stepsForPulse(isEligible: true) == 1)
}

@MainActor
@Test("Live speed partitions identical physical ticks and release returns to one")
func liveSpeedTickPartition() {
    let one = DiggingSession(snapshotStore: MemorySnapshotStore())
    let two = DiggingSession(snapshotStore: MemorySnapshotStore())
    for _ in 0..<20 { _ = one.advanceLive(steps: 1) }
    for _ in 0..<10 { _ = two.advanceLive(steps: 2) }
    #expect(one.world == two.world)
    // Release semantics are represented by the next scheduler pulse returning to one.
    _ = two.advanceLive(steps: 1)
    #expect(two.world.tick == 21)
}

@MainActor
@Test("No elapsed background interval advances live authority")
func noElapsedBackgroundCatchup() async throws {
    let session = DiggingSession(snapshotStore: MemorySnapshotStore())
    let tick = session.world.tick
    try await Task.sleep(for: .milliseconds(20))
    #expect(session.world.tick == tick)
    _ = session.advanceLive(steps: 1)
    #expect(session.world.tick == tick + 1)
}

@MainActor
@Test("Repeated digging stroke increases authoritative excavation depth")
func repeatedDiggingDepth() {
    let session = DiggingSession(snapshotStore: MemorySnapshotStore())
    let stroke = [
        SurfaceCoordinate(column: 7, row: 7),
        SurfaceCoordinate(column: 8, row: 9),
        SurfaceCoordinate(column: 9, row: 10),
    ]
    #expect(session.excavate(stroke))
    let first = session.excavationDepth(at: stroke[1])
    #expect(session.excavate(stroke))
    let second = session.excavationDepth(at: stroke[1])
    #expect((first ?? 0) > 0)
    #expect((second ?? 0) > (first ?? 0))
    #expect(abs(((second ?? 0) - (first ?? 0)) - SurfaceWorld.excavationIncrement) < 1e-12)
    let commonFloor = session.world.cells[session.world.index(of: stroke[0])!].groundHeight
    #expect(session.world.cells[session.world.index(of: stroke[1])!].groundHeight == commonFloor)
    #expect(session.world.cells[session.world.index(of: stroke[2])!].groundHeight == commonFloor)
}

@MainActor
@Test("Corrupt digging snapshot is atomically rejected")
func corruptDiggingResumeIsAtomic() throws {
    let store = MemorySnapshotStore()
    let session = DiggingSession(snapshotStore: store)
    #expect(session.excavate([SurfaceCoordinate(column: 7, row: 10)]))
    _ = session.advanceCaptured(count: 3)
    let live = session.world
    try session.save()

    var envelope = try #require(JSONSerialization.jsonObject(with: store.data!) as? [String: Any])
    var world = try #require(envelope["world"] as? [String: Any])
    var source = try #require(world["source"] as? [String: Any])
    source["column"] = -1
    world["source"] = source
    envelope["world"] = world
    store.data = try JSONSerialization.data(withJSONObject: envelope)

    #expect(throws: Error.self) { try session.resume() }
    #expect(session.world == live)
}

@MainActor
@Test("Digging resume rejects both envelope/world version hybrids atomically")
func diggingEnvelopeWorldHybridsRejected() throws {
    let store = MemorySnapshotStore()
    let session = DiggingSession(snapshotStore: store)
    try session.save()
    let live = session.world
    let current = try #require(JSONSerialization.jsonObject(with: store.data!) as? [String: Any])

    var v1EnvelopeV2World = current
    v1EnvelopeV2World["schemaVersion"] = 1
    store.data = try JSONSerialization.data(withJSONObject: v1EnvelopeV2World)
    #expect(throws: DiggingSessionError.unsupportedSnapshot) { try session.resume() }
    #expect(session.world == live)

    var v2EnvelopeV1World = current
    var legacyWorld = try #require(v2EnvelopeV1World["world"] as? [String: Any])
    legacyWorld["schemaVersion"] = 1
    legacyWorld["compatibilityID"] = SurfaceWorld.legacyCompatibilityID
    legacyWorld.removeValue(forKey: "materialLedger")
    var legacyCells = try #require(legacyWorld["cells"] as? [[String: Any]])
    for index in legacyCells.indices { legacyCells[index].removeValue(forKey: "sediment") }
    legacyWorld["cells"] = legacyCells
    v2EnvelopeV1World["world"] = legacyWorld
    store.data = try JSONSerialization.data(withJSONObject: v2EnvelopeV1World)
    #expect(throws: DiggingSessionError.unsupportedSnapshot) { try session.resume() }
    #expect(session.world == live)
}

@MainActor
@Test("First migrated file save retains exact v1 bytes and never overwrites backup")
func migratedFileBackupRetainsOriginalBytes() throws {
    let fixture = try #require(Bundle(for: MemorySnapshotStore.self).url(
        forResource: "barrier-snapshot-tick-540",
        withExtension: "json"
    ))
    let original = try Data(contentsOf: fixture)
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("digging.json")
    try original.write(to: url)
    let session = DiggingSession(snapshotStore: FileSnapshotStore(url: url))

    try session.resume()
    try session.save()
    let backup = url.deletingPathExtension().appendingPathExtension("v1-backup.json")
    #expect(try Data(contentsOf: backup) == original)
    let firstBackup = try Data(contentsOf: backup)

    #expect(session.excavate([SurfaceCoordinate(column: 7, row: 10)]))
    try session.save()
    #expect(try Data(contentsOf: backup) == firstBackup)
    #expect(try Data(contentsOf: url) != original)
}

@MainActor
@Test("Launch or background save preserves exact v1 file without resume")
func saveWithoutResumePreservesLegacyBytes() throws {
    let fixture = try #require(Bundle(for: MemorySnapshotStore.self).url(
        forResource: "barrier-snapshot-tick-540",
        withExtension: "json"
    ))
    let original = try Data(contentsOf: fixture)
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("digging.json")
    try original.write(to: url)

    // This is the launch-created fresh session followed directly by the same save
    // used by backgrounding; no resume or migration flag primes preservation.
    let session = DiggingSession(snapshotStore: FileSnapshotStore(url: url))
    try session.save()

    let backup = url.deletingPathExtension().appendingPathExtension("v1-backup.json")
    #expect(try Data(contentsOf: backup) == original)
    let current = try JSONDecoder().decode(DiggingSnapshotEnvelope.self, from: Data(contentsOf: url))
    #expect(current.schemaVersion == DiggingSnapshotEnvelope.schemaVersion)
    #expect(current.world.originalSchemaVersion == SurfaceWorld.schemaVersion)
}

@MainActor
@Test("Debug export replays exact authority and metadata without ticking or overwriting save")
func debugStateExactReadOnlyExport() throws {
    let store = MemorySnapshotStore()
    store.data = Data("untouched saved phone state".utf8)
    let session = DiggingSession(snapshotStore: store)
    let coordinate = SurfaceCoordinate(column: 7, row: 10)
    #expect(session.excavate([coordinate]))
    _ = session.advanceCaptured(count: 7)
    session.moveSelection(columns: 3, rows: -2)

    let worldBefore = session.world
    let selectionBefore = session.selectedCoordinate
    let saveBefore = store.data
    let data = try session.debugStateData(appVersion: "0.1.0-test", buildNumber: "10-test")
    let replay = try DiggingDebugStateCodec.decode(data)

    #expect(replay.formatIdentifier == DiggingDebugStateEnvelope.formatIdentifier)
    #expect(replay.formatVersion == DiggingDebugStateEnvelope.formatVersion)
    #expect(replay.provenance.appVersion == "0.1.0-test")
    #expect(replay.provenance.buildNumber == "10-test")
    #expect(replay.provenance.worldCompatibilityID == SurfaceWorld.compatibilityID)
    #expect(replay.selectedCell == selectionBefore)
    #expect(replay.snapshot.schemaVersion == DiggingSnapshotEnvelope.schemaVersion)
    #expect(try replay.restoredWorld() == worldBefore)
    #expect(session.world == worldBefore)
    #expect(session.world.tick == worldBefore.tick)
    #expect(session.selectedCoordinate == selectionBefore)
    #expect(store.data == saveBefore)
    #expect(data.count <= DiggingDebugStateCodec.maximumByteCount)
    #expect(!data.contains(0x0A), "clipboard JSON stays compact")
}

@MainActor
@Test("Debug replay exports migrated authority in the current nested schema without altering legacy bytes")
func debugStateMigratedReplay() throws {
    let fixture = try #require(Bundle(for: MemorySnapshotStore.self).url(
        forResource: "barrier-snapshot-tick-540",
        withExtension: "json"
    ))
    let original = try Data(contentsOf: fixture)
    let store = MemorySnapshotStore()
    store.data = original
    let session = DiggingSession(snapshotStore: store)
    try session.resume()
    let migratedAuthority = session.world

    let data = try session.debugStateData(appVersion: "0.1.0", buildNumber: "10")
    let replay = try DiggingDebugStateCodec.decode(data)
    let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let snapshot = try #require(json["snapshot"] as? [String: Any])
    let world = try #require(snapshot["world"] as? [String: Any])

    #expect(snapshot["schemaVersion"] as? Int == DiggingSnapshotEnvelope.schemaVersion)
    #expect(world["schemaVersion"] as? Int == SurfaceWorld.schemaVersion)
    #expect(world["compatibilityID"] as? String == SurfaceWorld.compatibilityID)
    // A migrated in-memory world retains its original schema provenance solely so
    // the outer envelope can reject hybrids. Encoded authority is canonical v2;
    // compare those exact bytes rather than that non-encoded provenance marker.
    #expect(
        try DiggingJSONCodec.encode(replay.snapshot)
            == DiggingJSONCodec.encode(DiggingSnapshotEnvelope(world: migratedAuthority))
    )
    #expect(try replay.restoredWorld().tick == migratedAuthority.tick)
    #expect(store.data == original)
}

@Test("Debug replay rejects input beyond its explicit bound")
func debugStateInputBound() {
    let oversized = Data(repeating: 0x20, count: DiggingDebugStateCodec.maximumByteCount + 1)
    #expect(throws: DiggingSessionError.unsupportedDebugState) {
        _ = try DiggingDebugStateCodec.decode(oversized)
    }
}

@Test("Disabling an interrupted digging gesture resets transient brush state")
func interruptedDiggingBrushReset() {
    var brush = DiggingBrushState()
    let first = SurfaceCoordinate(column: 7, row: 10)
    let second = SurfaceCoordinate(column: 8, row: 10)

    #expect(brush.takeFresh([first, second]) == [first, second])
    brush.previousCoordinate = second
    #expect(!brush.touched.isEmpty)

    // The view calls this seam when interactionEnabled changes to false.
    brush.reset()
    #expect(brush.touched.isEmpty)
    #expect(brush.previousCoordinate == nil)
    #expect(brush.takeFresh([first]) == [first])
}

@MainActor
@Test("Interrupted excavation remains safe without implicit flow")
func interruptedDiggingDoesNotFlow() {
    let session = DiggingSession(snapshotStore: MemorySnapshotStore())
    let coordinate = SurfaceCoordinate(column: 7, row: 10)
    #expect(session.excavate([coordinate]))
    let tick = session.world.tick
    let depth = session.excavationDepth(at: coordinate)
    // Models a cancelled/disabled gesture: onGestureEnded is intentionally not sent.
    #expect(session.world.tick == tick)
    #expect(abs((depth ?? 0) - SurfaceWorld.excavationIncrement) < 1e-12)
    #expect((try? session.world.validated()) != nil)
}

@MainActor
@Test("Selected-cell accessibility path stays inside the safe digging boundary")
func selectedCellBoundary() {
    let session = DiggingSession(snapshotStore: MemorySnapshotStore())
    for _ in 0..<100 {
        session.moveSelection(columns: -1, rows: -1)
    }
    #expect(session.selectedCoordinate == SurfaceCoordinate(column: 1, row: 1))
    for _ in 0..<100 {
        session.moveSelection(columns: 1, rows: 1)
    }
    #expect(session.selectedCoordinate == SurfaceCoordinate(
        column: session.world.width - 2,
        row: session.world.height - 2
    ))
}

@Test("Surface screen and map coordinates round-trip")
func surfaceMapCoordinateRoundTrip() {
    let layout = SurfaceMapLayout(width: 20, height: 26, viewport: CGSize(width: 390, height: 610))
    for row in 0..<26 {
        for column in 0..<20 {
            let coordinate = SurfaceCoordinate(column: column, row: row)
            let center = layout.center(of: coordinate)
            #expect(center != nil)
            #expect(layout.coordinate(at: center!) == coordinate)
        }
    }
    #expect(layout.coordinate(at: CGPoint(x: -1, y: -1)) == nil)
}

// Shape the Bend (4): eligible picking excludes the outlet and occupied seat.
@Test("Metal creek picking accepts only eligible authored stone seats")
func creekPickingEligibility() {
    let viewport = CGSize(width: 390, height: 600)
    let anchors = CreekLayout.anchors(count: 6)
    let eligible = [0, 1, 2, 4]

    for index in eligible {
        #expect(CreekPicking.cell(
            at: point(for: anchors[index], in: viewport),
            viewport: viewport,
            eligibleCells: eligible,
            cellCount: 6
        ) == index)
    }
    #expect(CreekPicking.cell(
        at: point(for: anchors[3], in: viewport),
        viewport: viewport,
        eligibleCells: eligible,
        cellCount: 6
    ) == nil)
    #expect(CreekPicking.cell(
        at: point(for: anchors[5], in: viewport),
        viewport: viewport,
        eligibleCells: eligible,
        cellCount: 6
    ) == nil)
}

// Shape the Bend (5): depth-to-width calibration has no old saturation cap.
@Test("Water width remains monotonic beyond the former depth cap")
func monotonicWaterWidth() {
    let depths = [0.0, 0.12, 0.34, 0.50, 0.80]
    let widths = depths.map(CreekMesh.calibratedWaterWidth)
    #expect(zip(widths, widths.dropFirst()).allSatisfy(<))
}

@MainActor
@Test("Game session starts with authoritative flowing objective and effective seats")
func gameSessionStart() throws {
    let session = try SimulationSession(snapshotStore: MemorySnapshotStore())
    #expect(session.projection.scenarioName == "shape-the-bend")
    #expect(session.projection.tick == 0)
    #expect(session.projection.waterTransfers.count == 5)
    #expect(session.projection.poolObjective?.status == .gathering)
    #expect(session.eligibleStoneCells == [0, 1, 2, 3, 4])
}

// Shape the Bend (1): a commit synchronously produces exactly one immutable
// projection after each of twenty actual authoritative fixed ticks.
@MainActor
@Test("Attempt commits exactly twenty real per-tick projections")
func actualAttemptFrames() throws {
    let session = try SimulationSession(snapshotStore: MemorySnapshotStore())
    try session.placeRock(cell: 2)
    let placed = session.projection

    let frames = try session.commitShapeTheBendAttempt()

    #expect(frames.count == 20)
    #expect(frames.map(\.tick) == Array(1...20).map(UInt64.init))
    #expect(frames.allSatisfy { $0.cells.count == placed.cells.count })
    #expect(frames[0].cells != frames[19].cells)
    #expect(frames[0].rockEffect?.elapsedTicks == 1)
    #expect(frames[19].rockEffect?.elapsedTicks == 20)
    #expect(session.projection == frames[19])
    #expect(session.projection.tick == placed.tick + SimulationSession.attemptTicks)
    #expect(session.hasCommittedAttempt)
}

@MainActor
@Test("Comparison captures actual flow before first intervention and retry seam")
func comparisonBeforeIntegrity() throws {
    let session = try SimulationSession(snapshotStore: MemorySnapshotStore())
    let initial = session.projection
    try session.placeRock(cell: 0)
    #expect(session.comparisonBeforeProjection == initial)

    _ = try session.commitShapeTheBendAttempt()
    let evolved = session.projection
    try session.tryAnotherSpot()
    #expect(session.comparisonBeforeProjection?.tick == evolved.tick)
    #expect(session.comparisonBeforeProjection?.cells == evolved.cells)
    #expect(session.comparisonBeforeProjection?.waterTransfers == evolved.waterTransfers)
    try session.placeRock(cell: 2)
    #expect(session.comparisonBeforeProjection?.tick == evolved.tick)
    #expect(session.comparisonBeforeProjection?.cells == evolved.cells)
    #expect(session.comparisonBeforeProjection?.waterTransfers == evolved.waterTransfers)
    let frames = try session.commitShapeTheBendAttempt()

    #expect(frames.first?.tick == evolved.tick + 1)
    #expect(session.projection.tick == 40)
}

@MainActor
@Test("Foam integrator uses authoritative speed and crosses boundaries exactly")
func foamTracerSourceAndPath() throws {
    let session = try SimulationSession(snapshotStore: MemorySnapshotStore())
    let projection = session.projection
    let metrics = CreekTracer.speedMetrics(for: projection)
    let target = try #require(projection.poolObjective?.targetCell)
    #expect(metrics[target] == projection.poolObjective?.calmness)
    #expect(metrics[target] == projection.poolObjective!.transfer / projection.poolObjective!.depth)

    // The first speed reaches the 0.2 boundary; all remaining duration uses
    // the next segment's doubled metric and lands exactly on 0.4.
    let crossed = CreekTracer.advancedProgress(
        from: 0.195,
        duration: 0.25,
        metrics: [1, 2, 1, 1, 1]
    )
    #expect(abs(crossed - 0.4) < 0.000_01)

    // 7 * (1 / 11) divides just below 7 in Float. An exact boundary must
    // select segment 7 rather than returning early from zero-speed segment 6.
    var boundaryMetrics = Array(repeating: 0.0, count: 11)
    boundaryMetrics[7] = 1
    let segmentWidth: Float = 1 / 11
    let exactBoundary = 7 * segmentWidth
    let advancedFromBoundary = CreekTracer.advancedProgress(
        from: exactBoundary,
        duration: 0.1,
        metrics: boundaryMetrics
    )
    #expect(advancedFromBoundary > exactBoundary)

    let progress = CreekTracer.seeds
    let beforePackets = CreekTracer.packets(
        projection: projection,
        progresses: progress,
        reduceMotion: false
    )
    try session.placeRock(cell: 2)
    let afterPackets = CreekTracer.packets(
        projection: session.projection,
        progresses: progress,
        reduceMotion: false
    )
    #expect(beforePackets.map(\.position) == afterPackets.map(\.position))

    let staticPackets = CreekTracer.packets(
        projection: projection,
        progresses: progress,
        reduceMotion: true
    )
    #expect(staticPackets.count == beforePackets.count * 2)
    for index in progress.indices {
        let expected = CreekTracer.advancedProgress(
            from: progress[index],
            duration: CreekTracer.presentationInterval,
            metrics: metrics
        )
        let expectedPacket = CreekTracer.packets(
            projection: projection,
            progresses: [expected],
            reduceMotion: false
        )[0]
        #expect(staticPackets[index * 2].mark == .start)
        #expect(staticPackets[index * 2 + 1].mark == .end)
        #expect(staticPackets[index * 2 + 1].position == expectedPacket.position)
    }
}

// Shape the Bend (3): retry preserves the evolved reach and requires a new
// placement before another bounded experiment.
@MainActor
@Test("Try another spot keeps the evolved reach for an informed retry")
func retryKeepsEvolvedReach() throws {
    let session = try SimulationSession(snapshotStore: MemorySnapshotStore())
    try session.placeRock(cell: 3)
    _ = try session.commitShapeTheBendAttempt()
    let evolved = session.projection

    try session.tryAnotherSpot()

    #expect(session.projection == evolved)
    #expect(session.projection.tick == 20)
    #expect(!session.hasCommittedAttempt)
    #expect(!session.attemptClosed)
    #expect(!session.canCommitAttempt)
    #expect(session.eligibleStoneCells == [0, 1, 2, 4])

    try session.placeRock(cell: 2)
    #expect(session.canCommitAttempt)
    let retried = try session.commitShapeTheBendAttempt()
    #expect(retried.first?.tick == 21)
    #expect(retried.last?.tick == 40)
}

@MainActor
@Test("Attempt progress is relative on an evolved-reach retry")
func attemptRelativeProgress() throws {
    let session = try SimulationSession(snapshotStore: MemorySnapshotStore())
    try session.placeRock(cell: 4)
    _ = try session.commitShapeTheBendAttempt()
    try session.tryAnotherSpot()
    try session.placeRock(cell: 2)
    let frames = try session.commitShapeTheBendAttempt()

    #expect(session.attemptElapsedTicks(for: frames.first!) == 1)
    #expect(session.attemptElapsedTicks(for: frames.last!) == 20)
}


// Shape the Bend (3): Keep retains final authority and closes mutation paths.
@MainActor
@Test("Keep retains final projection and closes the attempt")
func keepRetainsFinal() throws {
    let session = try SimulationSession(snapshotStore: MemorySnapshotStore())
    try session.placeRock(cell: 2)
    _ = try session.commitShapeTheBendAttempt()
    let final = session.projection

    try session.keepCreek()

    #expect(session.projection == final)
    #expect(session.attemptClosed)
    #expect(throws: ShapeTheBendAttemptError.attemptClosed) {
        try session.placeRock(cell: 3)
    }
    #expect(throws: ShapeTheBendAttemptError.attemptClosed) {
        _ = try session.commitShapeTheBendAttempt()
    }
    #expect(session.projection == final)
}

@MainActor
@Test("A near miss cannot be kept through the session boundary")
func failedAttemptCannotBeKept() throws {
    let session = try SimulationSession(snapshotStore: MemorySnapshotStore())
    try session.placeRock(cell: 4)
    _ = try session.commitShapeTheBendAttempt()

    #expect(session.projection.poolObjective?.status == .deepButQuick)
    #expect(throws: ShapeTheBendAttemptError.objectiveNotHolding) {
        try session.keepCreek()
    }
    #expect(!session.attemptClosed)
}

// Shape the Bend (4): app commands enforce eligibility independent of UI.
@MainActor
@Test("Session rejects outlet and occupied seats")
func sessionEligibility() throws {
    let session = try SimulationSession(snapshotStore: MemorySnapshotStore())
    #expect(throws: ShapeTheBendAttemptError.ineligibleCell(5)) {
        try session.placeRock(cell: 5)
    }
    try session.placeRock(cell: 3)
    #expect(session.eligibleStoneCells == [0, 1, 2, 4])
    #expect(throws: ShapeTheBendAttemptError.ineligibleCell(3)) {
        try session.placeRock(cell: 3)
    }
}

@MainActor
@Test("Resume is unavailable until a snapshot exists")
func resumeAvailability() throws {
    let store = MemorySnapshotStore()
    let session = try SimulationSession(snapshotStore: store)
    #expect(!session.canResume)
    try session.save()
    #expect(session.canResume)
}

@MainActor
@Test("Snapshot persistence restores exact projected state")
func saveResume() throws {
    let store = MemorySnapshotStore()
    let session = try SimulationSession(snapshotStore: store)
    try session.placeRock(cell: 2)
    try session.save()
    let saved = session.projection
    _ = try session.commitShapeTheBendAttempt()
    #expect(session.projection != saved)

    try session.resume()

    #expect(session.projection == saved)
    #expect(!session.hasCommittedAttempt)
    #expect(!session.attemptClosed)
}

@MainActor
@Test("Comparison snapshot round-trips with committed attempt")
func comparisonSnapshotRoundTrip() throws {
    let store = MemorySnapshotStore()
    let session = try SimulationSession(snapshotStore: store)
    let before = session.projection
    try session.placeRock(cell: 2)
    _ = try session.commitShapeTheBendAttempt()
    try session.save()
    try session.load(BuiltInScenarios.shapeTheBend)

    try session.resume()

    #expect(session.comparisonBeforeProjection == before)
    #expect(session.hasCommittedAttempt)
}

@MainActor
@Test("Legacy snapshot without comparison restores with comparison unavailable")
func legacySnapshotWithoutComparison() throws {
    let store = MemorySnapshotStore()
    let session = try SimulationSession(snapshotStore: store)
    try session.placeRock(cell: 2)
    _ = try session.commitShapeTheBendAttempt()
    try session.save()
    var json = try #require(JSONSerialization.jsonObject(with: store.data!) as? [String: Any])
    json.removeValue(forKey: "comparisonBefore")
    store.data = try JSONSerialization.data(withJSONObject: json)

    try session.resume()

    #expect(session.comparisonBeforeProjection == nil)
    #expect(session.hasCommittedAttempt)
}

@MainActor
@Test("Corrupt comparison snapshot is rejected without replacing live state")
func corruptComparisonSnapshotRejected() throws {
    let store = MemorySnapshotStore()
    let session = try SimulationSession(snapshotStore: store)
    try session.placeRock(cell: 2)
    _ = try session.commitShapeTheBendAttempt()
    try session.save()
    try session.load(BuiltInScenarios.shapeTheBend)
    let live = session.projection
    var json = try #require(JSONSerialization.jsonObject(with: store.data!) as? [String: Any])
    var comparison = try #require(json["comparisonBefore"] as? [String: Any])
    comparison["schemaVersion"] = 999
    json["comparisonBefore"] = comparison
    store.data = try JSONSerialization.data(withJSONObject: json)

    #expect(throws: Error.self) { try session.resume() }
    #expect(session.projection == live)
    #expect(session.comparisonBeforeProjection == nil)
}

@MainActor
@Test("Comparison with impossible tick ordering is rejected")
func comparisonTickOrderingRejected() throws {
    let store = MemorySnapshotStore()
    let session = try SimulationSession(snapshotStore: store)
    try session.placeRock(cell: 2)
    _ = try session.commitShapeTheBendAttempt()
    try session.save()
    let live = session.projection
    var json = try #require(JSONSerialization.jsonObject(with: store.data!) as? [String: Any])
    var comparison = try #require(json["comparisonBefore"] as? [String: Any])
    var state = try #require(comparison["state"] as? [String: Any])
    state["tick"] = 19
    comparison["state"] = state
    json["comparisonBefore"] = comparison
    store.data = try JSONSerialization.data(withJSONObject: json)

    #expect(throws: ShapeTheBendAttemptError.comparisonSnapshotMismatch) {
        try session.resume()
    }
    #expect(session.projection == live)
}

@MainActor
@Test("Malformed resume preserves current authoritative projection")
func malformedResumePreservesState() throws {
    let store = MemorySnapshotStore()
    store.data = Data("not a snapshot".utf8)
    let session = try SimulationSession(snapshotStore: store)
    try session.placeRock(cell: 2)
    let before = session.projection

    #expect(throws: Error.self) { try session.resume() }
    #expect(session.projection == before)
    #expect(session.canResume)
}

@MainActor
@Test("Resume rejects selected-stone metadata that disagrees with authority")
func mismatchedRockMetadataIsRejected() throws {
    let store = MemorySnapshotStore()
    let session = try SimulationSession(snapshotStore: store)
    try session.placeRock(cell: 2)
    try session.save()
    let before = session.projection

    var json = try #require(JSONSerialization.jsonObject(with: store.data!) as? [String: Any])
    json["selectedRockCell"] = 3
    store.data = try JSONSerialization.data(withJSONObject: json)

    #expect(throws: ShapeTheBendAttemptError.snapshotRockMismatch) {
        try session.resume()
    }
    #expect(session.projection == before)
}
