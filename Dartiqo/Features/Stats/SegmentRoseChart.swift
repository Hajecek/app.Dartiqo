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

/// Stejný terč jako při hře. Žlutá na poli znamená, jak často tam šipka dopadla.
struct SegmentRoseChart: View {
    var darts: [Dart]
    var title: String
    /// Jen terč, bez popisků. Hodí se do řádku, který vede dál.
    var compact: Bool = false

    @State private var selected: Int?

    private var spread: SegmentSpread { SegmentSpread.make(darts) }
    private let gold = Color(red: 0.91, green: 0.69, blue: 0.24)

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
                legendSwatch(BoardFace.heat.opacity(0.35), "Málo")
                legendSwatch(BoardFace.heat, "Hodně")
            }

            Text(readout)
                .font(.caption)
                .foregroundStyle(selected == nil ? .white.opacity(0.48) : .white.opacity(0.82))
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.snappy, value: selected)
        }
        .padding(16)
        .background(BoardFace.plate, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .environment(\.colorScheme, .dark)
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
        return "Stejný terč jako při hře. Jasnější pole znamená víc zásahů. Klepni na výseč pro počty."
    }

    private var accessibilitySummary: String {
        if let selected, let slice = spread.slices.first(where: { $0.segment == selected }) {
            return "\(title). Segment \(selected), \(slice.count) šipek, \(percent(slice.share)). Single \(slice.singles), double \(slice.doubles), triple \(slice.triples). Bull \(percent(spread.bullShare))."
        }
        guard let best = spread.best, let worst = spread.worst else { return title }
        return "\(title). Stejný terč jako při hře, jasnější pole znamená víc zásahů. Nejvíc segment \(best.segment), \(percent(best.share)). Nejmíň segment \(worst.segment), \(percent(worst.share)). Bull \(percent(spread.bullShare))."
    }

    private var bullBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(spread.bullCount > 0 ? BoardFace.heat.opacity(0.45 + 0.55 * spread.bullDepth) : Color.white.opacity(0.28))
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

    private func legendSwatch(_ color: Color, _ title: String) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(title)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.white.opacity(0.62))
    }

    private func percent(_ share: Double) -> String {
        let value = (share * 100).formatted(.number.precision(.fractionLength(1)))
        return "\(value) %"
    }

    private func draw(in context: GraphicsContext, size: CGSize) {
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(BoardFace.plate))
        let layout = BoardFace.layout(in: size)
        BoardFace.drawScoringBeds(context: context, center: layout.center, radius: layout.radius)
        BoardFace.drawBulls(context: context, center: layout.center, radius: layout.radius)
        drawHeat(in: context, center: layout.center, radius: layout.radius)
        BoardFace.drawWires(context: context, center: layout.center, radius: layout.radius)
        if let selected, let index = BoardGeometry.sectors.firstIndex(of: selected) {
            let bounds = BoardFace.angles(for: index)
            context.stroke(
                BoardFace.ring(inner: BoardGeometry.outerBull, outer: 1, start: bounds.start, end: bounds.end, center: layout.center, radius: layout.radius),
                with: .color(.white.opacity(0.95)),
                lineWidth: 2
            )
        }
        if !compact {
            BoardFace.drawNumbers(context: context, center: layout.center, radius: layout.radius, aimedSegment: selected, aimColor: .white)
        }
    }

    /// Žlutá sedí na skutečném poli. Nejsilnější zásah je nejjasnější, prázdné pole zůstane jako na terči.
    private func drawHeat(in context: GraphicsContext, center: CGPoint, radius: CGFloat) {
        var beds: [(segment: Int, multiplier: Int, count: Int)] = []
        for (index, slice) in spread.slices.enumerated() {
            let segment = BoardGeometry.sectors[index]
            beds.append((segment, 1, slice.singles))
            beds.append((segment, 2, slice.doubles))
            beds.append((segment, 3, slice.triples))
        }
        beds.append((25, 1, spread.bullOuter))
        beds.append((25, 2, spread.bullInner))
        let maxCount = max(beds.map(\.count).max() ?? 0, 1)
        for bed in beds where bed.count > 0 {
            guard let path = BoardFace.bedPath(segment: bed.segment, multiplier: bed.multiplier, center: center, radius: radius) else { continue }
            let emphasized = selected == nil || bed.segment == selected
            let share = Double(bed.count) / Double(maxCount)
            let opacity = (0.22 + 0.58 * share) * (emphasized ? 1 : 0.35)
            context.fill(path, with: .color(BoardFace.heat.opacity(opacity)))
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
