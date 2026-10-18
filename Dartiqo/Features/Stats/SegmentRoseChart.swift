import SwiftUI

/// Podíl šipek na číslech 1–20. Barva na terči vychází z počtu zásahů segmentu.
struct SegmentSpread: Equatable {
    struct Slice: Identifiable, Equatable {
        var segment: Int
        var count: Int
        var share: Double
        var singles: Int
        var doubles: Int
        var triples: Int
        /// 0 je čistý single, 1 je čistý triple. Double je uprostřed.
        var depth: Double {
            guard count > 0 else { return 0 }
            return (Double(doubles) * 0.5 + Double(triples)) / Double(count)
        }
        var id: Int { segment }
    }

    var slices: [Slice]
    var bullCount: Int
    var bullOuter: Int
    var bullInner: Int
    var bullShare: Double
    /// 0 je jen vnější bull, 1 je jen vnitřní.
    var bullDepth: Double {
        guard bullCount > 0 else { return 0 }
        return Double(bullInner) / Double(bullCount)
    }
    var missCount: Int
    var total: Int
    var best: Slice?
    var worst: Slice?

    static func make(_ darts: [Dart]) -> SegmentSpread {
        var singles: [Int: Int] = [:]
        var doubles: [Int: Int] = [:]
        var triples: [Int: Int] = [:]
        var bullOuter = 0
        var bullInner = 0
        var misses = 0
        for dart in darts {
            switch dart.segment {
            case 1...20:
                switch dart.multiplier {
                case 3: triples[dart.segment, default: 0] += 1
                case 2: doubles[dart.segment, default: 0] += 1
                default: singles[dart.segment, default: 0] += 1
                }
            case 25:
                if dart.multiplier == 2 { bullInner += 1 } else { bullOuter += 1 }
            default:
                misses += 1
            }
        }
        let total = darts.count
        let bull = bullOuter + bullInner
        let slices = BoardGeometry.sectors.map { segment in
            let single = singles[segment, default: 0]
            let double = doubles[segment, default: 0]
            let triple = triples[segment, default: 0]
            let count = single + double + triple
            return Slice(
                segment: segment,
                count: count,
                share: total == 0 ? 0 : Double(count) / Double(total),
                singles: single,
                doubles: double,
                triples: triple
            )
        }
        let ranked = slices.sorted { lhs, rhs in
            if lhs.count != rhs.count { return lhs.count > rhs.count }
            let left = BoardGeometry.sectors.firstIndex(of: lhs.segment) ?? 0
            let right = BoardGeometry.sectors.firstIndex(of: rhs.segment) ?? 0
            return left < right
        }
        return SegmentSpread(
            slices: slices,
            bullCount: bull,
            bullOuter: bullOuter,
            bullInner: bullInner,
            bullShare: total == 0 ? 0 : Double(bull) / Double(total),
            missCount: misses,
            total: total,
            best: ranked.first,
            worst: ranked.last
        )
    }
}

/// Terč s polem single, pruhem triple a okrajem double. Sytost je počet zásahů.
struct SegmentRoseChart: View {
    var darts: [Dart]
    var title: String
    /// Jen terč, bez popisků. Hodí se do řádku, který vede dál.
    var compact: Bool = false

    @State private var selected: Int?

    private var spread: SegmentSpread { SegmentSpread.make(darts) }
    /// Single je světlá žlutá, double bronzová, triple tmavá.
    private let singleBed = RGB(r: 0.99, g: 0.88, b: 0.42)
    private let doubleBed = RGB(r: 0.84, g: 0.52, b: 0.12)
    private let tripleBed = RGB(r: 0.40, g: 0.20, b: 0.05)

    var body: some View {
        if compact {
            plot
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        } else {
            card
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                extreme("Nejmíň", spread.worst, tint: .primary, caption: .secondary)
                Spacer(minLength: 12)
                extreme("Nejvíc", spread.best, tint: doubleBed.color, caption: doubleBed.color.opacity(0.8), trailing: true)
            }

            plot
                .frame(maxWidth: 440)
                .frame(maxWidth: .infinity)

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                bullBadge
            }

            HStack(spacing: 14) {
                legendSwatch(singleBed.color, "Single")
                legendSwatch(doubleBed.color, "Double")
                legendSwatch(tripleBed.color, "Triple")
            }

            Text(readout)
                .font(.caption)
                .foregroundStyle(selected == nil ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.snappy, value: selected)
        }
        .padding(16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Theme.stroke, lineWidth: 0.5)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityHint("Klepni na výseč, nebo přejeď nahoru a dolů mezi segmenty.")
        .accessibilityAdjustableAction { direction in
            let order = BoardGeometry.sectors
            let current = selected.flatMap { order.firstIndex(of: $0) } ?? -1
            let next = direction == .increment
                ? (current + 1) % order.count
                : (current - 1 + order.count) % order.count
            selected = order[next]
        }
        .sensoryFeedback(.selection, trigger: selected)
        .onChange(of: spread.total) { _, _ in selected = nil }
    }

    private var plot: some View {
        Canvas { context, size in
            draw(in: context, size: size)
        }
        .aspectRatio(1, contentMode: .fit)
        .contentShape(Rectangle())
        .overlay {
            GeometryReader { geo in
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        SpatialTapGesture().onEnded { value in
                            guard !compact else { return }
                            let layout = BoardFace.layout(in: geo.size)
                            guard let segment = segment(at: value.location, center: layout.center, radius: layout.radius) else { return }
                            selected = selected == segment ? nil : segment
                        }
                    )
            }
        }
    }

    private var readout: String {
        if let selected, let slice = spread.slices.first(where: { $0.segment == selected }) {
            return "\(selected) · S \(slice.singles) · D \(slice.doubles) · T \(slice.triples) · \(percent(slice.share))"
        }
        return "Světlá plocha je single, tmavý pruh triple a okraj double. Sytost je počet zásahů. Klepni na segment."
    }

    private var accessibilitySummary: String {
        if let selected, let slice = spread.slices.first(where: { $0.segment == selected }) {
            return "\(title). Segment \(selected), \(slice.count) šipek, \(percent(slice.share)). Single \(slice.singles), double \(slice.doubles), triple \(slice.triples). Bull \(percent(spread.bullShare))."
        }
        guard let best = spread.best, let worst = spread.worst else { return title }
        return "\(title). Světlá plocha je single, tmavý pruh triple a okraj double. Sytost je počet zásahů. Nejvíc segment \(best.segment), \(percent(best.share)). Nejmíň segment \(worst.segment), \(percent(worst.share)). Bull \(percent(spread.bullShare))."
    }

    private var bullBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(spread.bullInner > 0 ? tripleBed.color : (spread.bullOuter > 0 ? doubleBed.color : Color.primary.opacity(0.28)))
                .frame(width: 9, height: 9)
            Text("Bull")
                .foregroundStyle(.secondary)
            Text(percent(spread.bullShare))
                .foregroundStyle(.primary)
                .monospacedDigit()
        }
        .font(.caption.weight(.semibold))
        .accessibilityElement(children: .combine)
    }

    private func extreme(_ title: String, _ slice: SegmentSpread.Slice?, tint: Color, caption: Color, trailing: Bool = false) -> some View {
        VStack(alignment: trailing ? .trailing : .leading, spacing: 1) {
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(caption)
            Text(slice.map { percent($0.share) } ?? "—")
                .font(.system(.title3, design: .rounded).weight(.bold))
                .monospacedDigit()
                .foregroundStyle(tint)
        }
    }

    private func legendSwatch(_ color: Color, _ title: String) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(title)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)
    }

    /// Nejhranější pole — single, double, triple i bull — je plná sytost.
    private var heatPeak: Int {
        let beds = spread.slices.flatMap { [$0.singles, $0.doubles, $0.triples] }
        return max(beds.max() ?? 0, spread.bullOuter, spread.bullInner, 1)
    }

    private func bedFill(_ color: Color, count: Int, emphasized: Bool) -> Color {
        if count <= 0 { return Color.primary.opacity(emphasized ? 0.08 : 0.04) }
        let share = Double(count) / Double(heatPeak)
        let opacity = (0.45 + 0.55 * share) * (emphasized ? 1 : 0.32)
        return color.opacity(opacity)
    }

    private func percent(_ share: Double) -> String {
        let value = (share * 100).formatted(.number.precision(.fractionLength(1)))
        return "\(value) %"
    }

    private func draw(in context: GraphicsContext, size: CGSize) {
        let layout = BoardFace.layout(in: size)
        let center = layout.center
        let radius = layout.radius
        context.fill(BoardFace.disk(factor: 1.16, center: center, radius: radius), with: .color(Color.primary.opacity(0.06)))

        for slice in spread.slices {
            let emphasized = selected == nil || slice.segment == selected
            fillBed(slice.segment, multiplier: 1, count: slice.singles, color: singleBed.color, emphasized: emphasized, context: context, center: center, radius: radius)
            fillBed(slice.segment, multiplier: 3, count: slice.triples, color: tripleBed.color, emphasized: emphasized, context: context, center: center, radius: radius)
            fillBed(slice.segment, multiplier: 2, count: slice.doubles, color: doubleBed.color, emphasized: emphasized, context: context, center: center, radius: radius)
        }

        let bullEmphasized = selected == nil
        context.fill(
            BoardFace.disk(factor: BoardGeometry.outerBull, center: center, radius: radius),
            with: .color(bedFill(doubleBed.color, count: spread.bullOuter, emphasized: bullEmphasized))
        )
        context.fill(
            BoardFace.disk(factor: BoardGeometry.innerBull, center: center, radius: radius),
            with: .color(bedFill(tripleBed.color, count: spread.bullInner, emphasized: bullEmphasized))
        )

        drawRings(in: context, center: center, radius: radius)
        if let selected, let index = BoardGeometry.sectors.firstIndex(of: selected) {
            let bounds = BoardFace.angles(for: index)
            context.stroke(
                BoardFace.ring(inner: BoardGeometry.outerBull, outer: 1, start: bounds.start, end: bounds.end, center: center, radius: radius),
                with: .color(Color.primary),
                lineWidth: max(1.5, radius * 0.012)
            )
        }
        guard !compact else { return }
        for (index, slice) in spread.slices.enumerated() {
            let angle = (-90 + Double(index) * 18) * Double.pi / 180
            let spot = CGPoint(x: center.x + radius * 1.09 * cos(angle), y: center.y + radius * 1.09 * sin(angle))
            let isBest = slice.segment == spread.best?.segment && slice.count > 0
            let isSelected = slice.segment == selected
            let color: Color = isSelected ? Color.primary : (isBest ? doubleBed.color : Color.primary.opacity(0.72))
            context.draw(
                Text("\(slice.segment)")
                    .font(.system(size: max(11, radius * 0.072), weight: isSelected || isBest ? .heavy : .bold, design: .rounded))
                    .foregroundColor(color),
                at: spot
            )
        }
    }

    private func fillBed(_ segment: Int, multiplier: Int, count: Int, color: Color, emphasized: Bool, context: GraphicsContext, center: CGPoint, radius: CGFloat) {
        guard let path = BoardFace.bedPath(segment: segment, multiplier: multiplier, center: center, radius: radius) else { return }
        context.fill(path, with: .color(bedFill(color, count: count, emphasized: emphasized)))
    }

    /// Paprsky a kružnice doublu, triplu a bullu. Leží nad barvou, ať je pole pořád čitelné.
    private func drawRings(in context: GraphicsContext, center: CGPoint, radius: CGFloat) {
        let spoke = max(0.8, radius * 0.007)
        let wire = max(1.35, radius * 0.013)
        for index in 0..<20 {
            let bounds = BoardFace.angles(for: index)
            context.stroke(
                BoardFace.ring(inner: BoardGeometry.outerBull, outer: 1, start: bounds.start, end: bounds.end, center: center, radius: radius),
                with: .color(Color.primary.opacity(0.28)),
                lineWidth: spoke
            )
        }
        for factor in [1.0, BoardGeometry.doubleInner, BoardGeometry.tripleOuter, BoardGeometry.tripleInner] {
            context.stroke(
                BoardFace.disk(factor: factor, center: center, radius: radius),
                with: .color(Color.primary.opacity(0.55)),
                lineWidth: wire
            )
        }
        for factor in [BoardGeometry.outerBull, BoardGeometry.innerBull] {
            context.stroke(
                BoardFace.disk(factor: factor, center: center, radius: radius),
                with: .color(Color.primary.opacity(0.45)),
                lineWidth: max(1, radius * 0.01)
            )
        }
    }

    /// Číselník je až za skórovací kružnicí, klepnutí tam pořád vybere segment.
    private func segment(at location: CGPoint, center: CGPoint, radius: CGFloat) -> Int? {
        guard radius > 0 else { return nil }
        let x = Double(location.x - center.x) / Double(radius)
        let y = Double(location.y - center.y) / Double(radius)
        let distance = hypot(x, y)
        guard distance > BoardGeometry.outerBull, distance <= 1.18 else { return nil }
        let scale = min(distance, 0.99) / distance
        let dart = BoardGeometry.hit(x: x * scale, y: y * scale)
        return (1...20).contains(dart.segment) ? dart.segment : nil
    }
}

private struct RGB {
    var r, g, b: Double

    func mix(_ other: RGB, _ amount: Double) -> RGB {
        let t = min(1, max(0, amount))
        return RGB(r: r + (other.r - r) * t, g: g + (other.g - g) * t, b: b + (other.b - b) * t)
    }

    var color: Color { Color(red: r, green: g, blue: b) }
}

#if DEBUG
#Preview("Rozložení") {
    let darts = BoardGeometry.sectors.enumerated().flatMap { index, segment -> [Dart] in
        let count = segment == 20 ? 48 : (index % 6) + 2
        let multiplier = index % 3 == 0 ? 3 : (index % 3 == 1 ? 1 : 2)
        return Array(repeating: Dart(segment, multiplier, x: 0, y: 0), count: count)
    } + Array(repeating: Dart(25, 2, x: 0, y: 0), count: 7)
    return SegmentRoseChart(darts: darts, title: "Podíl zásahů")
        .padding()
        .background(Color(white: 0.94))
}
#endif
