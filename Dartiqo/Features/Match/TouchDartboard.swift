import SwiftUI

/// Vzhled terče. Mapa dopadů i herní terč kreslí stejná pole a stejné plátno.
enum BoardFace {
    static let plate = Color.black
    static let surround = Color(white: 0.14)
    static let blackBed = Color(white: 0.065)
    static let creamBed = Color(red: 0.92, green: 0.84, blue: 0.65)
    static let redBed = Color(red: 0.78, green: 0.12, blue: 0.15)
    static let greenBed = Color(red: 0.04, green: 0.59, blue: 0.35)
    static let wire = Color.gray.opacity(0.7)
    static let heat = Color(red: 1, green: 0.92, blue: 0.15)
    /// Skórovací poloměr vůči kratší straně. Číselník zůstává uvnitř kruhu.
    static let radiusFactor: CGFloat = 0.43

    static func layout(in size: CGSize) -> (center: CGPoint, radius: CGFloat) {
        let side = min(size.width, size.height)
        return (CGPoint(x: size.width / 2, y: size.height / 2), side * radiusFactor)
    }

    static func ring(inner: Double, outer: Double, start: Double, end: Double, center: CGPoint, radius: CGFloat) -> Path {
        var path = Path()
        path.addArc(center: center, radius: radius * outer, startAngle: .degrees(start), endAngle: .degrees(end), clockwise: false)
        path.addArc(center: center, radius: radius * inner, startAngle: .degrees(end), endAngle: .degrees(start), clockwise: true)
        path.closeSubpath()
        return path
    }

    static func angles(for index: Int) -> (start: Double, end: Double) {
        let start = Double(index) * 18 - 99
        return (start, start + 18)
    }

    static func disk(factor: Double, center: CGPoint, radius: CGFloat) -> Path {
        let span = radius * factor
        return Path(ellipseIn: CGRect(x: center.x - span, y: center.y - span, width: span * 2, height: span * 2))
    }

    static func bedPath(segment: Int, multiplier: Int, center: CGPoint, radius: CGFloat) -> Path? {
        if segment == 0 { return nil }
        if segment == 25 {
            let outer = multiplier == 2 ? BoardGeometry.innerBull : BoardGeometry.outerBull
            let inner = multiplier == 2 ? 0 : BoardGeometry.innerBull
            return disk(factor: outer, center: center, radius: radius)
                .subtracting(disk(factor: inner, center: center, radius: radius))
        }
        guard let index = BoardGeometry.sectors.firstIndex(of: segment) else { return nil }
        let bounds = angles(for: index)
        if multiplier == 2 {
            return ring(inner: BoardGeometry.doubleInner, outer: 1, start: bounds.start, end: bounds.end, center: center, radius: radius)
        }
        if multiplier == 3 {
            return ring(inner: BoardGeometry.tripleInner, outer: BoardGeometry.tripleOuter, start: bounds.start, end: bounds.end, center: center, radius: radius)
        }
        return ring(inner: BoardGeometry.outerBull, outer: BoardGeometry.doubleInner, start: bounds.start, end: bounds.end, center: center, radius: radius)
            .subtracting(ring(inner: BoardGeometry.tripleInner, outer: BoardGeometry.tripleOuter, start: bounds.start, end: bounds.end, center: center, radius: radius))
    }

    static func drawScoringBeds(context: GraphicsContext, center: CGPoint, radius: CGFloat) {
        context.fill(disk(factor: 1.16, center: center, radius: radius), with: .color(surround))
        for index in 0..<20 {
            let bounds = angles(for: index)
            let band = index.isMultiple(of: 2) ? redBed : greenBed
            let base = index.isMultiple(of: 2) ? blackBed : creamBed
            context.fill(ring(inner: BoardGeometry.outerBull, outer: 1, start: bounds.start, end: bounds.end, center: center, radius: radius), with: .color(base))
            context.fill(ring(inner: BoardGeometry.doubleInner, outer: 1, start: bounds.start, end: bounds.end, center: center, radius: radius), with: .color(band))
            context.fill(ring(inner: BoardGeometry.tripleInner, outer: BoardGeometry.tripleOuter, start: bounds.start, end: bounds.end, center: center, radius: radius), with: .color(band))
        }
    }

    static func drawBulls(context: GraphicsContext, center: CGPoint, radius: CGFloat) {
        context.fill(disk(factor: BoardGeometry.outerBull, center: center, radius: radius), with: .color(greenBed))
        context.fill(disk(factor: BoardGeometry.innerBull, center: center, radius: radius), with: .color(redBed))
    }

    static func drawWires(context: GraphicsContext, center: CGPoint, radius: CGFloat) {
        for index in 0..<20 {
            let bounds = angles(for: index)
            context.stroke(
                ring(inner: BoardGeometry.outerBull, outer: 1, start: bounds.start, end: bounds.end, center: center, radius: radius),
                with: .color(wire),
                lineWidth: 0.5
            )
        }
    }

    static func drawNumbers(context: GraphicsContext, center: CGPoint, radius: CGFloat, aimedSegment: Int? = nil, aimColor: Color = heat) {
        for index in 0..<20 {
            let angle = (-90 + Double(index) * 18) * Double.pi / 180
            let point = CGPoint(x: center.x + radius * 1.09 * cos(angle), y: center.y + radius * 1.09 * sin(angle))
            let segment = BoardGeometry.sectors[index]
            let aimed = segment == aimedSegment
            context.draw(
                Text("\(segment)")
                    .font(.system(size: max(11, radius * 0.075), weight: aimed ? .heavy : .bold, design: .rounded))
                    .foregroundColor(aimed ? aimColor : .white),
                at: point
            )
        }
    }
}

struct TouchDartboard: View {
    var marks: [Dart] = []
    var interactive = true
    var showMarkNumbers = true
    /// 1 = celý terč. Vyšší hodnota přiblíží střed, gesta používají stejný poloměr.
    var zoom: CGFloat = 1
    /// AI nápověda. Zvýrazní jen dané pole — double, triple, single nebo bull.
    var suggestion: Dart? = nil
    /// Rozsvítí pole každého zapsaného zásahu. Poslední šipka je výraznější.
    var markBeds = false
    var onHit: (Dart) -> Void

    @State private var touch: CGPoint?
    @State private var hover: Dart?
    @State private var magnifying = false
    @State private var pressTask: Task<Void, Never>?

    private let zoomScale: CGFloat = 2.35
    private let highlight = BoardFace.heat

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let radius = min(size.width, size.height) * BoardFace.radiusFactor * max(zoom, 1)
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            ZStack {
                boardCanvas(size: size, center: center, radius: radius, hover: hover)
                    .scaleEffect(magnifying ? zoomScale : 1, anchor: zoomAnchor(in: size))
                    .animation(.easeOut(duration: 0.12), value: magnifying)
                    .animation(.easeOut(duration: 0.08), value: touch)

                if magnifying, let touch {
                    aimingReticle(at: touch, label: hover?.label)
                        .allowsHitTesting(false)
                }
            }
            .clipped()
            .contentShape(Rectangle())
            .modifier(BoardInteractionModifier(enabled: interactive, gesture: boardGesture(size: size, center: center, radius: radius)))
            .accessibilityElement()
            .accessibilityLabel(suggestion.map { "Dotykový terč, doporučení \($0.label)" } ?? "Dotykový terč")
            .accessibilityHint(interactive ? "Podrž a posouvej prst pro výběr přesného místa. Pusť pro zápis." : "")
            .accessibilityAddTraits(interactive ? .isButton : [])
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func aimingReticle(at touch: CGPoint, label: String?) -> some View {
        ZStack {
            // Outer guide
            Circle()
                .strokeBorder(.white.opacity(0.9), lineWidth: 1.5)
                .frame(width: 44, height: 44)
            // Crosshair
            Path { path in
                path.move(to: CGPoint(x: 22, y: 4))
                path.addLine(to: CGPoint(x: 22, y: 16))
                path.move(to: CGPoint(x: 22, y: 28))
                path.addLine(to: CGPoint(x: 22, y: 40))
                path.move(to: CGPoint(x: 4, y: 22))
                path.addLine(to: CGPoint(x: 16, y: 22))
                path.move(to: CGPoint(x: 28, y: 22))
                path.addLine(to: CGPoint(x: 40, y: 22))
            }
            .stroke(.white.opacity(0.85), lineWidth: 1.2)
            .frame(width: 44, height: 44)
            // Exact placement dot — the recorded hit point
            Circle()
                .fill(highlight)
                .frame(width: 7, height: 7)
                .overlay(Circle().strokeBorder(.black.opacity(0.55), lineWidth: 1))
            if let label {
                Text(label)
                    .font(AppFont.body(13, weight: .bold))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.6), in: Capsule())
                    .foregroundStyle(.white)
                    .offset(y: -36)
            }
        }
        .position(touch)
    }

    private func zoomAnchor(in size: CGSize) -> UnitPoint {
        guard magnifying, let touch, size.width > 0, size.height > 0 else { return .center }
        return UnitPoint(x: touch.x / size.width, y: touch.y / size.height)
    }

    private func boardGesture(size: CGSize, center: CGPoint, radius: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                touch = value.location
                hover = dart(at: value.location, center: center, radius: radius)
                if pressTask == nil {
                    pressTask = Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 120_000_000)
                        guard !Task.isCancelled, touch != nil else { return }
                        magnifying = true
                    }
                }
            }
            .onEnded { value in
                pressTask?.cancel()
                pressTask = nil
                let dart = dart(at: value.location, center: center, radius: radius)
                withAnimation(.easeOut(duration: 0.12)) {
                    magnifying = false
                    touch = nil
                    hover = nil
                }
                onHit(dart)
            }
    }

    private func dart(at point: CGPoint, center: CGPoint, radius: CGFloat) -> Dart {
        guard radius > 0 else { return .miss }
        let x = Double((point.x - center.x) / radius)
        let y = Double((point.y - center.y) / radius)
        return BoardGeometry.hit(x: x, y: y)
    }

    private func boardCanvas(size: CGSize, center: CGPoint, radius: CGFloat, hover: Dart?) -> some View {
        Canvas { context, _ in
            BoardFace.drawScoringBeds(context: context, center: center, radius: radius)
            BoardFace.drawWires(context: context, center: center, radius: radius)
            BoardFace.drawNumbers(context: context, center: center, radius: radius, aimedSegment: suggestion?.segment, aimColor: highlight)
            BoardFace.drawBulls(context: context, center: center, radius: radius)
            if let suggestion, let path = highlightPath(for: suggestion, center: center, radius: radius) {
                context.stroke(path, with: .color(.black.opacity(0.55)), lineWidth: 5)
                context.fill(path, with: .color(highlight.opacity(0.78)))
                context.stroke(path, with: .color(highlight), lineWidth: 2.5)
            }
            if markBeds {
                for (index, dart) in marks.enumerated() where dart != suggestion {
                    guard let path = highlightPath(for: dart, center: center, radius: radius) else { continue }
                    let latest = index == marks.count - 1
                    context.fill(path, with: .color(highlight.opacity(latest ? 0.72 : 0.34)))
                    context.stroke(path, with: .color(highlight.opacity(latest ? 1 : 0.7)), lineWidth: latest ? 2.5 : 1.5)
                }
            }
            if let hover, hover != suggestion, let path = highlightPath(for: hover, center: center, radius: radius) {
                context.fill(path, with: .color(highlight.opacity(0.28)))
                context.stroke(path, with: .color(highlight), lineWidth: 2.5)
            }
            for (i, dart) in marks.enumerated() {
                if let point = BoardGeometry.marker(for: dart) {
                    let p = CGPoint(x: center.x + point.x * radius, y: center.y + point.y * radius)
                    let latest = markBeds && i == marks.count - 1
                    let coreRadius: CGFloat = latest ? 6 : 4
                    let ringRadius: CGFloat = latest ? 10 : 7
                    let core = CGRect(x: p.x - coreRadius, y: p.y - coreRadius, width: coreRadius * 2, height: coreRadius * 2)
                    let ringRect = CGRect(x: p.x - ringRadius, y: p.y - ringRadius, width: ringRadius * 2, height: ringRadius * 2)
                    context.stroke(Path(ellipseIn: ringRect), with: .color(.white.opacity(0.95)), lineWidth: 2)
                    context.fill(Path(ellipseIn: core), with: .color(highlight))
                    context.stroke(Path(ellipseIn: core), with: .color(.black.opacity(0.55)), lineWidth: 1)
                    if showMarkNumbers {
                        context.draw(
                            Text("\(i + 1)").font(.system(size: 9, weight: .bold, design: .rounded)).foregroundColor(.white),
                            at: CGPoint(x: p.x, y: p.y - 14)
                        )
                    }
                }
            }
        }
    }

    private func highlightPath(for dart: Dart, center: CGPoint, radius: CGFloat) -> Path? {
        BoardFace.bedPath(segment: dart.segment, multiplier: dart.multiplier, center: center, radius: radius)
    }
}

private struct BoardInteractionModifier<G: Gesture>: ViewModifier {
    var enabled: Bool
    var gesture: G
    func body(content: Content) -> some View {
        if enabled {
            content.highPriorityGesture(gesture)
        } else {
            content
        }
    }
}

#if DEBUG
#Preview {
    TouchDartboard(onHit: { _ in })
        .frame(height: 420)
        .background(Color.black)
        .preferredColorScheme(.dark)
}
#endif
