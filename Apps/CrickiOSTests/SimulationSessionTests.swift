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
