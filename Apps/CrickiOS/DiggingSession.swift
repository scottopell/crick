import CreekCore
import Foundation
import Observation

struct DiggingSnapshotEnvelope: Codable, Equatable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let kind: String
    let world: SurfaceWorld

    init(world: SurfaceWorld) {
        schemaVersion = Self.schemaVersion
        kind = "digging-surface"
        self.world = world
    }
}

enum DiggingSessionError: Error, Equatable {
    case unsupportedSnapshot
}

@MainActor
@Observable
final class DiggingSession {
    static let automaticTicks = 18
    static let observationTicks = 30

    private let snapshotStore: any SnapshotStoring
    private(set) var world: SurfaceWorld
    private(set) var canResume: Bool
    private(set) var message = "Drag through gravel to dig"
    private(set) var sceneSummary = "No patches lowered yet. Water follows the authored bend."
    var selectedCoordinate = SurfaceCoordinate(column: 8, row: 10)
    private var preDigWaterDepths: [Double]?
    private var pendingDugCoordinates: Set<SurfaceCoordinate> = []

    init(snapshotStore: any SnapshotStoring) {
        self.snapshotStore = snapshotStore
        world = DiggingExperimentTerrain.newWorld()
        canResume = snapshotStore.exists()
    }

    @discardableResult
    func excavate(_ coordinates: [SurfaceCoordinate]) -> Bool {
        var changed = false
        for coordinate in coordinates {
            let before = world.cells.map(\.waterDepth)
            if (try? world.excavate(coordinate)) ?? 0 > 0 {
                if preDigWaterDepths == nil { preDigWaterDepths = before }
                changed = true
                selectedCoordinate = coordinate
                pendingDugCoordinates.insert(coordinate)
            }
        }
        if changed {
            message = "Ground lowered — watch where water goes"
            sceneSummary = diggingSummary(newlyWet: nil)
        }
        return changed
    }

    func excavateSelected() -> [SurfaceWorld] {
        guard excavate([selectedCoordinate]) else { return [] }
        return advanceCaptured(count: Self.automaticTicks)
    }

    func advanceCaptured(count: Int = observationTicks) -> [SurfaceWorld] {
        guard count > 0 else { return [] }
        var frames: [SurfaceWorld] = []
        frames.reserveCapacity(count)
        for _ in 0..<count {
            guard world.step() else { break }
            frames.append(world)
        }
        if let before = preDigWaterDepths, !pendingDugCoordinates.isEmpty {
            let newlyWet = world.cells.indices.filter {
                before[$0] <= 0.001 && world.cells[$0].waterDepth > 0.004
            }
            let alongStroke = newlyWet.count { index in
                pendingDugCoordinates.contains(world.coordinate(for: index)!)
            }
            message = "Water flowed for \(frames.count) fixed ticks"
            sceneSummary = diggingSummary(
                newlyWet: (newlyWet.count, alongStroke),
                remainingWaterLips: world.dryExcavationBarriers().count
            )
            preDigWaterDepths = nil
            pendingDugCoordinates.removeAll(keepingCapacity: true)
        } else {
            message = "Water flowed for \(frames.count) fixed ticks"
        }
        return frames
    }

    func reset() {
        world = DiggingExperimentTerrain.newWorld()
        selectedCoordinate = SurfaceCoordinate(column: 8, row: 10)
        preDigWaterDepths = nil
        pendingDugCoordinates.removeAll(keepingCapacity: true)
        message = "Fresh gravel — drag to dig"
        sceneSummary = "No patches lowered yet. Water follows the authored bend."
    }

    func moveSelection(columns: Int, rows: Int) {
        let column = min(world.width - 2, max(1, selectedCoordinate.column + columns))
        let row = min(world.height - 2, max(1, selectedCoordinate.row + rows))
        selectedCoordinate = SurfaceCoordinate(column: column, row: row)
    }

    func excavationDepth(at coordinate: SurfaceCoordinate) -> Double? {
        guard let index = world.index(of: coordinate) else { return nil }
        return world.cells[index].excavationDepth
    }

    private func diggingSummary(
        newlyWet: (total: Int, alongStroke: Int)?,
        remainingWaterLips: Int? = nil
    ) -> String {
        let coordinate = selectedCoordinate
        let patchCount = pendingDugCoordinates.count
        let location = "near column \(coordinate.column + 1), row \(coordinate.row + 1)"
        let deepest = pendingDugCoordinates.compactMap(excavationDepth).max() ?? 0
        let increments = Int((deepest / SurfaceWorld.excavationIncrement).rounded())
        let depth = "up to \(increments) digging \(increments == 1 ? "increment" : "increments") deep"
        guard let newlyWet else {
            return "\(patchCount) dug \(patchCount == 1 ? "patch" : "patches") \(location), \(depth)."
        }
        let lipSummary = remainingWaterLips.map {
            " \($0) local \($0 == 1 ? "lip remains" : "lips remain") where visible water meets higher dug ground (which may contain shallow water below the visual threshold)."
        } ?? ""
        return "\(patchCount) dug \(patchCount == 1 ? "patch" : "patches") \(location), \(depth); water newly wet \(newlyWet.total) \(newlyWet.total == 1 ? "patch" : "patches"), including \(newlyWet.alongStroke) along the stroke.\(lipSummary)"
    }

    func save() throws {
        let envelope = DiggingSnapshotEnvelope(world: world)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try snapshotStore.save(try encoder.encode(envelope))
        canResume = true
        message = "Saved this digging creek"
    }

    func resume() throws {
        let envelope = try JSONDecoder().decode(
            DiggingSnapshotEnvelope.self,
            from: snapshotStore.load()
        )
        guard envelope.schemaVersion == DiggingSnapshotEnvelope.schemaVersion,
              envelope.kind == "digging-surface" else {
            throw DiggingSessionError.unsupportedSnapshot
        }
        let restored = try envelope.world.validated()
        world = restored
        selectedCoordinate = SurfaceCoordinate(
            column: min(world.width - 2, max(1, selectedCoordinate.column)),
            row: min(world.height - 2, max(1, selectedCoordinate.row))
        )
        message = "Resumed saved creek at tick \(world.tick)"
        preDigWaterDepths = nil
        pendingDugCoordinates.removeAll(keepingCapacity: true)
        let lowered = world.cells.count { $0.excavationDepth > 0.000_001 }
        sceneSummary = "Resumed at tick \(world.tick) with \(lowered) lowered patches."
    }
}

extension FileSnapshotStore {
    static func diggingApplicationSupport() throws -> Self {
        let manager = FileManager.default
        let directory = try manager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("Crick", isDirectory: true)
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        return Self(url: directory.appendingPathComponent("digging-surface-v1.json"))
    }
}
