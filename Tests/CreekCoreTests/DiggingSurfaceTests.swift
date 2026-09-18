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

@Test("One captured floor is cut-only across different and pre-lowered heights")
func capturedFloorIsPersistentAndCutOnly() throws {
    var world = DiggingExperimentTerrain.newWorld(settlingTicks: 0)
    let start = SurfaceCoordinate(column: 4, row: 4)
    let high = SurfaceCoordinate(column: 15, row: 4)
    let low = SurfaceCoordinate(column: 5, row: 20)
    let floor = try world.cutFloor(startingAt: start)
    _ = try world.excavate(low, toFloor: world.safeGlobalCutFloor)
    let lowBefore = world.cells[world.index(of: low)!].groundHeight

    _ = try world.excavate(start, toFloor: floor)
    _ = try world.excavate(high, toFloor: floor)
    _ = try world.excavate(low, toFloor: floor)

    #expect(world.cells[world.index(of: start)!].groundHeight == floor)
    #expect(world.cells[world.index(of: high)!].groundHeight == floor)
    #expect(world.cells[world.index(of: low)!].groundHeight == lowBefore)
    #expect(abs(world.materialResidual) < 1e-8)
}

@Test("No water flow performs no erosion")
func noFlowNoErosion() throws {
    let cells = Array(repeating: SurfaceCell(groundHeight: 1), count: 25)
    var world = try SurfaceWorld(
        width: 5, height: 5, cells: cells,
        source: .init(column: 2, row: 0), outlet: .init(column: 2, row: 4),
        sourceWaterPerTick: 0, sourceDepthCap: 0
    )
    let before = world.cells.map(\.groundHeight)
    world.step(count: 200)
    #expect(world.cells.map(\.groundHeight) == before)
    #expect(world.totalCarriedSediment == 0)
}

@Test("A floor cut has positive downstream material effects against an uncut causal control")
func causalCutErosionTransportDeposition() throws {
    // This is a paired intervention: both worlds begin as the exact same ordinary
    // authored terrain with no settling and therefore no pre-existing sediment.
    let initial = DiggingExperimentTerrain.newWorld(settlingTicks: 0)
    #expect(initial.totalCarriedSediment == 0)
    var uncut = initial
    var cutWorld = initial
    let cut = SurfaceCoordinate(column: 6, row: 5)
    let removed = try cutWorld.excavate(cut, toFloor: cutWorld.cutFloor(startingAt: cut))
    #expect(removed > 0)
    #expect(uncut.totalCarriedSediment == 0)
    #expect(cutWorld.totalCarriedSediment == 0)

    struct Measurements {
        var erosion: [Double]
        var deposition: [Double]
        var downstreamSedimentFlux: [Double]
    }
    func run(_ world: inout SurfaceWorld) -> Measurements {
        var result = Measurements(
            erosion: .init(repeating: 0, count: world.cells.count),
            deposition: .init(repeating: 0, count: world.cells.count),
            downstreamSedimentFlux: .init(repeating: 0, count: world.cells.count)
        )
        for _ in 0..<1_200 {
            let preWater = world.cells.map(\.waterDepth)
            let preSediment = world.cells.map(\.sediment)
            let preGround = world.cells.map(\.groundHeight)
            guard world.step() else { break }
            for transfer in world.lastEdgeTransfers where transfer.to.row > transfer.from.row {
                let donor = world.index(of: transfer.from)!
                let receiver = world.index(of: transfer.to)!
                if preWater[donor] > 0 {
                    result.downstreamSedimentFlux[receiver] += preSediment[donor] * transfer.amount / preWater[donor]
                }
            }
            for index in world.cells.indices {
                let delta = world.cells[index].groundHeight - preGround[index]
                if delta < 0 { result.erosion[index] -= delta }
                if delta > 0 { result.deposition[index] += delta }
            }
        }
        return result
    }

    let baseline = run(&uncut)
    let intervention = run(&cutWorld)
    // Fixed nearby downstream observations, chosen from the ordinary map rather
    // than by searching for a solver optimum.
    let erosionIndex = cutWorld.index(of: .init(column: 6, row: 6))!
    let fluxIndex = cutWorld.index(of: .init(column: 5, row: 6))!
    let depositionIndex = cutWorld.index(of: .init(column: 5, row: 6))!
    let erosionEffect = intervention.erosion[erosionIndex] - baseline.erosion[erosionIndex]
    let fluxEffect = intervention.downstreamSedimentFlux[fluxIndex] - baseline.downstreamSedimentFlux[fluxIndex]
    let depositionEffect = intervention.deposition[depositionIndex] - baseline.deposition[depositionIndex]

    #expect(uncut.tick == 1_200)
    #expect(cutWorld.tick == uncut.tick)
    #expect(erosionEffect > 0)
    #expect(fluxEffect > 0)
    #expect(depositionEffect > 0)
    #expect(abs(cutWorld.materialLedger.excavated - uncut.materialLedger.excavated - removed) < 1e-12)
    #expect(abs(uncut.materialResidual) < 1e-7)
    #expect(abs(cutWorld.materialResidual) < 1e-7)
    let e = cutWorld.coordinate(for: erosionIndex)!
    let f = cutWorld.coordinate(for: fluxIndex)!
    let d = cutWorld.coordinate(for: depositionIndex)!
    print("CAUSAL_CUT paired_tick=\(cutWorld.tick) cut=\(cut.column),\(cut.row) removed=\(removed) erosion_cut_minus_control=\(e.column),\(e.row):\(erosionEffect) sediment_flux_cut_minus_control=\(f.column),\(f.row):\(fluxEffect) deposition_cut_minus_control=\(d.column),\(d.row):\(depositionEffect) excavated_ledger_cut_minus_control=\(cutWorld.materialLedger.excavated - uncut.materialLedger.excavated) exported_ledger_cut_minus_control=\(cutWorld.materialLedger.exported - uncut.materialLedger.exported)")
}

@Test("Sediment advects and deposits when carrying capacity falls")
func sedimentTransportDepositsDownstream() throws {
    let width = 3
    var cells = Array(repeating: SurfaceCell(groundHeight: 1), count: 9)
    cells[1] = SurfaceCell(groundHeight: 1.2, waterDepth: 0.3, sediment: 0.04)
    cells[4] = SurfaceCell(groundHeight: 1.0, waterDepth: 0.05)
    cells[7] = SurfaceCell(groundHeight: 1.0, waterDepth: 0.05)
    var world = try SurfaceWorld(
        width: width, height: 3, cells: cells,
        source: .init(column: 1, row: 0), outlet: .init(column: 1, row: 2),
        sourceWaterPerTick: 0, sourceDepthCap: 0
    )
    let downstreamBefore = world.cells[4].groundHeight
    world.step(count: 40)
    #expect(world.cells[4].groundHeight > downstreamBefore || world.cells[7].groundHeight > 1)
    #expect(abs(world.materialResidual) < 1e-8)
}

@Test("Closed material ledger remains conserved over a long run")
func closedMaterialLedgerLongRun() throws {
    var world = DiggingExperimentTerrain.newWorld()
    let floor = try world.cutFloor(startingAt: .init(column: 7, row: 8))
    for row in 8...14 { _ = try world.excavate(.init(column: 7, row: row), toFloor: floor) }
    world.step(count: 1_000)
    #expect(abs(world.materialResidual) < 1e-7)
    #expect((try? world.validated()) != nil)
}

@Test("Schema one world migrates exact height and water with zero sediment")
func v1SurfaceMigration() throws {
    let current = DiggingExperimentTerrain.newWorld(settlingTicks: 0)
    var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(current)) as? [String: Any])
    json["schemaVersion"] = 1
    json["compatibilityID"] = SurfaceWorld.legacyCompatibilityID
    json.removeValue(forKey: "materialLedger")
    var oldCells = json["cells"] as! [[String: Any]]
    for index in oldCells.indices { oldCells[index].removeValue(forKey: "sediment") }
    json["cells"] = oldCells
    let data = try JSONSerialization.data(withJSONObject: json)
    let migrated = try JSONDecoder().decode(SurfaceWorld.self, from: data)
    #expect(migrated.schemaVersion == 2)
    #expect(migrated.cells.map(\.groundHeight) == current.cells.map(\.groundHeight))
    #expect(migrated.cells.map(\.waterDepth) == current.cells.map(\.waterDepth))
    #expect(migrated.totalCarriedSediment == 0)
    #expect(abs(migrated.materialResidual) < 1e-8)
}

@Test("Schema two rejects absent material ledger and absent cell sediment")
func v2SurfaceRequiresMaterialFields() throws {
    let current = DiggingExperimentTerrain.newWorld(settlingTicks: 0)
    let encoded = try JSONEncoder().encode(current)

    var withoutLedger = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    withoutLedger.removeValue(forKey: "materialLedger")
    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(
            SurfaceWorld.self,
            from: JSONSerialization.data(withJSONObject: withoutLedger)
        )
    }

    var withoutSediment = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    var cells = try #require(withoutSediment["cells"] as? [[String: Any]])
    cells[0].removeValue(forKey: "sediment")
    withoutSediment["cells"] = cells
    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(
            SurfaceWorld.self,
            from: JSONSerialization.data(withJSONObject: withoutSediment)
        )
    }
}

@Test("A fully drained outlet exports its full proportional sediment before bed exchange")
func fullDrainExportsAllOutletSediment() throws {
    // Equal surfaces prevent advection: the outlet's 0.04 water is the exact
    // post-advection mixture and the 0.042 drain removes all of it.
    var cells = Array(repeating: SurfaceCell(groundHeight: 1.04), count: 9)
    cells[7] = SurfaceCell(groundHeight: 1, waterDepth: 0.04, sediment: 0.01)
    var world = try SurfaceWorld(
        width: 3,
        height: 3,
        cells: cells,
        source: .init(column: 1, row: 0),
        outlet: .init(column: 1, row: 2),
        sourceWaterPerTick: 0,
        sourceDepthCap: 0
    )
    let groundBefore = world.cells[7].groundHeight

    let completed = world.step()
    #expect(completed)

    #expect(abs(world.cells[7].waterDepth) < 1e-12)
    #expect(abs(world.cells[7].sediment) < 1e-12)
    #expect(abs(world.materialLedger.exported - 0.01) < 1e-12)
    #expect(world.cells[7].groundHeight == groundBefore)
    #expect(abs(world.materialResidual) < 1e-12)
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

@Test("Barrier diagnostic uses destination surface, solver deadband, and visual wet threshold")
func surfaceBarrierDiagnosticMatchesTransferThreshold() throws {
    let source = SurfaceCoordinate(column: 1, row: 1)
    let destination = SurfaceCoordinate(column: 2, row: 1)

    func world(destinationGround: Double, destinationWater: Double) throws -> SurfaceWorld {
        var cells = Array(repeating: SurfaceCell(groundHeight: 2), count: 12)
        cells[5] = SurfaceCell(groundHeight: 1, waterDepth: 0.01)
        cells[6] = SurfaceCell(
            groundHeight: destinationGround,
            authoredGroundHeight: destinationGround + 0.1,
            waterDepth: destinationWater
        )
        return try SurfaceWorld(
            width: 4,
            height: 3,
            cells: cells,
            source: .init(column: 1, row: 0),
            outlet: .init(column: 1, row: 2),
            sourceWaterPerTick: 0,
            sourceDepthCap: 0
        )
    }

    // Shallow destination water is visually omitted but contributes to its surface.
    let blocked = try world(destinationGround: 1.010, destinationWater: 0.003)
    let barriers = blocked.dryExcavationBarriers()
    #expect(barriers.count == 1)
    #expect(barriers.first?.visibleWetSource == source)
    #expect(barriers.first?.belowVisualWetThresholdDestination == destination)
    #expect(abs((barriers.first?.rise ?? 0) - 0.003) < 1e-12)

    // A rise inside the same hydraulic tolerance as the solver is not a barrier.
    let deadband = try world(destinationGround: 1.0119, destinationWater: 0)
    #expect(deadband.dryExcavationBarriers().isEmpty)

    // A destination below the source surface is transferable, not blocked.
    var transferable = try world(destinationGround: 1.008, destinationWater: 0)
    #expect(transferable.dryExcavationBarriers().isEmpty)
    let advanced = transferable.step()
    #expect(advanced)
    #expect(transferable.lastEdgeTransfers.contains {
        $0.from == source && $0.to == destination && $0.amount > 0
    })
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

@Test("Captured phone barrier needs a real cut; revised scoop carries water through the same footprint")
func capturedBarrierRegression() throws {
    struct Envelope: Decodable { let world: SurfaceWorld }
    let fixture = try #require(Bundle.module.url(
        forResource: "barrier-snapshot-tick-540",
        withExtension: "json",
        subdirectory: "Fixtures"
    ))
    let captured = try JSONDecoder().decode(Envelope.self, from: Data(contentsOf: fixture)).world
    #expect(captured.tick == 540)

    let footprint = captured.cells.indices.filter {
        captured.cells[$0].excavationDepth > 0.000_001
    }.compactMap(captured.coordinate)
    #expect(footprint.count == 30)

    // Repeated bounded Observe actions confirm the exact captured terrain remains blocked.
    let untouched = try measuredFootprint(from: captured, footprint: footprint, passes: 0)
    #expect(untouched.longitudinalTransfer == 0)
    #expect(untouched.newlyWetFootprint.isEmpty)

    // Reproduce an app session: each stroke gets its automatic 18 ticks, followed by
    // bounded repeats of the 30-tick Observe action. Measurements use actual transfers.
    let revised = try measuredFootprint(from: captured, footprint: footprint, passes: 3)
    #expect(revised.longitudinalTransfer > 0)
    #expect(!revised.newlyWetFootprint.isEmpty)
    #expect(revised.earliestLowerEdgeTransferTick != nil)
    #expect(revised.earliestNewWetTick != nil)

    // Lowering ground is not a predetermined win: a deep, isolated pit stays isolated.
    let pit = [
        SurfaceCoordinate(column: 2, row: 15),
        SurfaceCoordinate(column: 3, row: 15),
    ]
    let isolated = try measuredFootprint(from: captured, footprint: pit, passes: 3)
    #expect(isolated.longitudinalTransfer == 0)
    #expect(isolated.newlyWetFootprint.isEmpty)
    #expect(isolated.earliestLowerEdgeTransferTick == nil)
    #expect(abs(revised.world.waterResidual) < 1e-8)
    #expect(abs(isolated.world.waterResidual) < 1e-8)

    print("BARRIER_FIX untouched=\(untouched.longitudinalTransfer) revised=\(revised.longitudinalTransfer) newly_wet=\(revised.newlyWetFootprint.count) earliest_lower_edge_tick=\(String(describing: revised.earliestLowerEdgeTransferTick)) earliest_new_wet_tick=\(String(describing: revised.earliestNewWetTick)) isolated=\(isolated.longitudinalTransfer)")
}

private struct FootprintMeasurement {
    let world: SurfaceWorld
    let longitudinalTransfer: Double
    let newlyWetFootprint: Set<SurfaceCoordinate>
    let earliestLowerEdgeTransferTick: UInt64?
    let earliestNewWetTick: UInt64?
}

private func measuredFootprint(
    from baseline: SurfaceWorld,
    footprint: [SurfaceCoordinate],
    passes: Int
) throws -> FootprintMeasurement {
    var world = baseline
    let indices = Set(footprint.compactMap(world.index))
    let initialDepths = world.cells.map(\.waterDepth)
    var longitudinalTransfer = 0.0
    var earliestLowerEdgeTransferTick: UInt64?
    var earliestNewWetTick: UInt64?

    func recordLatestTick() {
        for transfer in world.lastEdgeTransfers {
            guard let from = world.index(of: transfer.from),
                  let to = world.index(of: transfer.to),
                  indices.contains(from), indices.contains(to) else { continue }
            if transfer.to.row > transfer.from.row {
                longitudinalTransfer += transfer.amount
            } else if transfer.to.row < transfer.from.row {
                longitudinalTransfer -= transfer.amount
            }
            if earliestLowerEdgeTransferTick == nil,
               transfer.from == SurfaceCoordinate(column: 8, row: 20),
               transfer.to == SurfaceCoordinate(column: 8, row: 21),
               transfer.amount > 0 {
                earliestLowerEdgeTransferTick = world.tick
            }
        }
        if earliestNewWetTick == nil, footprint.contains(where: { coordinate in
            let index = world.index(of: coordinate)!
            return initialDepths[index] <= 0.001 && world.cells[index].waterDepth > 0.004
        }) {
            earliestNewWetTick = world.tick
        }
    }

    func advance(_ count: Int) {
        for _ in 0..<count {
            let advanced = world.step()
            #expect(advanced)
            recordLatestTick()
        }
    }

    for _ in 0..<passes {
        for coordinate in footprint { try world.excavate(coordinate) }
        advance(18)
    }
    // Observe is repeatable in the app; cap this regression at fifteen actions.
    for _ in 0..<15 { advance(30) }

    let newlyWet = Set(footprint.filter { coordinate in
        let index = world.index(of: coordinate)!
        return initialDepths[index] <= 0.001 && world.cells[index].waterDepth > 0.004
    })
    return FootprintMeasurement(
        world: world,
        longitudinalTransfer: longitudinalTransfer,
        newlyWetFootprint: newlyWet,
        earliestLowerEdgeTransferTick: earliestLowerEdgeTransferTick,
        earliestNewWetTick: earliestNewWetTick
    )
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
