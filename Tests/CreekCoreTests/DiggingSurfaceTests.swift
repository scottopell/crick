@testable import CreekCore
import Foundation
import Testing

@Test("Surface map coordinates round-trip exactly")
func surfaceCoordinateRoundTrip() {
    let world = DiggingExperimentTerrain.newWorld(settlingTicks: 2)
    for index in world.cells.indices {
        let coordinate = world.coordinate(for: index)
        #expect(coordinate != nil)
        #expect(world.index(of: coordinate!) == index)
    }
    #expect(world.index(of: SurfaceCoordinate(column: -1, row: 0)) == nil)
    #expect(world.coordinate(for: world.cells.count) == nil)
}

@Test("Every and only safe interior cell can be incrementally excavated")
func freeInteriorExcavation() throws {
    let original = DiggingExperimentTerrain.newWorld(settlingTicks: 2)
    for row in 0..<original.height {
        for column in 0..<original.width {
            let coordinate = SurfaceCoordinate(column: column, row: row)
            var world = original
            if world.isSafeToDig(coordinate) {
                let first = try world.excavate(coordinate)
                let second = try world.excavate(coordinate)
                #expect(first == SurfaceWorld.excavationIncrement)
                #expect(second == SurfaceWorld.excavationIncrement)
                let index = world.index(of: coordinate)!
                #expect(abs(world.cells[index].excavationDepth - 2 * SurfaceWorld.excavationIncrement) < 1e-12)
            } else {
                #expect(throws: SurfaceWorldError.unsafeToDig(coordinate)) {
                    try world.excavate(coordinate)
                }
            }
        }
    }
}

@Test("Four-neighbor fixed ticks are exact, conservative, and aggregate-capped")
func conservativeSurfaceTick() throws {
    let width = 5
    let height = 5
    var cells = Array(repeating: SurfaceCell(groundHeight: 1), count: width * height)
    cells[2 * width + 2] = SurfaceCell(groundHeight: 1, waterDepth: 1)
    var world = try SurfaceWorld(
        width: width,
        height: height,
        cells: cells,
        source: SurfaceCoordinate(column: 2, row: 0),
        outlet: SurfaceCoordinate(column: 2, row: 4),
        sourceWaterPerTick: 0,
        sourceDepthCap: 0
    )

    world.step()

    let center = world.cells[2 * width + 2]
    #expect(center.waterDepth >= 0.42 - 1e-12)
    #expect(world.cells[2 * width + 1].waterDepth > 0)
    #expect(world.cells[2 * width + 3].waterDepth > 0)
    #expect(world.cells[1 * width + 2].waterDepth > 0)
    #expect(world.cells[3 * width + 2].waterDepth > 0)
    #expect(world.cells[1 * width + 1].waterDepth == 0)
    #expect(abs(world.waterResidual) < 1e-12)
}

@Test("Deterministic replay and Codable snapshot preserve the isolated surface authority")
func surfaceReplayAndSnapshot() throws {
    let route = (4...11).map { SurfaceCoordinate(column: 7, row: $0) }
    var first = DiggingExperimentTerrain.newWorld()
    var second = first
    for coordinate in route {
        try first.excavate(coordinate)
        try second.excavate(coordinate)
    }
    first.step(count: 48)
    second.step(count: 48)
    #expect(first == second)
    #expect(abs(first.waterResidual) < 1e-8)

    let data = try JSONEncoder().encode(first)
    let restored = try JSONDecoder().decode(SurfaceWorld.self, from: data).validated()
    #expect(restored == first)
}

@Test("Authored launch fixture connects source through the draining outlet")
func sourceToOutletFixture() {
    let world = DiggingExperimentTerrain.newWorld()
    let wetRows = world.cells.indices.compactMap {
        world.cells[$0].waterDepth > 0.001 ? world.coordinate(for: $0)!.row : nil
    }
    #expect(wetRows.max() == world.height - 2)
    #expect(world.ledger.initialWater == world.totalWater)
    #expect(world.tick == 0)

    var advanced = world
    advanced.step()
    #expect(advanced.ledger.waterOut > 0)
    #expect(abs(advanced.waterResidual) < 1e-8)
}

@Test("Complete invariant rejects invalid construction and corrupt decoded states")
func completeSurfaceInvariant() throws {
    let valid = DiggingExperimentTerrain.newWorld(settlingTicks: 2)
    let encoder = JSONEncoder()

    #expect(throws: SurfaceWorldError.invalidCellCount) {
        _ = try SurfaceWorld(
            width: .max,
            height: .max,
            cells: [],
            source: .init(column: 0, row: 0),
            outlet: .init(column: 0, row: 2),
            sourceWaterPerTick: 0,
            sourceDepthCap: 0
        )
    }

    let mutations: [(String, (inout [String: Any]) -> Void)] = [
        ("width product overflow", { $0["width"] = Int.max }),
        ("source column", { json in
            var source = json["source"] as! [String: Any]
            source["column"] = -1
            json["source"] = source
        }),
        ("outlet column", { json in
            var outlet = json["outlet"] as! [String: Any]
            outlet["column"] = valid.width
            json["outlet"] = outlet
        }),
        ("source rate", { $0["sourceWaterPerTick"] = -1 }),
        ("source cap", { $0["sourceDepthCap"] = -1 }),
        ("initial ledger", { json in mutateLedger(&json, key: "initialWater", value: -1) }),
        ("in ledger", { json in mutateLedger(&json, key: "waterIn", value: -1) }),
        ("out ledger", { json in mutateLedger(&json, key: "waterOut", value: -1) }),
        ("out exceeds supplied water", { json in mutateLedger(&json, key: "waterOut", value: 1e9) }),
        ("excavation exceeds bound", { json in
            var cells = json["cells"] as! [[String: Any]]
            cells[21]["groundHeight"] = (cells[21]["authoredGroundHeight"] as! Double)
                - SurfaceWorld.maximumExcavationDepth - 0.01
            json["cells"] = cells
        }),
        ("negative water", { json in
            var cells = json["cells"] as! [[String: Any]]
            cells[0]["waterDepth"] = -0.1
            json["cells"] = cells
        }),
    ]

    let encoded = try encoder.encode(valid)
    for (name, mutate) in mutations {
        var json = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        mutate(&json)
        let corrupt = try JSONSerialization.data(withJSONObject: json)
        #expect(throws: Error.self, "decoded corrupt \(name)") {
            _ = try JSONDecoder().decode(SurfaceWorld.self, from: corrupt)
        }
    }

    // JSON cannot encode non-finite values, so exercise finite-input sums that overflow.
    var overflowCells = Array(repeating: SurfaceCell(groundHeight: 0), count: 9)
    overflowCells[0] = SurfaceCell(
        groundHeight: Double.greatestFiniteMagnitude,
        authoredGroundHeight: Double.greatestFiniteMagnitude,
        waterDepth: Double.greatestFiniteMagnitude
    )
    #expect(throws: SurfaceWorldError.invalidState) {
        _ = try SurfaceWorld(
            width: 3,
            height: 3,
            cells: overflowCells,
            source: .init(column: 1, row: 0),
            outlet: .init(column: 1, row: 2),
            sourceWaterPerTick: 0,
            sourceDepthCap: 0
        )
    }
    #expect(throws: SurfaceWorldError.invalidState) {
        _ = try SurfaceWorld(
            width: valid.width,
            height: valid.height,
            cells: valid.cells,
            source: valid.source,
            outlet: valid.outlet,
            sourceWaterPerTick: valid.sourceWaterPerTick,
            sourceDepthCap: valid.sourceDepthCap,
            ledger: SurfaceWaterLedger(
                initialWater: Double.greatestFiniteMagnitude,
                waterIn: Double.greatestFiniteMagnitude,
                waterOut: 0
            )
        )
    }
}

@Test("Dry bed and hydraulic sill remain still")
func dryBedSill() throws {
    let width = 3
    let dry = Array(repeating: SurfaceCell(groundHeight: 1), count: 9)
    var dryWorld = try SurfaceWorld(
        width: width,
        height: 3,
        cells: dry,
        source: .init(column: 1, row: 0),
        outlet: .init(column: 1, row: 2),
        sourceWaterPerTick: 0,
        sourceDepthCap: 0
    )
    let dryBefore = dryWorld
    let dryAdvanced = dryWorld.step()
    #expect(dryAdvanced)
    #expect(dryWorld.cells == dryBefore.cells)
    #expect(dryWorld.lastEdgeTransfers.isEmpty)

    var sillCells = dry
    sillCells[4].waterDepth = 0.0015
    var sillWorld = try SurfaceWorld(
        width: width,
        height: 3,
        cells: sillCells,
        source: .init(column: 1, row: 0),
        outlet: .init(column: 1, row: 2),
        sourceWaterPerTick: 0,
        sourceDepthCap: 0
    )
    let sillAdvanced = sillWorld.step()
    #expect(sillAdvanced)
    #expect(sillWorld.cells[4].waterDepth == 0.0015)
    #expect(sillWorld.lastEdgeTransfers.isEmpty)
}

@Test("Asymmetric long run conserves and fixed-step batching is deterministic")
func asymmetricConservationAndBatching() throws {
    let width = 7
    let height = 6
    let cells = (0..<(width * height)).map { index in
        let column = index % width
        let row = index / width
        return SurfaceCell(
            groundHeight: 2 - Double(row) * 0.07 + Double((column * 7 + row * 3) % 5) * 0.013,
            waterDepth: (column + 2 * row) % 4 == 0 ? Double(column + 1) * 0.009 : 0
        )
    }
    let original = try SurfaceWorld(
        width: width,
        height: height,
        cells: cells,
        source: .init(column: 1, row: 0),
        outlet: .init(column: 5, row: height - 1),
        sourceWaterPerTick: 0.017,
        sourceDepthCap: 0.24
    )
    var batched = original
    var individual = original
    let batchedCount = batched.step(count: 2_000)
    #expect(batchedCount == 2_000)
    for _ in 0..<2_000 {
        let advanced = individual.step()
        #expect(advanced)
    }
    #expect(batched == individual)
    #expect(abs(batched.waterResidual) < 1e-8)
    #expect(batched.cells.allSatisfy { $0.waterDepth.isFinite && $0.waterDepth >= 0 })
}

@Test("Maximum tick refuses a partial or wrapped step")
func tickOverflowPolicy() throws {
    let baseline = DiggingExperimentTerrain.newWorld(settlingTicks: 2)
    var world = try SurfaceWorld(
        width: baseline.width,
        height: baseline.height,
        cells: baseline.cells,
        source: baseline.source,
        outlet: baseline.outlet,
        sourceWaterPerTick: baseline.sourceWaterPerTick,
        sourceDepthCap: baseline.sourceDepthCap,
        tick: .max
    )
    let before = world
    let oneStep = world.step()
    let tenSteps = world.step(count: 10)
    #expect(!oneStep)
    #expect(tenSteps == 0)
    #expect(world == before)
}

private func mutateLedger(_ json: inout [String: Any], key: String, value: Any) {
    var ledger = json["ledger"] as! [String: Any]
    ledger[key] = value
    json["ledger"] = ledger
}

@Test("Connected alternative strokes reroute measured downstream edge flux")
func multipleDiggingAlternativesReroute() throws {
    let baseline = DiggingExperimentTerrain.newWorld()
    let westStroke = [
        (7, 7), (7, 8), (8, 9), (8, 10), (9, 10), (9, 11), (10, 11),
        (10, 12), (11, 12), (11, 13), (12, 13), (12, 14), (13, 14), (13, 15),
    ].map(SurfaceCoordinate.init)
    let eastStroke = [
        (7, 7), (8, 7), (8, 8), (9, 8), (9, 9), (10, 9), (11, 9),
        (11, 10), (12, 10), (12, 11), (13, 11), (13, 12), (14, 12),
        (14, 13), (15, 13), (15, 14), (15, 15), (14, 15), (14, 16),
    ].map(SurfaceCoordinate.init)
    let disconnectedPit = [
        SurfaceCoordinate(column: 2, row: 17),
        SurfaceCoordinate(column: 3, row: 17),
    ]

    let noDig = try measuredRoute(from: baseline, stroke: [])
    let west = try measuredRoute(from: baseline, stroke: westStroke)
    let east = try measuredRoute(from: baseline, stroke: eastStroke)
    let pit = try measuredRoute(from: baseline, stroke: disconnectedPit)

    // Signed downstream flow through row 13→14 moves into distinct excavated gates.
    #expect(west.flux[12] > noDig.flux[12] + 0.20)
    #expect(east.flux[15] > noDig.flux[15] + 0.10)
    #expect(west.newlyWetOnStroke >= 4)
    #expect(east.newlyWetOnStroke >= 5)
    #expect(west.newlyWetDownstream)
    #expect(east.newlyWetDownstream)
    // A similarly deep but disconnected pit does not alter the authoritative gate.
    #expect(zip(pit.flux, noDig.flux).allSatisfy { abs($0 - $1) < 1e-12 })
    print("REROUTE_FLUX baseline12=\(noDig.flux[12]) west12=\(west.flux[12]) baseline15=\(noDig.flux[15]) east15=\(east.flux[15]) pit_delta=\(zip(pit.flux, noDig.flux).map { abs($0 - $1) }.max()!)")
}

private struct RouteMeasurement {
    let flux: [Double]
    let newlyWetOnStroke: Int
    let newlyWetDownstream: Bool
}

private func measuredRoute(
    from baseline: SurfaceWorld,
    stroke: [SurfaceCoordinate],
    repetitions: Int = 3,
    horizon: Int = 100
) throws -> RouteMeasurement {
    var world = baseline
    for _ in 0..<repetitions {
        for coordinate in stroke { try world.excavate(coordinate) }
    }
    var flux = Array(repeating: 0.0, count: world.width)
    for _ in 0..<horizon {
        let advanced = world.step()
        #expect(advanced)
        for transfer in world.lastEdgeTransfers {
            if transfer.from.row == 13, transfer.to.row == 14 {
                flux[transfer.from.column] += transfer.amount
            } else if transfer.from.row == 14, transfer.to.row == 13 {
                flux[transfer.to.column] -= transfer.amount
            }
        }
    }
    let newlyWetOnStroke = stroke.count { coordinate in
        let index = world.index(of: coordinate)!
        return baseline.cells[index].waterDepth < 0.001 && world.cells[index].waterDepth > 0.004
    }
    let newlyWetDownstream = world.cells.indices.contains { index in
        let coordinate = world.coordinate(for: index)!
        return coordinate.row >= 14
            && baseline.cells[index].waterDepth < 0.001
            && world.cells[index].waterDepth > 0.004
    }
    #expect(abs(world.waterResidual) < 1e-8)
    return RouteMeasurement(
        flux: flux,
        newlyWetOnStroke: newlyWetOnStroke,
        newlyWetDownstream: newlyWetDownstream
    )
}
