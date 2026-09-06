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
        let gesture = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.tapped(_:))
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

        @objc func tapped(_ gesture: UITapGestureRecognizer) {
            guard let view, cellCount > 0 else { return }
            let point = gesture.location(in: view)
            guard let cell = CreekPicking.cell(
                at: point,
                viewport: view.bounds.size,
                cellCount: cellCount
            ) else { return }
            onPlaceStone(cell)
        }
    }
}

enum CreekPicking {
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
    private let started = CACurrentMediaTime()

    func attach(to view: MTKView) {
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
        vertices = CreekMesh.make(projection: projection)
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let pipeline, let queue,
              let drawable = view.currentDrawable,
              let pass = view.currentRenderPassDescriptor,
              !vertices.isEmpty,
              let command = queue.makeCommandBuffer(),
              let encoder = command.makeRenderCommandEncoder(descriptor: pass) else {
            return
        }
        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBytes(
            vertices,
            length: MemoryLayout<CreekVertex>.stride * vertices.count,
            index: 0
        )
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
    static func make(projection: SimulationProjection) -> [CreekVertex] {
        guard !projection.cells.isEmpty else { return [] }
        var result: [CreekVertex] = []
        let anchors = CreekLayout.anchors(count: projection.cells.count)
        let bank = SIMD4<Float>(0.16, 0.24, 0.12, 1)
        let dampBank = SIMD4<Float>(0.22, 0.27, 0.15, 1)
        let gravel = SIMD4<Float>(0.45, 0.38, 0.24, 1)
        let shallowWater = SIMD4<Float>(0.10, 0.52, 0.60, 0.72)
        let rock = SIMD4<Float>(0.27, 0.29, 0.27, 1)

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

        let waterWidths = projection.cells.map {
            0.13 + Float(min(0.34, $0.waterDepth)) * 0.42
        }
        ribbon(
            &result,
            points: anchors,
            widths: waterWidths,
            color: shallowWater,
            water: 1
        )

        for (index, cell) in projection.cells.enumerated()
        where cell.rockResistance > 0 {
            let shadow = anchors[index] + SIMD2<Float>(0.018, -0.025)
            stone(&result, center: shadow, radius: 0.105, color: [0.04, 0.05, 0.04, 0.42])
            stone(&result, center: anchors[index], radius: 0.10, color: rock)
        }
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
