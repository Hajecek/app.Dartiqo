import SwiftUI

/// Úvod po startu. První snímek sedí na systémovou launch screen
/// (žluté LaunchLogo 100 pt na černém LaunchBackground). Pak terč
/// dosedne a šipka doletí do značky.
struct LaunchView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var boardOn = false
    @State private var flight: CGFloat = 0
    @State private var hit = false
    @State private var punch = false
    @State private var wave: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let board = min(geo.size.width, geo.size.height) * 0.94
            ZStack {
                Color("LaunchBackground")

                glow
                boardArt(size: board)
                waves
                socket
                mark
                dart(in: geo.size)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Dartiqo se načítá")
        .sensoryFeedback(.impact(flexibility: .solid, intensity: 0.95), trigger: hit)
        .task { await play() }
    }

    private var glow: some View {
        Circle()
            .fill(Theme.brand.opacity(hit ? 0.34 : 0.12))
            .frame(width: 220, height: 220)
            .blur(radius: 56)
            .opacity(boardOn || reduceMotion ? 1 : 0)
            .accessibilityHidden(true)
    }

    private func boardArt(size: CGFloat) -> some View {
        LaunchBoard(color: Theme.brand)
            .frame(width: size, height: size)
            .rotationEffect(.degrees(boardOn ? 0 : -16))
            .scaleEffect(boardOn ? 1 : 0.74)
            .opacity(boardOn ? (hit ? 0.20 : 0.14) : 0)
            .accessibilityHidden(true)
    }

    private var waves: some View {
        ZStack {
            ForEach(0..<2, id: \.self) { i in
                let progress = max(0, min(1, wave - CGFloat(i) * 0.16))
                Circle()
                    .stroke(Theme.brand.opacity((1 - progress) * 0.55), lineWidth: 2.2 - progress)
                    .frame(width: 84 + progress * 360, height: 84 + progress * 360)
            }
        }
        .opacity(hit ? 1 : 0)
        .accessibilityHidden(true)
    }

    private var socket: some View {
        Circle()
            .stroke(Theme.brand.opacity(hit ? 0.40 : 0.16), lineWidth: 1.5)
            .frame(width: 136, height: 136)
            .scaleEffect(boardOn ? 1 : 0.72)
            .opacity(boardOn || reduceMotion ? 1 : 0)
            .accessibilityHidden(true)
    }

    private var mark: some View {
        Image("LaunchLogo")
            .resizable()
            .frame(width: 100, height: 100)
            .scaleEffect(punch ? 1.14 : 1)
            .shadow(color: Theme.brand.opacity(hit ? 0.45 : 0), radius: 18)
    }

    private func dart(in size: CGSize) -> some View {
        let travel = min(size.width, size.height) * 0.78
        return LaunchDart()
            .scaleEffect(0.88 + 0.18 * flight)
            .offset(x: travel * 0.70 * (1 - flight), y: -travel * 0.56 * (1 - flight))
            .opacity(flight > 0.03 && flight < 0.97 ? 1 : 0)
            .accessibilityHidden(true)
    }

    @MainActor
    private func play() async {
        if reduceMotion {
            boardOn = true
            flight = 1
            hit = true
            return
        }
        try? await Task.sleep(for: .milliseconds(70))
        withAnimation(.spring(duration: 0.78, bounce: 0.16)) {
            boardOn = true
        }
        try? await Task.sleep(for: .milliseconds(200))
        withAnimation(.easeIn(duration: 0.46)) {
            flight = 1
        }
        try? await Task.sleep(for: .milliseconds(460))
        withAnimation(.spring(duration: 0.32, bounce: 0.46)) {
            hit = true
            punch = true
        }
        withAnimation(.easeOut(duration: 0.72)) {
            wave = 1
        }
        try? await Task.sleep(for: .milliseconds(160))
        withAnimation(.spring(duration: 0.42, bounce: 0.18)) {
            punch = false
        }
    }
}

/// Terč jako tenká drátěná kresba. Dvojité a trojité pole se střídavě vyplňují.
struct LaunchBoard: View {
    var color: Color = Theme.brand

    var body: some View {
        Canvas { context, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let r = min(size.width, size.height) / 2
            let line = max(1, r * 0.007)

            func ring(_ radius: Double) -> Path {
                Path(ellipseIn: CGRect(x: c.x - r * radius, y: c.y - r * radius, width: r * radius * 2, height: r * radius * 2))
            }
            func wedge(_ inner: Double, _ outer: Double, _ a: Double, _ b: Double) -> Path {
                var p = Path()
                p.addArc(center: c, radius: r * outer, startAngle: .degrees(a), endAngle: .degrees(b), clockwise: false)
                p.addArc(center: c, radius: r * inner, startAngle: .degrees(b), endAngle: .degrees(a), clockwise: true)
                p.closeSubpath()
                return p
            }

            for i in 0..<20 {
                let a = Double(i) * 18 - 99
                if i.isMultiple(of: 2) {
                    context.fill(wedge(0.93, 1, a, a + 18), with: .color(color.opacity(0.55)))
                    context.fill(wedge(0.56, 0.62, a, a + 18), with: .color(color.opacity(0.55)))
                }
                var spoke = Path()
                let rad = a * .pi / 180
                spoke.move(to: CGPoint(x: c.x + cos(rad) * r * 0.16, y: c.y + sin(rad) * r * 0.16))
                spoke.addLine(to: CGPoint(x: c.x + cos(rad) * r, y: c.y + sin(rad) * r))
                context.stroke(spoke, with: .color(color.opacity(0.45)), lineWidth: line)
            }
            for radius in [1.0, 0.93, 0.62, 0.56, 0.16] {
                context.stroke(ring(radius), with: .color(color.opacity(radius == 1 ? 0.85 : 0.6)), lineWidth: line * 1.3)
            }
            context.stroke(ring(0.07), with: .color(color), lineWidth: line * 1.1)
        }
    }
}

/// Šipka ve stejném sklonu jako kresba ve značce.
private struct LaunchDart: View {
    var body: some View {
        Canvas { context, size in
            let mid = size.height / 2
            let paint = GraphicsContext.Shading.color(Theme.brand)

            var flights = Path()
            flights.move(to: CGPoint(x: size.width * 0.22, y: mid))
            flights.addLine(to: CGPoint(x: size.width * 0.02, y: mid - size.height * 0.46))
            flights.addLine(to: CGPoint(x: size.width * 0.30, y: mid))
            flights.addLine(to: CGPoint(x: size.width * 0.02, y: mid + size.height * 0.46))
            flights.closeSubpath()
            context.fill(flights, with: paint)

            var shaft = Path()
            shaft.addRoundedRect(
                in: CGRect(x: size.width * 0.20, y: mid - 1.1, width: size.width * 0.50, height: 2.2),
                cornerSize: CGSize(width: 1, height: 1)
            )
            context.fill(shaft, with: paint)

            var barrel = Path()
            barrel.addRoundedRect(
                in: CGRect(x: size.width * 0.66, y: mid - 2.6, width: size.width * 0.16, height: 5.2),
                cornerSize: CGSize(width: 2, height: 2)
            )
            context.fill(barrel, with: paint)

            var point = Path()
            point.move(to: CGPoint(x: size.width * 0.98, y: mid))
            point.addLine(to: CGPoint(x: size.width * 0.82, y: mid - 2.4))
            point.addLine(to: CGPoint(x: size.width * 0.82, y: mid + 2.4))
            point.closeSubpath()
            context.fill(point, with: paint)
        }
        .frame(width: 78, height: 30)
        .rotationEffect(.degrees(138))
        .shadow(color: Theme.brand.opacity(0.55), radius: 10)
    }
}

#if DEBUG
#Preview("Launch") {
    LaunchView()
}
#Preview("Terč") {
    LaunchBoard()
        .frame(width: 320, height: 320)
        .padding()
        .background(.black)
}
#endif
