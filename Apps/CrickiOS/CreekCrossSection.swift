import SwiftUI

struct CreekCrossSection: View {
    let projection: SimulationProjection
    let placeRock: (Int) -> Void

    private let chartHeight = 190.0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Upstream", systemImage: "arrow.right")
                Spacer()
                Text("Downstream")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)

            GeometryReader { geometry in
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(projection.cells) { cell in
                        cellButton(cell, width: cellWidth(in: geometry.size.width))
                    }
                }
            }
            .frame(height: chartHeight)
            .background(
                LinearGradient(
                    colors: [.cyan.opacity(0.12), .blue.opacity(0.04)],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                in: RoundedRectangle(cornerRadius: 16)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(.blue.opacity(0.18))
            }

            Text("Tap a creek cell to place a rock. Then advance fixed ticks to watch water pool on its upstream side and flow change downstream.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("creek-cross-section")
    }

    private func cellButton(_ cell: CellProjection, width: Double) -> some View {
        let scale = verticalScale
        let bedHeight = max(16, (cell.bedElevation - minimumBed) * scale + 20)
        let waterHeight = max(2, cell.waterDepth * scale)
        let transfer = projection.waterTransfers.indices.contains(cell.id)
            ? projection.waterTransfers[cell.id]
            : nil

        return Button {
            placeRock(cell.id)
        } label: {
            VStack(spacing: 2) {
                if let transfer {
                    Text("→ \(transfer.formatted(.number.precision(.fractionLength(2))))")
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundStyle(.blue)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                } else {
                    Text(" ").font(.system(size: 8))
                }
                Spacer(minLength: 0)
                ZStack(alignment: .bottom) {
                    Rectangle()
                        .fill(.brown.gradient)
                        .frame(height: bedHeight)
                    Rectangle()
                        .fill(.blue.opacity(0.68))
                        .frame(height: waterHeight)
                        .offset(y: -bedHeight)
                    Image(systemName: cell.rockResistance > 0
                        ? "hexagon.fill" : "plus.circle.fill")
                        .foregroundStyle(cell.rockResistance > 0
                            ? AnyShapeStyle(.gray.gradient)
                            : AnyShapeStyle(.white.opacity(0.72)))
                        .font(.system(size: min(width * 0.62, 30)))
                        .shadow(color: .black.opacity(0.16), radius: 1)
                        .offset(y: -bedHeight + 4)
                }
                .frame(height: bedHeight + waterHeight)
                Text("\(cell.id)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.primary)
            }
            .frame(width: width, height: chartHeight - 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("creek-cell-\(cell.id)")
        .accessibilityLabel("Cell \(cell.id), water depth \(formatted(cell.waterDepth)), rock resistance \(formatted(cell.rockResistance))")
        .accessibilityHint("Places a rock in this cell")
    }

    private var minimumBed: Double {
        projection.cells.map(\.bedElevation).min() ?? 0
    }

    private var verticalScale: Double {
        let maximumSurface = projection.cells.map {
            $0.bedElevation + $0.waterDepth
        }.max() ?? 1
        let range = max(0.1, maximumSurface - minimumBed)
        return 125 / range
    }

    private func cellWidth(in totalWidth: Double) -> Double {
        let gaps = Double(max(0, projection.cells.count - 1)) * 3
        return max(34, (totalWidth - gaps) / Double(projection.cells.count))
    }

    private func formatted(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(3)))
    }
}

struct RockEffectCard: View {
    let effect: RockEffectProjection

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Observed around selected rock", systemImage: "water.waves")
                .font(.headline)
            Text("Over the last \(effect.elapsedTicks) fixed ticks, cell \(effect.cell) resisted \((effect.resistance * 100).formatted(.number.precision(.fractionLength(0))))% of local conductivity.")
            LabeledContent("Upstream-side depth change", value: signed(effect.upstreamDepthChange))
                .accessibilityIdentifier("upstream-depth-change")
            if let downstream = effect.downstreamDepthChange {
                LabeledContent("Next downstream cell", value: signed(downstream))
            }
            if let flow = effect.flowPastRock {
                LabeledContent("Flow past rock", value: flow.formatted(.number.precision(.fractionLength(4))))
            }
        }
        .font(.subheadline)
        .padding(12)
        .background(.blue.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Observed around selected rock over \(effect.elapsedTicks) fixed ticks. Upstream-side depth change \(signed(effect.upstreamDepthChange)). Next downstream cell \(effect.downstreamDepthChange.map(signed) ?? "unavailable"). Flow past rock \(effect.flowPastRock?.formatted(.number.precision(.fractionLength(4))) ?? "unavailable").")
        .accessibilityIdentifier("rock-effect-card")
    }

    private func signed(_ value: Double) -> String {
        value.formatted(
            .number.sign(strategy: .always()).precision(.fractionLength(4))
        )
    }
}
