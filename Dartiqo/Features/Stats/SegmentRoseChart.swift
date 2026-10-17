import SwiftUI

/// Podíl šipek na číslech 1–20. Nejplnější segment sahá na vnější kružnici,
/// ostatní výseče zůstávají vidět i při malém počtu hodů.
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

/// Růžicový graf v pořadí terče. 20 je nahoře, čísla jdou po směru hodin.
struct SegmentRoseChart: View {
    var darts: [Dart]
    var title: String
    /// Jen výseče, bez popisků. Hodí se do řádku, který vede dál.
    var compact: Bool = false

    @State private var selected: Int?

    private var spread: SegmentSpread { SegmentSpread.make(darts) }
    private let gold = Color(red: 0.91, green: 0.69, blue: 0.24)
    private let canvas = Color(red: 0.07, green: 0.09, blue: 0.14)
    /// Čistý single je světlý, double uprostřed, čistý triple tmavý.
    private let bedLight = RGB(r: 0.99, g: 0.88, b: 0.42)
    private let bedMid = RGB(r: 0.84, g: 0.52, b: 0.12)
    private let bedDark = RGB(r: 0.40, g: 0.20, b: 0.05)

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
                extreme("Nejmíň", spread.worst, tint: .white.opacity(0.78), caption: .white.opacity(0.42))
                Spacer(minLength: 12)
                extreme("Nejvíc", spread.best, tint: gold, caption: gold.opacity(0.8), trailing: true)
            }

            plot
                .frame(maxWidth: 440)
                .frame(maxWidth: .infinity)

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Spacer(minLength: 8)
                bullBadge
            }

            HStack(spacing: 14) {
                legendSwatch(0, "Single")
                legendSwatch(0.5, "Double")
                legendSwatch(1, "Triple")
            }

            Text(readout)
                .font(.caption)
                .foregroundStyle(selected == nil ? .white.opacity(0.48) : .white.opacity(0.82))
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.snappy, value: selected)
        }
        .padding(16)
        .background(canvas, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
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
                            let layout = RoseGeometry(size: geo.size, compact: compact)
                            guard let index = layout.segmentIndex(at: value.location) else { return }
                            let segment = BoardGeometry.sectors[index]
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
        return "Plocha je single, tmavý pruh triple a okraj double. Klepni na výseč pro počty."
    }

    private var accessibilitySummary: String {
        if let selected, let slice = spread.slices.first(where: { $0.segment == selected }) {
            return "\(title). Segment \(selected), \(slice.count) šipek, \(percent(slice.share)). Single \(slice.singles), double \(slice.doubles), triple \(slice.triples). Bull \(percent(spread.bullShare))."
        }
        guard let best = spread.best, let worst = spread.worst else { return title }
        return "\(title). Plocha je single, tmavý pruh triple a okraj double. Nejvíc segment \(best.segment), \(percent(best.share)). Nejmíň segment \(worst.segment), \(percent(worst.share)). Bull \(percent(spread.bullShare))."
    }

    private var bullBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(spread.bullCount > 0 ? bedColor(spread.bullDepth) : Color.white.opacity(0.28))
                .frame(width: 9, height: 9)
            Text("Bull")
                .foregroundStyle(.white.opacity(0.55))
            Text(percent(spread.bullShare))
                .foregroundStyle(.white.opacity(0.88))
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

    private func legendSwatch(_ depth: Double, _ title: String) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(bedColor(depth))
                .frame(width: 8, height: 8)
            Text(title)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.white.opacity(0.62))
    }

    /// Světlá žlutá pro single, bronzová uprostřed, tmavá pro triple.
    private func bedColor(_ depth: Double, emphasized: Bool = true) -> Color {
        let t = min(1, max(0, depth))
        let base = t < 0.5
            ? bedLight.mix(bedMid, t / 0.5)
            : bedMid.mix(bedDark, (t - 0.5) / 0.5)
        let shown = emphasized ? base : base.mix(RGB(r: 0.07, g: 0.09, b: 0.14), 0.5)
        return shown.color
    }

    private func percent(_ share: Double) -> String {
        let value = (share * 100).formatted(.number.precision(.fractionLength(1)))
        return "\(value) %"
    }

    private func draw(in context: GraphicsContext, size: CGSize) {
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(canvas))
        let layout = RoseGeometry(size: size, compact: compact)
        let rings = 4
        let maxCount = max(spread.slices.map(\.count).max() ?? 0, 1)
        for (index, slice) in spread.slices.enumerated() {
            let emphasized = selected == nil || slice.segment == selected
            let radius = layout.petalRadius(count: slice.count, maxCount: maxCount)
            let path = layout.wedge(index: index, radius: radius)
            if slice.count == 0 {
                context.fill(path, with: .color(Color.white.opacity(emphasized ? 0.16 : 0.08)))
            } else {
                let singleShare = Double(slice.singles) / Double(slice.count)
                let body = slice.singles > 0
                    ? bedColor(0, emphasized: emphasized).opacity(0.4 + 0.6 * singleShare)
                    : Color.white.opacity(emphasized ? 0.1 : 0.05)
                context.fill(path, with: .color(body))
                if slice.triples > 0 {
                    let thick = layout.bedThickness(slice.triples, of: slice.count, radius: radius)
                    let mid = radius * 0.54
                    context.fill(
                        layout.annulus(index: index, inner: max(0, mid - thick / 2), outer: mid + thick / 2),
                        with: .color(bedColor(1, emphasized: emphasized))
                    )
                }
                if slice.doubles > 0 {
                    let thick = layout.bedThickness(slice.doubles, of: slice.count, radius: radius)
                    context.fill(
                        layout.annulus(index: index, inner: max(0, radius - thick), outer: radius),
                        with: .color(bedColor(0.5, emphasized: emphasized))
                    )
                }
            }
            if slice.segment == selected {
                context.stroke(path, with: .color(.white.opacity(0.9)), lineWidth: 1.5)
            }
        }

        for index in 0..<20 {
            var spoke = Path()
            spoke.move(to: layout.center)
            spoke.addLine(to: layout.point(layout.outer, degreesFromTop: CGFloat(index) * 18 - 9))
            context.stroke(spoke, with: .color(.white.opacity(0.10)), lineWidth: 1)
        }
        for step in 1...rings {
            let radius = layout.outer * CGFloat(step) / CGFloat(rings)
            var circle = Path()
            circle.addEllipse(in: CGRect(x: layout.center.x - radius, y: layout.center.y - radius, width: radius * 2, height: radius * 2))
            context.stroke(circle, with: .color(.white.opacity(0.16)), lineWidth: 1)
        }

        guard !compact else { return }

        for (index, slice) in spread.slices.enumerated() {
            let spot = layout.point(layout.labelRadius, degreesFromTop: CGFloat(index) * 18)
            let isBest = slice.segment == spread.best?.segment && slice.count > 0
            let isSelected = slice.segment == selected
            let color: Color = isSelected ? .white : (isBest ? gold : .white.opacity(0.58))
            let label = context.resolve(
                Text("\(slice.segment)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(color)
            )
            context.draw(label, at: spot, anchor: .center)
        }
    }
}

/// 0° je dvanáctka, úhel roste po směru hodin. V obrazovce y roste dolů.
private struct RoseGeometry {
    var center: CGPoint
    var outer: CGFloat
    var labelRadius: CGFloat

    init(size: CGSize, compact: Bool) {
        let side = min(size.width, size.height)
        center = CGPoint(x: size.width / 2, y: size.height / 2)
        outer = side * (compact ? 0.46 : 0.36)
        labelRadius = outer + side * 0.075
    }

    func point(_ radius: CGFloat, degreesFromTop: CGFloat) -> CGPoint {
        let radians = (Double(degreesFromTop) - 90) * .pi / 180
        return CGPoint(
            x: center.x + radius * CGFloat(cos(radians)),
            y: center.y + radius * CGFloat(sin(radians))
        )
    }

    /// I nejkratší zásah je pořád výseč. Nula zůstane krátká a tlumená, ať segment nezmizí.
    func petalRadius(count: Int, maxCount: Int) -> CGFloat {
        if count <= 0 { return outer * 0.18 }
        let share = CGFloat(count) / CGFloat(max(maxCount, 1))
        return outer * (0.36 + 0.64 * share)
    }

    /// Pár zásahů pořád nakreslí pruh. Čím větší podíl, tím je silnější.
    func bedThickness(_ count: Int, of total: Int, radius: CGFloat) -> CGFloat {
        guard count > 0, total > 0 else { return 0 }
        let share = CGFloat(count) / CGFloat(total)
        return radius * (0.08 + 0.2 * share)
    }

    func annulus(index: Int, inner: CGFloat, outer: CGFloat) -> Path {
        let middle = CGFloat(index) * 18
        let start = middle - 9 + 0.85
        let end = middle + 9 - 0.85
        let steps = 12
        var path = Path()
        func degrees(_ step: Int) -> CGFloat {
            start + (end - start) * CGFloat(step) / CGFloat(steps)
        }
        path.move(to: point(outer, degreesFromTop: start))
        for step in 0...steps {
            path.addLine(to: point(outer, degreesFromTop: degrees(step)))
        }
        for step in stride(from: steps, through: 0, by: -1) {
            path.addLine(to: point(inner, degreesFromTop: degrees(step)))
        }
        path.closeSubpath()
        return path
    }

    func wedge(index: Int, radius: CGFloat) -> Path {
        let middle = CGFloat(index) * 18
        let start = middle - 9 + 0.85
        let end = middle + 9 - 0.85
        var path = Path()
        path.move(to: center)
        let steps = 12
        for step in 0...steps {
            let degrees = start + (end - start) * CGFloat(step) / CGFloat(steps)
            path.addLine(to: point(radius, degreesFromTop: degrees))
        }
        path.closeSubpath()
        return path
    }

    func segmentIndex(at location: CGPoint) -> Int? {
        let dx = location.x - center.x
        let dy = location.y - center.y
        let distance = hypot(dx, dy)
        guard distance > 8, distance < labelRadius + 14 else { return nil }
        var fromTop = atan2(dy, dx) * 180 / .pi + 90
        if fromTop < 0 { fromTop += 360 }
        let shifted = (fromTop + 9).truncatingRemainder(dividingBy: 360)
        return Int(shifted / 18) % 20
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
