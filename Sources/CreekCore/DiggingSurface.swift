import Foundation

/// A deliberately small, deterministic surface-water model for the digging experiment.
/// It is independent of the legacy one-dimensional `Simulator` and its compatibility ID.
public struct SurfaceCoordinate: Codable, Equatable, Hashable, Sendable {
    public var column: Int
    public var row: Int

    public init(column: Int, row: Int) {
        self.column = column
        self.row = row
    }
}

public struct SurfaceCell: Codable, Equatable, Sendable {
    public var groundHeight: Double
    public var authoredGroundHeight: Double
    public var waterDepth: Double
    /// Signed net water movement during the last tick, in grid axes.
    public var flowX: Double
    public var flowY: Double

    public init(
        groundHeight: Double,
        authoredGroundHeight: Double? = nil,
        waterDepth: Double = 0,
        flowX: Double = 0,
        flowY: Double = 0
    ) {
        self.groundHeight = groundHeight
        self.authoredGroundHeight = authoredGroundHeight ?? groundHeight
        self.waterDepth = waterDepth
        self.flowX = flowX
        self.flowY = flowY
    }

    public var surfaceHeight: Double { groundHeight + waterDepth }
    public var excavationDepth: Double { authoredGroundHeight - groundHeight }
}

public struct SurfaceWaterLedger: Codable, Equatable, Sendable {
    public var initialWater: Double
    public var waterIn: Double
    public var waterOut: Double

    public init(initialWater: Double, waterIn: Double = 0, waterOut: Double = 0) {
        self.initialWater = initialWater
        self.waterIn = waterIn
        self.waterOut = waterOut
    }
}

/// One authoritative cardinal transfer completed during the most recent fixed tick.
/// Consumers may aggregate these measurements across a gate, but routing remains
/// entirely owned by `SurfaceWorld`.
public struct SurfaceEdgeTransfer: Codable, Equatable, Sendable {
    public let from: SurfaceCoordinate
    public let to: SurfaceCoordinate
    public let amount: Double

    public init(from: SurfaceCoordinate, to: SurfaceCoordinate, amount: Double) {
        self.from = from
        self.to = to
        self.amount = amount
    }
}

/// A local, directly observable hydraulic obstruction from a visibly wet source
/// toward an excavated neighbor below the visual wet-depth threshold. `rise` is
/// the destination surface minus the source surface, exactly as compared by the
/// solver. The destination can contain shallow water that the renderer omits.
public struct SurfaceBarrierEdge: Equatable, Sendable {
    public let visibleWetSource: SurfaceCoordinate
    public let belowVisualWetThresholdDestination: SurfaceCoordinate
    public let rise: Double

    public init(
        visibleWetSource: SurfaceCoordinate,
        belowVisualWetThresholdDestination: SurfaceCoordinate,
        rise: Double
    ) {
        self.visibleWetSource = visibleWetSource
        self.belowVisualWetThresholdDestination = belowVisualWetThresholdDestination
        self.rise = rise
    }
}

public enum SurfaceWorldError: Error, Equatable, Sendable {
    case invalidDimensions
    case invalidCellCount
    case invalidBoundary
    case invalidCell(SurfaceCoordinate)
    case unsafeToDig(SurfaceCoordinate)
    case invalidAmount
    case invalidState
}

public struct SurfaceWorld: Codable, Equatable, Sendable {
    public static let schemaVersion = 1
    public static let compatibilityID = "crick-digging-surface-v1"
    /// The default interaction scoop. Persisted v1 worlds store absolute ground
    /// heights, so increasing this future edit amount does not reinterpret or
    /// invalidate shallower cuts made by earlier builds.
    public static let excavationIncrement = 0.11
    public static let maximumExcavationDepth = 0.44
    public static let hydraulicTolerance = 0.002

    public private(set) var schemaVersion: Int
    public private(set) var compatibilityID: String
    public private(set) var width: Int
    public private(set) var height: Int
    public private(set) var tick: UInt64
    public private(set) var cells: [SurfaceCell]
    public private(set) var source: SurfaceCoordinate
    public private(set) var outlet: SurfaceCoordinate
    public private(set) var sourceWaterPerTick: Double
    public private(set) var sourceDepthCap: Double
    public private(set) var ledger: SurfaceWaterLedger
    public private(set) var lastEdgeTransfers: [SurfaceEdgeTransfer]

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, compatibilityID, width, height, tick, cells
        case source, outlet, sourceWaterPerTick, sourceDepthCap, ledger
        case lastEdgeTransfers
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        compatibilityID = try container.decode(String.self, forKey: .compatibilityID)
        width = try container.decode(Int.self, forKey: .width)
        height = try container.decode(Int.self, forKey: .height)
        tick = try container.decode(UInt64.self, forKey: .tick)
        cells = try container.decode([SurfaceCell].self, forKey: .cells)
        source = try container.decode(SurfaceCoordinate.self, forKey: .source)
        outlet = try container.decode(SurfaceCoordinate.self, forKey: .outlet)
        sourceWaterPerTick = try container.decode(Double.self, forKey: .sourceWaterPerTick)
        sourceDepthCap = try container.decode(Double.self, forKey: .sourceDepthCap)
        ledger = try container.decode(SurfaceWaterLedger.self, forKey: .ledger)
        lastEdgeTransfers = try container.decodeIfPresent(
            [SurfaceEdgeTransfer].self,
            forKey: .lastEdgeTransfers
        ) ?? []
        try validateCompleteInvariant()
    }

    public init(
        width: Int,
        height: Int,
        cells: [SurfaceCell],
        source: SurfaceCoordinate,
        outlet: SurfaceCoordinate,
        sourceWaterPerTick: Double,
        sourceDepthCap: Double,
        tick: UInt64 = 0,
        ledger: SurfaceWaterLedger? = nil,
        lastEdgeTransfers: [SurfaceEdgeTransfer] = []
    ) throws {
        self.schemaVersion = Self.schemaVersion
        self.compatibilityID = Self.compatibilityID
        self.width = width
        self.height = height
        self.tick = tick
        self.cells = cells
        self.source = source
        self.outlet = outlet
        self.sourceWaterPerTick = sourceWaterPerTick
        self.sourceDepthCap = sourceDepthCap
        self.ledger = ledger ?? SurfaceWaterLedger(
            initialWater: cells.reduce(0) { $0 + $1.waterDepth }
        )
        self.lastEdgeTransfers = lastEdgeTransfers
        try validateCompleteInvariant()
    }

    public var totalWater: Double { cells.reduce(0) { $0 + $1.waterDepth } }
    public var expectedWater: Double { ledger.initialWater + ledger.waterIn - ledger.waterOut }
    public var waterResidual: Double { totalWater - expectedWater }

    public func index(of coordinate: SurfaceCoordinate) -> Int? {
        guard (0..<width).contains(coordinate.column),
              (0..<height).contains(coordinate.row) else { return nil }
        return coordinate.row * width + coordinate.column
    }

    public func coordinate(for index: Int) -> SurfaceCoordinate? {
        guard cells.indices.contains(index) else { return nil }
        return SurfaceCoordinate(column: index % width, row: index / width)
    }

    public func isSafeToDig(_ coordinate: SurfaceCoordinate) -> Bool {
        (1..<(width - 1)).contains(coordinate.column)
            && (1..<(height - 1)).contains(coordinate.row)
    }

    /// Finds immediate blocked transfers from visibly wet cells toward excavated
    /// neighbors at or below the renderer's wet-depth threshold. Such destinations
    /// can contain shallow water; this diagnostic intentionally follows visibility,
    /// while its surface comparison and tolerance exactly match `proposeEdge`.
    /// Calling this does not mutate or advance the simulation.
    public func dryExcavationBarriers(
        visualWetDepth: Double = 0.004,
        minimumExcavation: Double = 0.000_001
    ) -> [SurfaceBarrierEdge] {
        var barriers: [SurfaceBarrierEdge] = []
        for row in 0..<height {
            for column in 0..<width {
                let first = SurfaceCoordinate(column: column, row: row)
                for second in [
                    SurfaceCoordinate(column: column + 1, row: row),
                    SurfaceCoordinate(column: column, row: row + 1),
                ] {
                    guard let firstIndex = index(of: first),
                          let secondIndex = index(of: second) else { continue }
                    let firstCell = cells[firstIndex]
                    let secondCell = cells[secondIndex]
                    let source: (SurfaceCoordinate, SurfaceCell)
                    let destination: (SurfaceCoordinate, SurfaceCell)
                    if firstCell.waterDepth > visualWetDepth,
                       secondCell.waterDepth <= visualWetDepth,
                       secondCell.excavationDepth > minimumExcavation {
                        source = (first, firstCell)
                        destination = (second, secondCell)
                    } else if secondCell.waterDepth > visualWetDepth,
                              firstCell.waterDepth <= visualWetDepth,
                              firstCell.excavationDepth > minimumExcavation {
                        source = (second, secondCell)
                        destination = (first, firstCell)
                    } else {
                        continue
                    }
                    let rise = destination.1.surfaceHeight - source.1.surfaceHeight
                    if rise > Self.hydraulicTolerance {
                        barriers.append(SurfaceBarrierEdge(
                            visibleWetSource: source.0,
                            belowVisualWetThresholdDestination: destination.0,
                            rise: rise
                        ))
                    }
                }
            }
        }
        return barriers
    }

    /// Lowers any safe interior cell by one equal increment. There are no authored
    /// solution cells: eligibility depends only on the safety boundary.
    @discardableResult
    public mutating func excavate(
        _ coordinate: SurfaceCoordinate,
        amount: Double = Self.excavationIncrement
    ) throws -> Double {
        guard amount.isFinite, amount > 0 else { throw SurfaceWorldError.invalidAmount }
        guard let index = index(of: coordinate) else { throw SurfaceWorldError.invalidCell(coordinate) }
        guard isSafeToDig(coordinate) else { throw SurfaceWorldError.unsafeToDig(coordinate) }
        let remaining = Self.maximumExcavationDepth - cells[index].excavationDepth
        let removed = min(amount, max(0, remaining))
        cells[index].groundHeight -= removed
        return removed
    }

    /// Advances one fixed tick. Every cardinal transfer is derived from the same
    /// pre-transfer surface, then each source cell's aggregate proposal is scaled
    /// to a bounded fraction of its available water before all deltas are applied.
    @discardableResult
    public mutating func step() -> Bool {
        // Saturating at the representable tick is preferable to wrapping chronology
        // or partially mutating water/ledger state.
        guard tick < UInt64.max else { return false }
        let sourceIndex = index(of: source)!
        let admitted = min(
            sourceWaterPerTick,
            max(0, sourceDepthCap - cells[sourceIndex].waterDepth)
        )
        let nextSourceDepth = cells[sourceIndex].waterDepth + admitted
        let nextWaterIn = ledger.waterIn + admitted
        let nextSupplied = ledger.initialWater + nextWaterIn
        guard nextSourceDepth.isFinite, nextWaterIn.isFinite,
              nextSupplied.isFinite else {
            lastEdgeTransfers = []
            return false
        }
        cells[sourceIndex].waterDepth = nextSourceDepth
        ledger.waterIn = nextWaterIn

        let preWater = cells.map(\.waterDepth)
        let surfaces = cells.map(\.surfaceHeight)
        var proposals = Array(repeating: [(target: Int, amount: Double, dx: Double, dy: Double)](), count: cells.count)

        // Stable row-major traversal; right/down visits each undirected edge once.
        for row in 0..<height {
            for column in 0..<width {
                let from = row * width + column
                if column + 1 < width {
                    proposeEdge(from, from + 1, dx: 1, dy: 0, surfaces: surfaces, into: &proposals)
                }
                if row + 1 < height {
                    proposeEdge(from, from + width, dx: 0, dy: 1, surfaces: surfaces, into: &proposals)
                }
            }
        }

        var delta = Array(repeating: 0.0, count: cells.count)
        var flowX = Array(repeating: 0.0, count: cells.count)
        var flowY = Array(repeating: 0.0, count: cells.count)
        var completedTransfers: [SurfaceEdgeTransfer] = []
        completedTransfers.reserveCapacity(cells.count * 2)
        for sourceIndex in cells.indices {
            let totalProposed = proposals[sourceIndex].reduce(0) { $0 + $1.amount }
            guard totalProposed.isFinite, totalProposed > 0,
                  preWater[sourceIndex] > 0 else { continue }
            // Retaining some local water damps cardinal checkerboarding while the
            // aggregate cap guarantees conservation even with four lower neighbors.
            let aggregateCap = preWater[sourceIndex] * 0.58
            let scale = min(1, aggregateCap / totalProposed)
            for proposal in proposals[sourceIndex] {
                let amount = proposal.amount * scale
                delta[sourceIndex] -= amount
                delta[proposal.target] += amount
                flowX[sourceIndex] += proposal.dx * amount
                flowY[sourceIndex] += proposal.dy * amount
                flowX[proposal.target] += proposal.dx * amount
                flowY[proposal.target] += proposal.dy * amount
                completedTransfers.append(SurfaceEdgeTransfer(
                    from: coordinate(for: sourceIndex)!,
                    to: coordinate(for: proposal.target)!,
                    amount: amount
                ))
            }
        }

        for index in cells.indices {
            cells[index].waterDepth = max(0, cells[index].waterDepth + delta[index])
            cells[index].flowX = flowX[index]
            cells[index].flowY = flowY[index]
        }

        // The outlet is a real participating cell above. Drain only after incoming
        // cardinal transfers have arrived, so it can visibly wet and pass water out.
        let outletIndex = index(of: outlet)!
        let drained = min(cells[outletIndex].waterDepth, 0.042)
        cells[outletIndex].waterDepth -= drained
        ledger.waterOut += drained
        lastEdgeTransfers = completedTransfers
        tick += 1
        return true
    }

    @discardableResult
    public mutating func step(count: Int) -> Int {
        guard count > 0 else { return 0 }
        var completed = 0
        for _ in 0..<count where step() { completed += 1 }
        return completed
    }

    public func validated() throws -> Self {
        try validateCompleteInvariant()
        return self
    }

    /// The single complete state gate used by both construction and decoded-state
    /// restoration. Keep every persisted invariant here so no entry path can drift.
    private func validateCompleteInvariant() throws {
        guard schemaVersion == Self.schemaVersion,
              compatibilityID == Self.compatibilityID else {
            throw SurfaceWorldError.invalidState
        }
        guard width >= 3, height >= 3 else {
            throw SurfaceWorldError.invalidDimensions
        }
        let product = width.multipliedReportingOverflow(by: height)
        guard !product.overflow, cells.count == product.partialValue else {
            throw SurfaceWorldError.invalidCellCount
        }
        guard sourceWaterPerTick.isFinite, sourceWaterPerTick >= 0,
              sourceDepthCap.isFinite, sourceDepthCap >= 0 else {
            throw SurfaceWorldError.invalidAmount
        }
        guard (0..<width).contains(source.column),
              (0..<height).contains(source.row),
              (0..<width).contains(outlet.column),
              (0..<height).contains(outlet.row),
              source.row == 0, outlet.row == height - 1 else {
            throw SurfaceWorldError.invalidBoundary
        }
        guard cells.allSatisfy({ cell in
            let excavation = cell.authoredGroundHeight - cell.groundHeight
            let surface = cell.groundHeight + cell.waterDepth
            return cell.groundHeight.isFinite && cell.authoredGroundHeight.isFinite
                && cell.waterDepth.isFinite && cell.waterDepth >= 0
                && cell.flowX.isFinite && cell.flowY.isFinite
                && excavation.isFinite && excavation >= -1e-12
                && excavation <= Self.maximumExcavationDepth + 1e-12
                && surface.isFinite
        }) else { throw SurfaceWorldError.invalidState }

        let supplied = ledger.initialWater + ledger.waterIn
        let expected = supplied - ledger.waterOut
        let actual = cells.reduce(0) { $0 + $1.waterDepth }
        guard ledger.initialWater.isFinite, ledger.initialWater >= 0,
              ledger.waterIn.isFinite, ledger.waterIn >= 0,
              ledger.waterOut.isFinite, ledger.waterOut >= 0,
              supplied.isFinite,
              ledger.waterOut <= supplied + 1e-12,
              expected.isFinite, expected >= -1e-12,
              actual.isFinite,
              abs(actual - expected) <= 1e-8 * max(1, expected),
              lastEdgeTransfers.allSatisfy({ transfer in
                  guard transfer.amount.isFinite, transfer.amount >= 0,
                        index(of: transfer.from) != nil,
                        index(of: transfer.to) != nil else { return false }
                  let distance = abs(transfer.from.column - transfer.to.column)
                      + abs(transfer.from.row - transfer.to.row)
                  return distance == 1
              }) else { throw SurfaceWorldError.invalidState }
    }

    private func proposeEdge(
        _ first: Int,
        _ second: Int,
        dx: Double,
        dy: Double,
        surfaces: [Double],
        into proposals: inout [[(target: Int, amount: Double, dx: Double, dy: Double)]]
    ) {
        let difference = surfaces[first] - surfaces[second]
        guard difference.isFinite, abs(difference) > Self.hydraulicTolerance else { return }
        let amount = (abs(difference) - Self.hydraulicTolerance) * 0.19
        guard amount.isFinite else { return }
        if difference > 0 {
            proposals[first].append((second, amount, dx, dy))
        } else {
            proposals[second].append((first, amount, -dx, -dy))
        }
    }
}

public enum DiggingExperimentTerrain {
    public static let width = 20
    public static let height = 26
    public static let source = SurfaceCoordinate(column: 5, row: 0)
    public static let outlet = SurfaceCoordinate(column: 12, row: height - 1)

    /// A descending gravel bend with a broad, visible inside shoulder. Geometry is
    /// authored, but simulation and digging eligibility contain no route knowledge.
    public static func newWorld(settlingTicks: Int = 520) -> SurfaceWorld {
        var cells: [SurfaceCell] = []
        cells.reserveCapacity(width * height)
        for row in 0..<height {
            let center = centerColumn(at: row)
            for column in 0..<width {
                let distance = abs(Double(column) - center)
                let downstreamSlope = 1.52 - Double(row) * 0.026
                let bankRise = min(0.82, pow(distance / 3.0, 1.55) * 0.17)
                let channelCut = 0.18 * exp(-pow(distance / 1.55, 2))
                let insideShoulder = shoulderHeight(column: column, row: row)
                let gravel = Double((column * 17 + row * 11) % 7) * 0.003
                let height = downstreamSlope + bankRise - channelCut + insideShoulder + gravel
                cells.append(SurfaceCell(groundHeight: height))
            }
        }
        var settlingWorld = try! SurfaceWorld(
            width: width,
            height: height,
            cells: cells,
            source: source,
            outlet: outlet,
            sourceWaterPerTick: 0.036,
            sourceDepthCap: 0.22
        )
        settlingWorld.step(count: settlingTicks)
        // Present a flowing creek as tick zero while preserving exact conservation.
        return try! SurfaceWorld(
            width: width,
            height: height,
            cells: settlingWorld.cells,
            source: source,
            outlet: outlet,
            sourceWaterPerTick: 0.036,
            sourceDepthCap: 0.22
        )
    }

    public static func centerColumn(at row: Int) -> Double {
        switch row {
        case ..<5:
            return 5.0
        case 5...14:
            let t = Double(row - 5) / 9.0
            return 5.0 + 9.0 * (t * t * (3 - 2 * t))
        case 15...19:
            return 14.0
        default:
            let t = Double(row - 20) / 5.0
            return 14.0 - 2.0 * min(1, max(0, t))
        }
    }

    private static func shoulderHeight(column: Int, row: Int) -> Double {
        guard (7...14).contains(row) else { return 0 }
        let center = centerColumn(at: row)
        // The inside of this rightward bend is northwest of its centerline.
        let insideDistance = center - Double(column)
        guard insideDistance > 0.8, insideDistance < 5.2 else { return 0 }
        let rowWeight = 1 - abs(Double(row) - 10.5) / 4.5
        let lateralWeight = 1 - abs(insideDistance - 2.7) / 2.5
        return 0.105 * max(0, rowWeight) * max(0, lateralWeight)
    }
}
