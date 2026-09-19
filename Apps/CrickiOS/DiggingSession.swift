import CreekCore
import Foundation
import Observation

struct DiggingSnapshotEnvelope: Codable, Equatable {
    static let schemaVersion = 2
    let schemaVersion: Int
    let kind: String
    let world: SurfaceWorld

    init(world: SurfaceWorld) {
        schemaVersion = Self.schemaVersion
        kind = "digging-surface"
        self.world = world
    }

    /// Restores both current and explicitly supported migrated snapshots through
    /// the same compatibility gate used by Save/Resume and debug-state replay.
    func restoredWorld() throws -> SurfaceWorld {
        guard kind == "digging-surface" else {
            throw DiggingSessionError.unsupportedSnapshot
        }
        switch (schemaVersion, world.originalSchemaVersion, world.originalCompatibilityID) {
        case (1, 1, SurfaceWorld.legacyCompatibilityID),
             (Self.schemaVersion, SurfaceWorld.schemaVersion, SurfaceWorld.compatibilityID):
            return try world.validated()
        default:
            throw DiggingSessionError.unsupportedSnapshot
        }
    }
}

struct DiggingDebugStateEnvelope: Codable, Equatable {
    static let formatIdentifier = "com.scottopell.crick.debug-state"
    static let formatVersion = 1

    struct Provenance: Codable, Equatable {
        let appVersion: String
        let buildNumber: String
        let worldCompatibilityID: String
    }

    let formatIdentifier: String
    let formatVersion: Int
    let provenance: Provenance
    let selectedCell: SurfaceCoordinate
    let snapshot: DiggingSnapshotEnvelope

    init(world: SurfaceWorld, selectedCell: SurfaceCoordinate, appVersion: String, buildNumber: String) {
        formatIdentifier = Self.formatIdentifier
        formatVersion = Self.formatVersion
        provenance = Provenance(
            appVersion: appVersion,
            buildNumber: buildNumber,
            worldCompatibilityID: world.compatibilityID
        )
        self.selectedCell = selectedCell
        snapshot = DiggingSnapshotEnvelope(world: world)
    }

    func restoredWorld() throws -> SurfaceWorld {
        guard formatIdentifier == Self.formatIdentifier,
              formatVersion == Self.formatVersion,
              !provenance.appVersion.isEmpty,
              !provenance.buildNumber.isEmpty,
              provenance.appVersion.utf8.count <= DiggingDebugStateCodec.maximumMetadataByteCount,
              provenance.buildNumber.utf8.count <= DiggingDebugStateCodec.maximumMetadataByteCount,
              provenance.worldCompatibilityID == snapshot.world.compatibilityID,
              snapshot.world.index(of: selectedCell) != nil else {
            throw DiggingSessionError.unsupportedDebugState
        }
        return try snapshot.restoredWorld()
    }
}

enum DiggingJSONCodec {
    static func encode<T: Encodable>(_ value: T, prettyPrinted: Bool = false) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = prettyPrinted ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        return try encoder.encode(value)
    }
}

enum DiggingDebugStateCodec {
    static let maximumByteCount = 1_000_000
    static let maximumMetadataByteCount = 128

    static func encode(_ envelope: DiggingDebugStateEnvelope) throws -> Data {
        let data = try DiggingJSONCodec.encode(envelope)
        guard data.count <= maximumByteCount else {
            throw DiggingSessionError.unsupportedDebugState
        }
        // Serialization is also the canonical migration boundary: a validated v1
        // world writes the current schema. Validate the exact bytes users receive,
        // rather than stale original-schema provenance retained only in memory.
        _ = try decode(data)
        return data
    }

    /// Developer replay entry point. It accepts only bounded, version-compatible
    /// plain JSON and validates the nested save envelope before returning it.
    static func decode(_ data: Data) throws -> DiggingDebugStateEnvelope {
        guard data.count <= maximumByteCount else {
            throw DiggingSessionError.unsupportedDebugState
        }
        let envelope = try JSONDecoder().decode(DiggingDebugStateEnvelope.self, from: data)
        _ = try envelope.restoredWorld()
        return envelope
    }
}

enum DiggingSessionError: Error, Equatable {
    case unsupportedSnapshot
    case unsupportedDebugState
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
    private var pendingObservationTicks = 0

    init(snapshotStore: any SnapshotStoring) {
        self.snapshotStore = snapshotStore
        world = DiggingExperimentTerrain.newWorld()
        canResume = snapshotStore.exists()
    }

    func cutFloor(startingAt coordinate: SurfaceCoordinate) -> Double? {
        try? world.cutFloor(startingAt: coordinate)
    }

    /// Compatibility convenience for discrete callers; pointer gestures must pass
    /// their independently captured floor through the overload below.
    @discardableResult
    func excavate(_ coordinates: [SurfaceCoordinate]) -> Bool {
        guard let first = coordinates.first,
              let floor = cutFloor(startingAt: first) else { return false }
        return excavate(coordinates, toFloor: floor)
    }

    /// Pointer path: every update supplies the floor captured once at finger-down.
    @discardableResult
    func excavate(_ coordinates: [SurfaceCoordinate], toFloor floor: Double) -> Bool {
        let beforeLatestDig = world.cells.map(\.waterDepth)
        var changed = false
        for coordinate in coordinates {
            if (try? world.excavate(coordinate, toFloor: floor)) ?? 0 > 0 {
                changed = true
                selectedCoordinate = coordinate
                pendingDugCoordinates.insert(coordinate)
            }
        }
        if changed {
            // Every successful intervention starts one fresh, bounded physical-time
            // observation window. Scheduler speed changes pulse frequency, not this count.
            preDigWaterDepths = beforeLatestDig
            pendingObservationTicks = 0
            message = "Ground lowered — current carries the loose bed"
            sceneSummary = diggingSummary(newlyWet: nil)
        }
        return changed
    }

    /// Separate VoiceOver equivalent: one intentional scoop at the selected cell.
    func excavateSelected() -> Bool {
        guard let floor = cutFloor(startingAt: selectedCoordinate) else { return false }
        return excavate([selectedCoordinate], toFloor: floor)
    }

    @discardableResult
    func advanceLive(steps: Int = 1) -> Int {
        let wasObservingDig = !pendingDugCoordinates.isEmpty
        var completed = 0
        for _ in 0..<max(0, steps) {
            guard world.step() else { break }
            completed += 1
            observePendingDigAfterPhysicalTick()
        }
        if completed > 0, !wasObservingDig { message = "Creek running live" }
        return completed
    }

    func advanceCaptured(count: Int = observationTicks) -> [SurfaceWorld] {
        guard count > 0 else { return [] }
        var frames: [SurfaceWorld] = []
        frames.reserveCapacity(count)
        for _ in 0..<count {
            guard world.step() else { break }
            frames.append(world)
            observePendingDigAfterPhysicalTick()
        }
        if pendingDugCoordinates.isEmpty { message = "Water flowed for \(frames.count) fixed ticks" }
        return frames
    }

    func reset() {
        world = DiggingExperimentTerrain.newWorld()
        selectedCoordinate = SurfaceCoordinate(column: 8, row: 10)
        preDigWaterDepths = nil
        pendingDugCoordinates.removeAll(keepingCapacity: true)
        pendingObservationTicks = 0
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

    private func observePendingDigAfterPhysicalTick() {
        guard let before = preDigWaterDepths, !pendingDugCoordinates.isEmpty else { return }
        pendingObservationTicks += 1
        guard pendingObservationTicks >= Self.automaticTicks else { return }

        let newlyWet = world.cells.indices.filter {
            before[$0] <= 0.001 && world.cells[$0].waterDepth > 0.004
        }
        let alongStroke = newlyWet.count { index in
            pendingDugCoordinates.contains(world.coordinate(for: index)!)
        }
        message = "Water responded for \(pendingObservationTicks) physical ticks"
        sceneSummary = diggingSummary(
            newlyWet: (newlyWet.count, alongStroke),
            remainingWaterLips: world.dryExcavationBarriers().count
        )
        preDigWaterDepths = nil
        pendingDugCoordinates.removeAll(keepingCapacity: true)
        pendingObservationTicks = 0
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

    /// Produces portable compact JSON without changing authority, presentation,
    /// tick, or the user's save file. Bundle metadata can be injected by tests.
    func debugStateData(
        appVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
        buildNumber: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
    ) throws -> Data {
        try DiggingDebugStateCodec.encode(DiggingDebugStateEnvelope(
            world: world,
            selectedCell: selectedCoordinate,
            appVersion: appVersion,
            buildNumber: buildNumber
        ))
    }

    func save() throws {
        let envelope = DiggingSnapshotEnvelope(world: world)
        if let files = snapshotStore as? FileSnapshotStore, files.exists() {
            // Save owns preservation: launch/background saves can occur before Resume.
            // Inspect the bytes that are about to be replaced and preserve an exact,
            // validated v1 envelope once. Corrupt/non-v1 files retain normal explicit
            // save semantics but can never be mistaken for migration input.
            let existing = try files.load()
            if Self.isLegacyV1Envelope(existing) {
                let backup = files.url.deletingPathExtension().appendingPathExtension("v1-backup.json")
                if !FileManager.default.fileExists(atPath: backup.path) {
                    try existing.write(to: backup, options: .atomic)
                }
            }
        }
        try snapshotStore.save(try DiggingJSONCodec.encode(envelope, prettyPrinted: true))
        canResume = true
        message = "Saved this digging creek"
    }

    private static func isLegacyV1Envelope(_ data: Data) -> Bool {
        guard let envelope = try? JSONDecoder().decode(DiggingSnapshotEnvelope.self, from: data) else {
            return false
        }
        return envelope.kind == "digging-surface"
            && envelope.schemaVersion == 1
            && envelope.world.originalSchemaVersion == 1
            && envelope.world.originalCompatibilityID == SurfaceWorld.legacyCompatibilityID
            && (try? envelope.world.validated()) != nil
    }

    func resume() throws {
        let envelope = try JSONDecoder().decode(
            DiggingSnapshotEnvelope.self,
            from: snapshotStore.load()
        )
        // Reject envelope/world hybrids before assigning a migrated world. This
        // also prevents a forged v1 envelope from triggering backup behavior.
        let restored = try envelope.restoredWorld()
        world = restored
        selectedCoordinate = SurfaceCoordinate(
            column: min(world.width - 2, max(1, selectedCoordinate.column)),
            row: min(world.height - 2, max(1, selectedCoordinate.row))
        )
        message = "Resumed saved creek at tick \(world.tick)"
        preDigWaterDepths = nil
        pendingDugCoordinates.removeAll(keepingCapacity: true)
        pendingObservationTicks = 0
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
