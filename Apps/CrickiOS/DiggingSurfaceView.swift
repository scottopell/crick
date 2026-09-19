import CreekCore
import SwiftUI

struct SurfaceMapLayout: Equatable {
    let width: Int
    let height: Int
    let bounds: CGRect

    init(width: Int, height: Int, viewport: CGSize) {
        self.width = width
        self.height = height
        let available = CGRect(origin: .zero, size: viewport).insetBy(dx: 10, dy: 8)
        let mapAspect = CGFloat(width) / CGFloat(height)
        let availableAspect = available.width / max(1, available.height)
        let size: CGSize
        if availableAspect > mapAspect {
            size = CGSize(width: available.height * mapAspect, height: available.height)
        } else {
            size = CGSize(width: available.width, height: available.width / mapAspect)
        }
        bounds = CGRect(
            x: available.midX - size.width / 2,
            y: available.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    var cellSize: CGSize {
        CGSize(width: bounds.width / CGFloat(width), height: bounds.height / CGFloat(height))
    }

    func coordinate(at point: CGPoint) -> SurfaceCoordinate? {
        guard bounds.contains(point) else { return nil }
        let column = min(width - 1, Int((point.x - bounds.minX) / cellSize.width))
        let row = min(height - 1, Int((point.y - bounds.minY) / cellSize.height))
        return SurfaceCoordinate(column: column, row: row)
    }

    func center(of coordinate: SurfaceCoordinate) -> CGPoint? {
        guard (0..<width).contains(coordinate.column),
              (0..<height).contains(coordinate.row) else { return nil }
        return CGPoint(
            x: bounds.minX + (CGFloat(coordinate.column) + 0.5) * cellSize.width,
            y: bounds.minY + (CGFloat(coordinate.row) + 0.5) * cellSize.height
        )
    }

    func rect(of coordinate: SurfaceCoordinate) -> CGRect? {
        guard let center = center(of: coordinate) else { return nil }
        return CGRect(
            x: center.x - cellSize.width / 2,
            y: center.y - cellSize.height / 2,
            width: cellSize.width,
            height: cellSize.height
        )
    }
}

struct DiggingBrushState: Equatable {
    private(set) var touched: Set<SurfaceCoordinate> = []
    var previousCoordinate: SurfaceCoordinate?
    private(set) var capturedTarget: Double?
    private(set) var capturedMode: SurfaceEditMode?

    mutating func capture(target: Double, mode: SurfaceEditMode) {
        guard capturedTarget == nil else { return }
        capturedTarget = target
        capturedMode = mode
    }

    mutating func takeFresh(_ coordinates: [SurfaceCoordinate]) -> [SurfaceCoordinate] {
        coordinates.filter { touched.insert($0).inserted }
    }

    mutating func reset() {
        touched.removeAll(keepingCapacity: true)
        previousCoordinate = nil
        capturedTarget = nil
        capturedMode = nil
    }
}

struct DiggingSurfaceView: View {
    let world: SurfaceWorld
    let selectedCoordinate: SurfaceCoordinate?
    let reduceMotion: Bool
    let interactionEnabled: Bool
    let editMode: SurfaceEditMode
    let accessibilitySummary: String
    let onEditBegan: (SurfaceCoordinate, SurfaceEditMode) -> Double?
    let onEditCells: ([SurfaceCoordinate], Double, SurfaceEditMode) -> Void
    let onGestureEnded: () -> Void

    @State private var brush = DiggingBrushState()
    @State private var visibleStroke: [SurfaceCoordinate] = []

    var body: some View {
        GeometryReader { geometry in
            let layout = SurfaceMapLayout(
                width: world.width,
                height: world.height,
                viewport: geometry.size
            )
            Canvas(opaque: true, colorMode: .linear, rendersAsynchronously: false) { context, _ in
                drawGround(context: &context, layout: layout)
                drawCutEdges(context: &context, layout: layout)
                drawWater(context: &context, layout: layout)
                drawBarrierEdges(context: &context, layout: layout)
                drawSelection(context: &context, layout: layout)
                drawStroke(context: &context, layout: layout)
            }
            .contentShape(Rectangle())
            .gesture(digGesture(layout: layout))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Editable gravel creek, \(editMode.rawValue) mode")
            .accessibilityValue(accessibilitySummary)
            .accessibilityHint(editMode == .dig
                ? "Drag to dig to one captured ground level."
                : "Start on a ground level and drag to raise only lower ground to it.")
            .accessibilityIdentifier("digging-surface")
            .onChange(of: interactionEnabled) { _, enabled in
                if !enabled { clearGestureState(preserveOutline: false) }
            }
            .onChange(of: editMode) { _, _ in
                clearGestureState(preserveOutline: false)
            }
            .onDisappear { clearGestureState(preserveOutline: false) }
        }
    }

    private func drawGround(context: inout GraphicsContext, layout: SurfaceMapLayout) {
        context.fill(Path(CGRect(origin: .zero, size: context.environment.displayScale > 0 ? CGSize(width: layout.bounds.maxX + 10, height: layout.bounds.maxY + 8) : .zero)), with: .color(Color(red: 0.09, green: 0.11, blue: 0.075)))
        let minimum = world.cells.map(\.authoredGroundHeight).min() ?? 0
        let maximum = world.cells.map(\.authoredGroundHeight).max() ?? 1
        for index in world.cells.indices {
            guard let coordinate = world.coordinate(for: index),
                  let rect = layout.rect(of: coordinate) else { continue }
            let cell = world.cells[index]
            let normalized = (cell.groundHeight - minimum) / max(0.001, maximum - minimum)
            let dug = min(1, cell.excavationDepth / SurfaceWorld.maximumExcavationDepth)
            let baseRed = 0.28 + normalized * 0.20
            let baseGreen = 0.245 + normalized * 0.17
            let baseBlue = 0.16 + normalized * 0.10
            // A first scoop is a subtle exposed-gravel shift, not the old nearly
            // opaque dark trench. Color and relief now increase continuously with
            // the authoritative absolute cut depth.
            let exposure = dug == 0 ? 0 : 0.10 + 0.62 * dug
            let color = Color(
                red: baseRed * (1 - exposure) + 0.27 * exposure,
                green: baseGreen * (1 - exposure) + 0.145 * exposure,
                blue: baseBlue * (1 - exposure) + 0.075 * exposure
            )
            context.fill(Path(rect.insetBy(dx: 0.08, dy: 0.08)), with: .color(color))

            // Warm bed tint is proportional to authoritative current net bed rise.
            if cell.netBedRise > 0.000_001 {
                let deposited = min(1, cell.netBedRise / SurfaceWorld.maximumBedRise)
                context.fill(
                    Path(rect.insetBy(dx: 0.4, dy: 0.4)),
                    with: .color(Color(red: 0.76, green: 0.48, blue: 0.18).opacity(0.18 + deposited * 0.58))
                )
            }

            // Stable gravel flecks retain a creek-bed reading without procedural randomness.
            if (index * 13 + coordinate.row) % 5 == 0 {
                let pebble = CGRect(
                    x: rect.midX - rect.width * 0.12,
                    y: rect.midY - rect.height * 0.08,
                    width: max(1, rect.width * 0.24),
                    height: max(1, rect.height * 0.16)
                )
                context.fill(Path(ellipseIn: pebble), with: .color(.white.opacity(0.10)))
            }
        }
    }

    /// Draws only measured height discontinuities around excavated ground. The
    /// high side catches light and the low side gets a short shadow, so shallow
    /// and deep cuts remain distinguishable without inventing a route.
    private func drawCutEdges(context: inout GraphicsContext, layout: SurfaceMapLayout) {
        for row in 0..<world.height {
            for column in 0..<world.width {
                let first = SurfaceCoordinate(column: column, row: row)
                guard let firstIndex = world.index(of: first) else { continue }
                for (second, vertical) in [
                    (SurfaceCoordinate(column: column + 1, row: row), true),
                    (SurfaceCoordinate(column: column, row: row + 1), false),
                ] {
                    guard let secondIndex = world.index(of: second),
                          world.cells[firstIndex].excavationDepth > 0.000_001
                            || world.cells[secondIndex].excavationDepth > 0.000_001,
                          let firstRect = layout.rect(of: first) else { continue }
                    let difference = world.cells[firstIndex].groundHeight
                        - world.cells[secondIndex].groundHeight
                    guard abs(difference) > 0.018 else { continue }
                    var edge = Path()
                    if vertical {
                        edge.move(to: CGPoint(x: firstRect.maxX, y: firstRect.minY + 0.7))
                        edge.addLine(to: CGPoint(x: firstRect.maxX, y: firstRect.maxY - 0.7))
                    } else {
                        edge.move(to: CGPoint(x: firstRect.minX + 0.7, y: firstRect.maxY))
                        edge.addLine(to: CGPoint(x: firstRect.maxX - 0.7, y: firstRect.maxY))
                    }
                    let strength = min(0.82, 0.20 + abs(difference) / 0.44 * 0.62)
                    context.stroke(
                        edge,
                        with: .color(difference > 0 ? .white.opacity(strength * 0.45) : .black.opacity(strength)),
                        style: StrokeStyle(lineWidth: 0.7 + min(1.5, abs(difference) * 4.5))
                    )
                }
            }
        }
    }

    private func drawWater(context: inout GraphicsContext, layout: SurfaceMapLayout) {
        // Join adjacent wet cells first, then lay depth-shaped pools over them.
        for index in world.cells.indices where world.cells[index].waterDepth > 0.004 {
            guard let coordinate = world.coordinate(for: index),
                  let center = layout.center(of: coordinate) else { continue }
            for neighbor in [
                SurfaceCoordinate(column: coordinate.column + 1, row: coordinate.row),
                SurfaceCoordinate(column: coordinate.column, row: coordinate.row + 1),
            ] {
                guard let neighborIndex = world.index(of: neighbor),
                      world.cells[neighborIndex].waterDepth > 0.004,
                      let neighborCenter = layout.center(of: neighbor) else { continue }
                var path = Path()
                path.move(to: center)
                path.addLine(to: neighborCenter)
                context.stroke(
                    path,
                    with: .color(Color(red: 0.12, green: 0.55, blue: 0.62).opacity(0.64)),
                    style: StrokeStyle(lineWidth: min(layout.cellSize.width, layout.cellSize.height) * 0.88, lineCap: .round)
                )
            }
        }

        for index in world.cells.indices {
            let cell = world.cells[index]
            guard cell.waterDepth > 0.001,
                  let coordinate = world.coordinate(for: index),
                  let rect = layout.rect(of: coordinate) else { continue }
            let depth = min(1, cell.waterDepth / 0.22)
            let inset = max(0.25, min(rect.width, rect.height) * CGFloat(0.18 * (1 - depth)))
            let wetRect = rect.insetBy(dx: inset, dy: inset)
            context.fill(
                Path(roundedRect: wetRect, cornerRadius: min(wetRect.width, wetRect.height) * 0.34),
                with: .color(Color(red: 0.055, green: 0.48 + depth * 0.14, blue: 0.65 + depth * 0.18).opacity(0.58 + depth * 0.38))
            )
            // Suspended sediment visibly clouds only the water that actually carries it.
            let concentration = min(1, cell.sediment / max(0.000_5, cell.waterDepth * 0.08))
            if concentration > 0.001 {
                context.fill(
                    Path(roundedRect: wetRect, cornerRadius: min(wetRect.width, wetRect.height) * 0.34),
                    with: .color(Color(red: 0.72, green: 0.43, blue: 0.15).opacity(0.12 + concentration * 0.46))
                )
            }

            let magnitude = hypot(cell.flowX, cell.flowY)
            // Sparse deterministic sampling keeps the actual vector direction legible.
            guard magnitude > 0.002, (coordinate.column + coordinate.row * 3) % 4 == 0 else { continue }
            let unitX = cell.flowX / magnitude
            let unitY = cell.flowY / magnitude
            let length = min(layout.cellSize.width, layout.cellSize.height) * 0.32
            let center = CGPoint(x: wetRect.midX, y: wetRect.midY)
            let tip = CGPoint(x: center.x + unitX * length, y: center.y + unitY * length)
            let perpendicular = CGPoint(x: -unitY, y: unitX)
            let back = CGPoint(x: tip.x - unitX * 3.2, y: tip.y - unitY * 3.2)
            var arrow = Path()
            arrow.move(to: center)
            arrow.addLine(to: tip)
            arrow.move(to: CGPoint(x: back.x + perpendicular.x * 2.2, y: back.y + perpendicular.y * 2.2))
            arrow.addLine(to: tip)
            arrow.addLine(to: CGPoint(x: back.x - perpendicular.x * 2.2, y: back.y - perpendicular.y * 2.2))
            context.stroke(arrow, with: .color(.white.opacity(reduceMotion ? 0.64 : 0.48)), style: StrokeStyle(lineWidth: 1.15, lineCap: .round, lineJoin: .round))
        }
    }

    /// Marks the short, local lip where visibly wet water meets a higher excavated
    /// neighbor. That neighbor may hold water below the renderer's wet threshold.
    private func drawBarrierEdges(context: inout GraphicsContext, layout: SurfaceMapLayout) {
        for barrier in world.dryExcavationBarriers() {
            guard let wet = layout.center(of: barrier.visibleWetSource),
                  let destination = layout.center(of: barrier.belowVisualWetThresholdDestination) else { continue }
            let midpoint = CGPoint(x: (wet.x + destination.x) / 2, y: (wet.y + destination.y) / 2)
            let dx = destination.x - wet.x
            let dy = destination.y - wet.y
            let length = min(layout.cellSize.width, layout.cellSize.height) * 0.30
            let magnitude = max(0.001, hypot(dx, dy))
            let perpendicular = CGPoint(x: -dy / magnitude, y: dx / magnitude)
            var lip = Path()
            lip.move(to: CGPoint(x: midpoint.x - perpendicular.x * length, y: midpoint.y - perpendicular.y * length))
            lip.addLine(to: CGPoint(x: midpoint.x + perpendicular.x * length, y: midpoint.y + perpendicular.y * length))
            context.stroke(
                lip,
                with: .color(.orange.opacity(0.52 + min(0.28, barrier.rise))),
                style: StrokeStyle(lineWidth: 1.35, lineCap: .round)
            )
        }
    }

    private func drawStroke(context: inout GraphicsContext, layout: SurfaceMapLayout) {
        guard visibleStroke.count > 1 else { return }
        var outline = Path()
        for (index, coordinate) in visibleStroke.enumerated() {
            guard let center = layout.center(of: coordinate) else { continue }
            if index == 0 { outline.move(to: center) } else { outline.addLine(to: center) }
        }
        context.stroke(
            outline,
            with: .color((brush.capturedMode == .fill ? Color.mint : Color.orange).opacity(0.78)),
            style: StrokeStyle(
                lineWidth: max(2, min(layout.cellSize.width, layout.cellSize.height) * 0.22),
                lineCap: .round,
                lineJoin: .round,
                dash: [4, 3]
            )
        )
    }

    private func drawSelection(context: inout GraphicsContext, layout: SurfaceMapLayout) {
        guard let selectedCoordinate,
              let rect = layout.rect(of: selectedCoordinate) else { return }
        context.stroke(
            Path(roundedRect: rect.insetBy(dx: 0.8, dy: 0.8), cornerRadius: 2),
            with: .color(.yellow.opacity(0.85)),
            style: StrokeStyle(lineWidth: 1.5)
        )
    }

    private func digGesture(layout: SurfaceMapLayout) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard interactionEnabled,
                      let coordinate = layout.coordinate(at: value.location),
                      world.isSafeToDig(coordinate) else { return }
                if brush.touched.isEmpty {
                    visibleStroke.removeAll(keepingCapacity: true)
                    guard let target = onEditBegan(coordinate, editMode) else { return }
                    brush.capture(target: target, mode: editMode)
                }
                let candidates: [SurfaceCoordinate]
                if let previousCoordinate = brush.previousCoordinate {
                    candidates = interpolated(from: previousCoordinate, to: coordinate)
                } else {
                    candidates = [coordinate]
                }
                let fresh = brush.takeFresh(candidates)
                if !fresh.isEmpty,
                   let target = brush.capturedTarget,
                   let mode = brush.capturedMode {
                    visibleStroke.append(contentsOf: fresh)
                    onEditCells(fresh, target, mode)
                }
                brush.previousCoordinate = coordinate
            }
            .onEnded { _ in
                let changed = interactionEnabled && !brush.touched.isEmpty
                clearGestureState(preserveOutline: false)
                if changed { onGestureEnded() }
            }
    }

    /// Ending, cancellation (reported as ending by `DragGesture`), or disabling
    /// always clears the transient brush. If disabled mid-stroke, excavations already
    /// applied remain authoritative, but no flow batch is committed.
    private func clearGestureState(preserveOutline: Bool) {
        brush.reset()
        if !preserveOutline { visibleStroke.removeAll(keepingCapacity: true) }
    }

    private func interpolated(
        from: SurfaceCoordinate,
        to: SurfaceCoordinate
    ) -> [SurfaceCoordinate] {
        let deltaColumn = to.column - from.column
        let deltaRow = to.row - from.row
        let steps = max(abs(deltaColumn), abs(deltaRow), 1)
        return (1...steps).map { step in
            SurfaceCoordinate(
                column: from.column + Int((Double(deltaColumn) * Double(step) / Double(steps)).rounded()),
                row: from.row + Int((Double(deltaRow) * Double(step) / Double(steps)).rounded())
            )
        }.filter(world.isSafeToDig)
    }
}
