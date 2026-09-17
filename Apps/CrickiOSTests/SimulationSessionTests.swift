import CreekCore
import CreekRunner
import Foundation
import Testing
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
    #expect(abs((first ?? 0) - SurfaceWorld.excavationIncrement) < 1e-12)
    #expect(abs((second ?? 0) - 2 * SurfaceWorld.excavationIncrement) < 1e-12)
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
