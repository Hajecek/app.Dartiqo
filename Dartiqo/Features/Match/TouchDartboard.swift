import SwiftUI

struct TouchDartboard: View {
    var marks: [Dart] = []
    var interactive = true
    var showMarkNumbers = true
    var onHit: (Dart) -> Void

    @State private var touch: CGPoint?
    @State private var hover: Dart?
    @State private var magnifying = false
    @State private var pressTask: Task<Void, Never>?

    private let zoomScale: CGFloat = 2.35
    private let highlight = Color(red: 1, green: 0.92, blue: 0.15)

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let radius = min(size.width, size.height) * 0.43
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
            .accessibilityLabel("Dotykový terč")
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
            func ring(_ inner: Double, _ outer: Double, _ start: Double, _ end: Double) -> Path {
                var p = Path()
                p.addArc(center: center, radius: radius * outer, startAngle: .degrees(start), endAngle: .degrees(end), clockwise: false)
                p.addArc(center: center, radius: radius * inner, startAngle: .degrees(end), endAngle: .degrees(start), clockwise: true)
                p.closeSubpath()
                return p
            }
            context.fill(Path(ellipseIn: CGRect(x: center.x - radius * 1.16, y: center.y - radius * 1.16, width: radius * 2.32, height: radius * 2.32)), with: .color(Color(white: 0.14)))
            for i in 0..<20 {
                let start = Double(i) * 18 - 99
                let end = start + 18
                let band = i.isMultiple(of: 2) ? Color(red: 0.78, green: 0.12, blue: 0.15) : Color(red: 0.04, green: 0.59, blue: 0.35)
                let base = i.isMultiple(of: 2) ? Color(white: 0.065) : Color(red: 0.92, green: 0.84, blue: 0.65)
                context.fill(ring(BoardGeometry.outerBull, 1, start, end), with: .color(base))
                context.fill(ring(BoardGeometry.doubleInner, 1, start, end), with: .color(band))
                context.fill(ring(BoardGeometry.tripleInner, BoardGeometry.tripleOuter, start, end), with: .color(band))
                context.stroke(ring(BoardGeometry.outerBull, 1, start, end), with: .color(.gray.opacity(0.7)), lineWidth: 0.5)
                let angle = (-90 + Double(i) * 18) * Double.pi / 180
                let point = CGPoint(x: center.x + radius * 1.09 * cos(angle), y: center.y + radius * 1.09 * sin(angle))
                context.draw(Text("\(BoardGeometry.sectors[i])").font(.system(size: max(11, radius * 0.075), weight: .bold, design: .rounded)).foregroundColor(.white), at: point)
            }
            for (r, color) in [(BoardGeometry.outerBull, Color(red: 0.04, green: 0.59, blue: 0.35)), (BoardGeometry.innerBull, Color(red: 0.78, green: 0.12, blue: 0.15))] {
                context.fill(Path(ellipseIn: CGRect(x: center.x - radius * r, y: center.y - radius * r, width: radius * r * 2, height: radius * r * 2)), with: .color(color))
            }
            if let hover, let path = highlightPath(for: hover, center: center, radius: radius, ring: ring) {
                context.fill(path, with: .color(highlight.opacity(0.28)))
                context.stroke(path, with: .color(highlight), lineWidth: 2.5)
            }
            for (i, dart) in marks.enumerated() {
                if let point = BoardGeometry.marker(for: dart) {
                    let p = CGPoint(x: center.x + point.x * radius, y: center.y + point.y * radius)
                    // Exact pin: small core + white ring + dart index
                    let core = CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8)
                    let ringRect = CGRect(x: p.x - 7, y: p.y - 7, width: 14, height: 14)
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

    private func highlightPath(
        for dart: Dart,
        center: CGPoint,
        radius: CGFloat,
        ring: (_ inner: Double, _ outer: Double, _ start: Double, _ end: Double) -> Path
    ) -> Path? {
        if dart.segment == 0 { return nil }
        if dart.segment == 25 {
            let r = dart.multiplier == 2 ? BoardGeometry.innerBull : BoardGeometry.outerBull
            let inner = dart.multiplier == 2 ? 0 : BoardGeometry.innerBull
            return Path(ellipseIn: CGRect(x: center.x - radius * r, y: center.y - radius * r, width: radius * r * 2, height: radius * r * 2))
                .subtracting(Path(ellipseIn: CGRect(x: center.x - radius * inner, y: center.y - radius * inner, width: radius * inner * 2, height: radius * inner * 2)))
        }
        guard let index = BoardGeometry.sectors.firstIndex(of: dart.segment) else { return nil }
        let start = Double(index) * 18 - 99
        let end = start + 18
        let bounds: (Double, Double) = dart.multiplier == 2
            ? (BoardGeometry.doubleInner, 1)
            : dart.multiplier == 3
            ? (BoardGeometry.tripleInner, BoardGeometry.tripleOuter)
            : (BoardGeometry.outerBull, BoardGeometry.doubleInner)
        if dart.multiplier == 1 {
            var path = ring(BoardGeometry.outerBull, BoardGeometry.doubleInner, start, end)
            path = path.subtracting(ring(BoardGeometry.tripleInner, BoardGeometry.tripleOuter, start, end))
            return path
        }
        return ring(bounds.0, bounds.1, start, end)
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
