import SwiftUI

/// Úvodní obrazovka po startu. Logo i pozadí odpovídají systémové launch screen
/// (LaunchLogo 100 pt na středu, barva LaunchBackground), aby přechod nebyl vidět.
struct LaunchView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var score = 501

    private static let countdown = [501, 441, 360, 281, 180, 121, 60, 32, 0]

    var body: some View {
        ZStack {
            Color("LaunchBackground").ignoresSafeArea()

            if !reduceMotion {
                Ripples()
                    .opacity(appeared ? 1 : 0)
            }

            Image("LaunchLogo")
                .resizable()
                .frame(width: 100, height: 100)
                .scaleEffect(appeared || reduceMotion ? 1 : 0.92)
                .overlay(alignment: .top) {
                    Text("DARTIQO")
                        .font(AppFont.display(22, weight: .black))
                        .tracking(9)
                        .foregroundStyle(.black)
                        .fixedSize()
                        .offset(y: appeared || reduceMotion ? 116 : 128)
                        .opacity(appeared ? 1 : 0)
                }

            VStack(spacing: 2) {
                Spacer()
                Text("\(score)")
                    .font(AppFont.display(44, weight: .black))
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
                Text("NAČÍTÁM HRU")
                    .font(AppFont.caption(11, weight: .bold))
                    .tracking(3)
                    .opacity(0.55)
            }
            .foregroundStyle(.black)
            .padding(.bottom, 40)
            .opacity(appeared ? 1 : 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Dartiqo se načítá")
        .task {
            withAnimation(.spring(duration: 0.6, bounce: 0.4).delay(0.05)) { appeared = true }
            for value in Self.countdown.dropFirst() {
                try? await Task.sleep(for: .milliseconds(130))
                withAnimation(.snappy(duration: 0.25)) { score = value }
            }
        }
    }
}

/// Soustředné kruhy, které se rozbíhají od loga jako kruhy terče.
private struct Ripples: View {
    private let count = 4
    private let period = 2.4

    var body: some View {
        TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(0..<count, id: \.self) { index in
                    let phase = (time / period + Double(index) / Double(count)).truncatingRemainder(dividingBy: 1)
                    Circle()
                        .stroke(.black, lineWidth: 2)
                        .frame(width: 110 + phase * 520, height: 110 + phase * 520)
                        .opacity((1 - phase) * 0.28)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// Terč jako čárová grafika jednou barvou. Dvojité a trojité pole se střídavě vyplňují.
struct BoardLines: View {
    var color: Color = .black
    var numbers = true

    private static let order = [20, 1, 18, 4, 13, 6, 10, 15, 2, 17, 3, 19, 7, 16, 8, 11, 14, 9, 12, 5]

    var body: some View {
        Canvas { context, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let r = min(size.width, size.height) / 2 * (numbers ? 0.84 : 1)
            let line = max(1, r * 0.008)

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
                    context.fill(wedge(0.93, 1, a, a + 18), with: .color(color))
                    context.fill(wedge(0.56, 0.62, a, a + 18), with: .color(color))
                }
                var spoke = Path()
                let rad = a * .pi / 180
                spoke.move(to: CGPoint(x: c.x + cos(rad) * r * 0.1, y: c.y + sin(rad) * r * 0.1))
                spoke.addLine(to: CGPoint(x: c.x + cos(rad) * r, y: c.y + sin(rad) * r))
                context.stroke(spoke, with: .color(color.opacity(0.6)), lineWidth: line)

                if numbers {
                    let mid = (a + 9) * .pi / 180
                    let point = CGPoint(x: c.x + cos(mid) * r * 1.1, y: c.y + sin(mid) * r * 1.1)
                    context.draw(
                        Text("\(Self.order[i])").font(.system(size: r * 0.09, weight: .heavy, design: .rounded)).foregroundStyle(color),
                        at: point
                    )
                }
            }
            for radius in [1, 0.93, 0.62, 0.56, 0.1] {
                context.stroke(ring(radius), with: .color(color), lineWidth: line * 1.4)
            }
            context.fill(ring(0.04), with: .color(color))
        }
        .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("Launch") {
    LaunchView()
}
#Preview("Terč") {
    BoardLines()
        .frame(width: 320, height: 320)
        .padding()
        .background(Theme.brand)
}
#endif
