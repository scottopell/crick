import MetalKit
import SwiftUI

struct CreekSceneView: UIViewRepresentable {
    let projection: SimulationProjection
    let onPlaceStone: (Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPlaceStone: onPlaceStone)
    }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero)
        view.device = MTLCreateSystemDefaultDevice()
        view.colorPixelFormat = .bgra8Unorm_srgb
        view.clearColor = MTLClearColor(red: 0.07, green: 0.11, blue: 0.08, alpha: 1)
        view.preferredFramesPerSecond = 60
        view.enableSetNeedsDisplay = false
        view.isPaused = false
        view.delegate = context.coordinator.renderer
        context.coordinator.renderer.attach(to: view)
        let gesture = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.dragged(_:))
        )
        view.addGestureRecognizer(gesture)
        context.coordinator.view = view
        context.coordinator.update(projection: projection)
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {
        context.coordinator.onPlaceStone = onPlaceStone
        context.coordinator.update(projection: projection)
    }

    @MainActor
    final class Coordinator: NSObject {
        let renderer = CreekRenderer()
        weak var view: MTKView?
        var onPlaceStone: (Int) -> Void
        private var cellCount = 0

        init(onPlaceStone: @escaping (Int) -> Void) {
            self.onPlaceStone = onPlaceStone
        }

        func update(projection: SimulationProjection) {
            cellCount = projection.cells.count
            renderer.update(projection: projection)
        }

        @objc func dragged(_ gesture: UIPanGestureRecognizer) {
            guard let view, cellCount > 0 else { return }
            let point = gesture.location(in: view)
            switch gesture.state {
            case .began:
                guard CreekPicking.isNearStone(
                    point: point,
                    viewport: view.bounds.size,
                    projection: renderer.projection
                ) else { return }
                renderer.beginDrag(at: point, viewport: view.bounds.size)
                UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
            case .changed:
                guard renderer.isDragging else { return }
                renderer.moveDrag(to: point, viewport: view.bounds.size)
            case .ended:
                guard renderer.isDragging else { return }
                renderer.endDrag()
                guard let cell = CreekPicking.cell(
                    at: point,
                    viewport: view.bounds.size,
                    cellCount: cellCount
                ) else { return }
                onPlaceStone(cell)
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            default:
                renderer.endDrag()
            }
        }
    }
}

enum CreekPicking {
    static let bankStone = SIMD2<Float>(-0.68, -0.72)

    static func isNearStone(
        point: CGPoint,
        viewport: CGSize,
        projection: SimulationProjection?
    ) -> Bool {
        guard viewport.width > 0, viewport.height > 0 else { return false }
        let scenePoint = SIMD2<Float>(
            Float(point.x / viewport.width) * 2 - 1,
            1 - Float(point.y / viewport.height) * 2
        )
        let placed = projection?.cells.first(where: { $0.rockResistance > 0 })
        let stone = placed.map { CreekLayout.anchors(count: projection!.cells.count)[$0.id] }
            ?? bankStone
        return distance(scenePoint, stone) < 0.25
    }

    static func cell(
        at point: CGPoint,
        viewport: CGSize,
        cellCount: Int
    ) -> Int? {
        guard cellCount > 0, viewport.width > 0, viewport.height > 0 else {
            return nil
        }
        let scenePoint = SIMD2<Float>(
            Float(point.x / viewport.width) * 2 - 1,
            1 - Float(point.y / viewport.height) * 2
        )
        let anchors = CreekLayout.anchors(count: cellCount)
        guard let nearest = anchors.enumerated().min(by: {
            distance_squared($0.element, scenePoint)
                < distance_squared($1.element, scenePoint)
        }), distance(nearest.element, scenePoint) < 0.34 else { return nil }
        return nearest.offset
    }
}

private struct CreekVertex {
    var position: SIMD2<Float>
    var color: SIMD4<Float>
    var water: Float
}

@MainActor
final class CreekRenderer: NSObject, MTKViewDelegate {
    private var queue: MTLCommandQueue?
    private var pipeline: MTLRenderPipelineState?
    private var vertices: [CreekVertex] = []
    private var vertexBuffer: MTLBuffer?
    private weak var view: MTKView?
    private(set) var projection: SimulationProjection?
    private(set) var isDragging = false
    private var dragPosition: SIMD2<Float>?
    private var priorDepths: [Double] = []
    private var targetDepths: [Double] = []
    private var transitionStarted = CACurrentMediaTime()
    private let started = CACurrentMediaTime()

    func attach(to view: MTKView) {
        self.view = view
        guard MemoryLayout<CreekVertex>.stride == 48 else {
            showFailure(in: view)
            return
        }
        guard let device = view.device,
              let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary(),
              let vertex = library.makeFunction(name: "creekVertex"),
              let fragment = library.makeFunction(name: "creekFragment") else {
            showFailure(in: view)
            return
        }
        self.queue = queue
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        do {
            pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            showFailure(in: view)
        }
    }

    private func showFailure(in view: MTKView) {
        view.isPaused = true
        let label = UILabel()
        label.text = "This device could not draw the creek."
        label.textColor = .white
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        label.accessibilityIdentifier = "creek-render-failure"
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    func update(projection: SimulationProjection) {
        let incoming = projection.cells.map(\.waterDepth)
        if targetDepths.isEmpty {
            priorDepths = incoming
        } else if incoming != targetDepths {
            priorDepths = displayedDepths(at: CACurrentMediaTime())
            transitionStarted = CACurrentMediaTime()
        }
        targetDepths = incoming
        self.projection = projection
        rebuild()
    }

    func beginDrag(at point: CGPoint, viewport: CGSize) {
        isDragging = true
        moveDrag(to: point, viewport: viewport)
    }

    func moveDrag(to point: CGPoint, viewport: CGSize) {
        dragPosition = SIMD2(
            Float(point.x / viewport.width) * 2 - 1,
            1 - Float(point.y / viewport.height) * 2
        )
        rebuild()
    }

    func endDrag() {
        isDragging = false
        dragPosition = nil
        rebuild()
    }

    private func rebuild() {
        guard let projection else { return }
        vertices = CreekMesh.make(
            projection: projection,
            displayedDepths: displayedDepths(at: CACurrentMediaTime()),
            draggedStone: dragPosition
        )
        guard let device = view?.device else { return }
        vertexBuffer = device.makeBuffer(
            bytes: vertices,
            length: MemoryLayout<CreekVertex>.stride * vertices.count,
            options: .storageModeShared
        )
    }

    private func displayedDepths(at now: CFTimeInterval) -> [Double] {
        guard priorDepths.count == targetDepths.count else { return targetDepths }
        let raw = min(1, max(0, (now - transitionStarted) / 0.7))
        let eased = 1 - pow(1 - raw, 3)
        return zip(priorDepths, targetDepths).map { prior, target in
            prior + (target - prior) * eased
        }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        if CACurrentMediaTime() - transitionStarted < 0.7 {
            rebuild()
        }
        guard let pipeline, let queue,
              let drawable = view.currentDrawable,
              let pass = view.currentRenderPassDescriptor,
              !vertices.isEmpty,
              let vertexBuffer,
              let command = queue.makeCommandBuffer(),
              let encoder = command.makeRenderCommandEncoder(descriptor: pass) else {
            return
        }
        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        var time = Float(CACurrentMediaTime() - started)
        encoder.setFragmentBytes(&time, length: MemoryLayout<Float>.size, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertices.count)
        encoder.endEncoding()
        command.present(drawable)
        command.commit()
    }
}

enum CreekLayout {
    static func anchors(count: Int) -> [SIMD2<Float>] {
        guard count > 0 else { return [] }
        return (0..<count).map { index in
            let t = count == 1 ? 0.5 : Float(index) / Float(count - 1)
            let x = -0.86 + t * 1.72
            let y = 0.58 - t * 1.16 + sin(t * .pi * 1.45) * 0.18
            return SIMD2(x, y)
        }
    }
}

private enum CreekMesh {
    static func make(
        projection: SimulationProjection,
        displayedDepths: [Double]? = nil,
        draggedStone: SIMD2<Float>? = nil
    ) -> [CreekVertex] {
        guard !projection.cells.isEmpty else { return [] }
        var result: [CreekVertex] = []
        let anchors = CreekLayout.anchors(count: projection.cells.count)
        let bank = SIMD4<Float>(0.115, 0.205, 0.095, 1)
        let dampBank = SIMD4<Float>(0.255, 0.315, 0.19, 1)
        let gravel = SIMD4<Float>(0.49, 0.42, 0.27, 1)
        let rock = SIMD4<Float>(0.20, 0.225, 0.215, 1)

        quad(&result, x0: -1, x1: 1, y0: -1, y1: 1, color: bank)
        ribbon(&result, points: anchors, widths: anchors.map { _ in 0.42 }, color: dampBank)
        ribbon(&result, points: anchors, widths: anchors.map { _ in 0.33 }, color: gravel)

        for index in 0..<30 {
            let t = Float(index % 15) / 14
            let base = sample(anchors, t: t)
            let side: Float = index < 15 ? -1 : 1
            let offset = normal(anchors, t: t) * side * (0.22 + Float((index * 7) % 5) * 0.018)
            pebble(
                &result,
                center: base + offset,
                radius: 0.012 + Float((index * 11) % 4) * 0.005,
                color: index.isMultiple(of: 3)
                    ? SIMD4<Float>(0.56, 0.50, 0.36, 1)
                    : SIMD4<Float>(0.34, 0.32, 0.23, 1)
            )
        }

        let depths = displayedDepths ?? projection.cells.map(\.waterDepth)
        let waterWidths = depths.map {
            0.13 + Float(min(0.34, $0)) * 0.42
        }
        for index in 0..<(anchors.count - 1) {
            let depth = Float((depths[index] + depths[index + 1]) * 0.5)
            let normalizedDepth = min(1, max(0, (depth - 0.12) / 0.24))
            let waterColor = SIMD4<Float>(
                0.11 - normalizedDepth * 0.045,
                0.56 - normalizedDepth * 0.12,
                0.66 - normalizedDepth * 0.07,
                0.69 + normalizedDepth * 0.16
            )
            ribbonSegment(
                &result,
                points: anchors,
                widths: waterWidths,
                index: index,
                color: waterColor,
                water: normalizedDepth + 0.01
            )
        }

        let targetCell = projection.poolObjective?.targetCell
        if let targetCell, anchors.indices.contains(targetCell) {
            let holding = projection.poolObjective?.status == .holding
            ring(
                &result,
                center: anchors[targetCell],
                radius: 0.16,
                color: holding
                    ? SIMD4<Float>(0.48, 0.92, 0.70, 0.48)
                    : SIMD4<Float>(0.90, 0.82, 0.45, 0.28)
            )
        }

        let placedIndex = projection.cells.firstIndex { $0.rockResistance > 0 }
        let authoritativeStone = placedIndex.map { anchors[$0] }
        let stonePosition = draggedStone
            ?? authoritativeStone
            ?? CreekPicking.bankStone
        if placedIndex == nil {
            ring(
                &result,
                center: stonePosition,
                radius: 0.16,
                color: [0.82, 0.90, 0.72, 0.22]
            )
        }
        let shadow = stonePosition + SIMD2<Float>(0.026, -0.035)
        stone(&result, center: shadow, radius: 0.12, color: [0.02, 0.03, 0.02, 0.58])
        stone(&result, center: stonePosition, radius: 0.11, color: rock)
        return result
    }

    private static func ribbon(
        _ vertices: inout [CreekVertex],
        points: [SIMD2<Float>],
        widths: [Float],
        color: SIMD4<Float>,
        water: Float = 0
    ) {
        guard points.count >= 2 else { return }
        for index in 0..<(points.count - 1) {
            let direction = simd_normalize(points[index + 1] - points[index])
            let perpendicular = SIMD2(-direction.y, direction.x)
            let nextDirection = index + 2 < points.count
                ? simd_normalize(points[index + 2] - points[index + 1])
                : direction
            let nextPerpendicular = SIMD2(-nextDirection.y, nextDirection.x)
            let a = points[index] + perpendicular * widths[index]
            let b = points[index] - perpendicular * widths[index]
            let c = points[index + 1] - nextPerpendicular * widths[index + 1]
            let d = points[index + 1] + nextPerpendicular * widths[index + 1]
            polygonQuad(&vertices, a, b, c, d, color: color, water: water)
        }
    }

    private static func ribbonSegment(
        _ vertices: inout [CreekVertex],
        points: [SIMD2<Float>], widths: [Float], index: Int,
        color: SIMD4<Float>, water: Float
    ) {
        let direction = simd_normalize(points[index + 1] - points[index])
        let perpendicular = SIMD2(-direction.y, direction.x)
        let nextDirection = index + 2 < points.count
            ? simd_normalize(points[index + 2] - points[index + 1])
            : direction
        let nextPerpendicular = SIMD2(-nextDirection.y, nextDirection.x)
        polygonQuad(
            &vertices,
            points[index] + perpendicular * widths[index],
            points[index] - perpendicular * widths[index],
            points[index + 1] - nextPerpendicular * widths[index + 1],
            points[index + 1] + nextPerpendicular * widths[index + 1],
            color: color,
            water: water
        )
    }

    private static func ring(
        _ vertices: inout [CreekVertex],
        center: SIMD2<Float>, radius: Float, color: SIMD4<Float>
    ) {
        let segments = 24
        let inner = radius * 0.83
        for index in 0..<segments {
            let a0 = Float(index) / Float(segments) * .pi * 2
            let a1 = Float(index + 1) / Float(segments) * .pi * 2
            polygonQuad(
                &vertices,
                center + SIMD2(cos(a0), sin(a0)) * inner,
                center + SIMD2(cos(a0), sin(a0)) * radius,
                center + SIMD2(cos(a1), sin(a1)) * radius,
                center + SIMD2(cos(a1), sin(a1)) * inner,
                color: color,
                water: 0
            )
        }
    }

    private static func sample(_ points: [SIMD2<Float>], t: Float) -> SIMD2<Float> {
        let scaled = t * Float(points.count - 1)
        let index = min(points.count - 2, Int(scaled))
        return simd_mix(points[index], points[index + 1], SIMD2(repeating: scaled - Float(index)))
    }

    private static func normal(_ points: [SIMD2<Float>], t: Float) -> SIMD2<Float> {
        let scaled = t * Float(points.count - 1)
        let index = min(points.count - 2, Int(scaled))
        let direction = simd_normalize(points[index + 1] - points[index])
        return SIMD2(-direction.y, direction.x)
    }

    private static func pebble(
        _ vertices: inout [CreekVertex],
        center: SIMD2<Float>, radius: Float, color: SIMD4<Float>
    ) {
        stone(&vertices, center: center, radius: radius, color: color)
    }

    private static func polygonQuad(
        _ vertices: inout [CreekVertex],
        _ a: SIMD2<Float>, _ b: SIMD2<Float>,
        _ c: SIMD2<Float>, _ d: SIMD2<Float>,
        color: SIMD4<Float>, water: Float
    ) {
        let va = CreekVertex(position: a, color: color, water: water)
        let vb = CreekVertex(position: b, color: color, water: water)
        let vc = CreekVertex(position: c, color: color, water: water)
        let vd = CreekVertex(position: d, color: color, water: water)
        vertices += [va, vb, vc, va, vc, vd]
    }

    private static func quad(
        _ vertices: inout [CreekVertex],
        x0: Float, x1: Float, y0: Float, y1: Float,
        color: SIMD4<Float>, water: Float = 0
    ) {
        let a = CreekVertex(position: [x0, y0], color: color, water: water)
        let b = CreekVertex(position: [x1, y0], color: color, water: water)
        let c = CreekVertex(position: [x1, y1], color: color, water: water)
        let d = CreekVertex(position: [x0, y1], color: color, water: water)
        vertices += [a, b, c, a, c, d]
    }

    private static func stone(
        _ vertices: inout [CreekVertex],
        center: SIMD2<Float>, radius: Float, color: SIMD4<Float>
    ) {
        let points: [SIMD2<Float>] = [
            [-0.95, -0.25], [-0.55, -0.90], [0.40, -0.82],
            [0.92, -0.20], [0.62, 0.72], [-0.30, 0.88],
        ].map { center + $0 * radius }
        for index in 1..<(points.count - 1) {
            vertices += [
                CreekVertex(position: points[0], color: color, water: 0),
                CreekVertex(position: points[index], color: color, water: 0),
                CreekVertex(position: points[index + 1], color: color, water: 0),
            ]
        }
    }
}
