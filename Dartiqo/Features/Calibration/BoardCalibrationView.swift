import SwiftUI
import UIKit

/// Simple Autodarts / GRAN-style steps: frame → circle on outer double → rotate onto 20 → check & save.
private enum Step: Int, CaseIterable {
    case frame, fit, rotate, check

    var title: String {
        switch self {
        case .frame: return "Namiř kameru"
        case .fit: return "Obvod terče"
        case .rotate: return "Otoč na 20"
        case .check: return "Kontrola"
        }
    }

    var instruction: String {
        switch self {
        case .frame: return "Celý terč musí být ve snímku. Číslo 20 nahoře. Telefon drž pevně."
        case .fit: return "Posuň střed do bull. Táhni okraj kruhu na vnější drát doublu."
        case .rotate: return "Otáčej, dokud žluté pole 20 nesedí na skutečnou 20 na terči."
        case .check: return "Klepni na místa na terči. Musí se zobrazit správné pole (např. D20)."
        }
    }
}

struct BoardCalibrationView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var camera = CameraSession()
    @State private var draft: BoardCalibration
    @State private var step: Step = .frame
    @State private var probe: NormPoint?
    @State private var probeLabel: String?
    @State private var savedToast = false
    @State private var dragMode: DragMode = .none

    private enum DragMode { case none, center, radius }

    init(initial: BoardCalibration? = nil) {
        _draft = State(initialValue: (initial ?? .draft).sanitized())
    }

    private var mapper: BoardMapper { BoardMapper(calibration: draft) }

    var body: some View {
        ZStack {
            Theme.ink.ignoresSafeArea()
            cameraLayer
            GeometryReader { geo in
                let size = geo.size
                ZStack {
                    dimOutsideBoard(in: size)
                    boardDrawing(in: size)
                    if step == .fit {
                        fitHandles(in: size)
                    }
                    if let probe, step == .check {
                        probeMark(at: probe, in: size)
                    }
                }
                .contentShape(Rectangle())
                .gesture(stepGesture(in: size))
                .onAppear { draft.previewAspect = Double(size.width / max(size.height, 1)) }
                .onChange(of: size) { _, s in draft.previewAspect = Double(s.width / max(s.height, 1)) }
            }
            .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                Spacer()
                bottomBar
            }
        }
        .preferredColorScheme(.dark)
        .toolbar(.hidden, for: .navigationBar)
        .task { await camera.prepare() }
        .onDisappear { camera.stop() }
        .alert("Kalibrace uložena", isPresented: $savedToast) {
            Button("Hotovo") { dismiss() }
        } message: {
            Text("Telefon už nepřemisťuj — autoscore používá tuhle mapu terče.")
        }
    }

    // MARK: Camera

    private var cameraLayer: some View {
        Group {
            switch camera.status {
            case .ready:
                CameraPreview(session: camera.session).ignoresSafeArea()
            case .requesting, .idle:
                ProgressView("Kamera…").tint(.white).frame(maxWidth: .infinity, maxHeight: .infinity)
            case .denied:
                fallback("Povol kameru v Nastavení", action: true)
            case .unavailable:
                fallback("Kamera není dostupná", action: false)
            }
        }
    }

    private func fallback(_ text: String, action: Bool) -> some View {
        ZStack {
            Theme.ink
            VStack(spacing: 16) {
                Image(systemName: "camera.fill").font(.system(size: 40)).foregroundStyle(Theme.accent)
                Text(text).font(AppFont.title(20)).foregroundStyle(.white).multilineTextAlignment(.center).padding(.horizontal)
                if action {
                    Button("Nastavení") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }.buttonStyle(PrimaryButton()).padding(.horizontal, 40)
                }
            }
        }.ignoresSafeArea()
    }

    // MARK: Drawing

    private func boardRect(in size: CGSize) -> CGRect {
        let c = screen(draft.center, in: size)
        let rx = draft.radius * size.width
        let ry = draft.radius * draft.previewAspect * size.height
        // Visual circle: use equal pixel radius from width-based radius
        let r = rx
        return CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
    }

    private func dimOutsideBoard(in size: CGSize) -> some View {
        let rect = boardRect(in: size)
        return Canvas { context, _ in
            var path = Path(CGRect(origin: .zero, size: size))
            path.addEllipse(in: rect)
            context.fill(path, with: .color(.black.opacity(0.45)), style: FillStyle(eoFill: true))
        }
        .allowsHitTesting(false)
        .opacity(step == .frame ? 0.85 : 0.55)
    }

    private func boardDrawing(in size: CGSize) -> some View {
        Canvas { context, _ in
            let rect = boardRect(in: size)
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let r = rect.width / 2

            // Outer double — what the user aligns
            context.stroke(Path(ellipseIn: rect), with: .color(.white), lineWidth: 3)

            if step != .frame {
                // Standard rings (fixed WDF proportions)
                for (ratio, color, width) in [
                    (BoardRings.doubleInner, Theme.accent.opacity(0.85), 1.5),
                    (BoardRings.tripleOuter, Color.white.opacity(0.45), 1.2),
                    (BoardRings.tripleInner, Color.white.opacity(0.45), 1.2),
                    (BoardRings.outerBull, Color.green.opacity(0.9), 1.5),
                    (BoardRings.innerBull, Color.red.opacity(0.95), 1.5)
                ] as [(Double, Color, Double)] {
                    let rr = r * ratio
                    context.stroke(
                        Path(ellipseIn: CGRect(x: center.x - rr, y: center.y - rr, width: rr * 2, height: rr * 2)),
                        with: .color(color),
                        lineWidth: width
                    )
                }

                // Spider wires
                for index in 0..<20 {
                    let hit = Double(index) * (.pi / 10) - .pi / 2 - .pi / 20 + draft.rotationDegrees * .pi / 180
                    let inner = BoardRings.outerBull * r
                    var wire = Path()
                    wire.move(to: CGPoint(x: center.x + cos(hit) * inner, y: center.y + sin(hit) * inner))
                    wire.addLine(to: CGPoint(x: center.x + cos(hit) * r, y: center.y + sin(hit) * r))
                    context.stroke(wire, with: .color(.white.opacity(0.55)), lineWidth: 1)
                }

                // Numbers
                for index in 0..<20 {
                    let mid = (Double(index) + 0.5) * (.pi / 10) - .pi / 2 - .pi / 20 + draft.rotationDegrees * .pi / 180
                    let p = CGPoint(x: center.x + cos(mid) * r * 1.12, y: center.y + sin(mid) * r * 1.12)
                    context.draw(
                        Text("\(BoardGeometry.sectors[index])")
                            .font(.system(size: max(10, r * 0.08), weight: .bold, design: .rounded))
                            .foregroundColor(.white),
                        at: p
                    )
                }
            }

            // Highlight sector 20 while rotating (Autodarts-style)
            if step == .rotate || step == .check {
                let start = -0.5 * (.pi / 10) - .pi / 2 - .pi / 20 + draft.rotationDegrees * .pi / 180
                let end = start + (.pi / 10)
                var wedge = Path()
                wedge.move(to: center)
                wedge.addArc(center: center, radius: r, startAngle: .radians(start), endAngle: .radians(end), clockwise: false)
                wedge.closeSubpath()
                context.fill(wedge, with: .color(Color.red.opacity(step == .rotate ? 0.35 : 0.18)))
                context.stroke(wedge, with: .color(.red.opacity(0.9)), lineWidth: 2)
            }

            // Center crosshair
            if step == .fit || step == .frame {
                var cross = Path()
                cross.move(to: CGPoint(x: center.x - 16, y: center.y))
                cross.addLine(to: CGPoint(x: center.x + 16, y: center.y))
                cross.move(to: CGPoint(x: center.x, y: center.y - 16))
                cross.addLine(to: CGPoint(x: center.x, y: center.y + 16))
                context.stroke(cross, with: .color(Theme.accent), lineWidth: 2)
                context.stroke(Path(ellipseIn: CGRect(x: center.x - 10, y: center.y - 10, width: 20, height: 20)), with: .color(Theme.accent), lineWidth: 2)
            }

            // Probe highlight
            if step == .check, let probe {
                let dart = mapper.dart(at: probe)
                if let outline = mapper.bandOutline(segment: dart.segment, multiplier: dart.multiplier), let first = outline.first {
                    var path = Path()
                    path.move(to: screen(first, in: size))
                    for p in outline.dropFirst() { path.addLine(to: screen(p, in: size)) }
                    path.closeSubpath()
                    context.fill(path, with: .color(Theme.accent.opacity(0.28)))
                    context.stroke(path, with: .color(Theme.accent), lineWidth: 2)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func fitHandles(in size: CGSize) -> some View {
        let c = screen(draft.center, in: size)
        let edge = CGPoint(x: c.x + draft.radius * size.width, y: c.y)
        return ZStack {
            Circle().fill(Theme.accent).frame(width: 28, height: 28)
                .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                .position(c)
            Circle().fill(.white).frame(width: 26, height: 26)
                .overlay(Text("↔").font(.system(size: 11, weight: .bold)))
                .position(edge)
        }
        .allowsHitTesting(false)
    }

    private func probeMark(at point: NormPoint, in size: CGSize) -> some View {
        ZStack {
            Circle().strokeBorder(Theme.accent, lineWidth: 2).frame(width: 28, height: 28)
            Circle().fill(Theme.accent).frame(width: 7, height: 7)
            if let probeLabel {
                Text(probeLabel)
                    .font(AppFont.caption(13, weight: .bold))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.black.opacity(0.7), in: Capsule())
                    .foregroundStyle(.white)
                    .offset(y: -26)
            }
        }
        .position(screen(point, in: size))
        .allowsHitTesting(false)
    }

    // MARK: Gestures

    private func stepGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if step == .fit { handleFitDrag(value, in: size, ended: false) }
            }
            .onEnded { value in
                switch step {
                case .fit:
                    handleFitDrag(value, in: size, ended: true)
                    dragMode = .none
                case .check:
                    let p = clamp(NormPoint(x: value.location.x / size.width, y: value.location.y / size.height))
                    probe = p
                    probeLabel = mapper.dart(at: p).label
                    store.feedback()
                default:
                    break
                }
            }
    }

    private func handleFitDrag(_ value: DragGesture.Value, in size: CGSize, ended: Bool) {
        let c = screen(draft.center, in: size)
        let edge = CGPoint(x: c.x + draft.radius * size.width, y: c.y)
        if dragMode == .none {
            let toCenter = hypot(value.startLocation.x - c.x, value.startLocation.y - c.y)
            let toEdge = hypot(value.startLocation.x - edge.x, value.startLocation.y - edge.y)
            dragMode = toEdge < toCenter && toEdge < 44 ? .radius : .center
        }
        switch dragMode {
        case .center:
            draft.center = clamp(NormPoint(x: value.location.x / size.width, y: value.location.y / size.height))
        case .radius:
            let dx = value.location.x - c.x
            let dy = value.location.y - c.y
            // Keep circular in pixels → radius as fraction of width
            draft.radius = max(0.08, min(0.7, hypot(dx, dy) / max(size.width, 1)))
        case .none:
            break
        }
        if ended { dragMode = .none }
        // Keep anchors visually round: radiusY tied via previewAspect in model
        draft = draft.sanitized()
    }

    // MARK: Chrome

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark").padding(12).background(.black.opacity(0.45), in: Circle())
            }
            Spacer()
            Text("\(step.rawValue + 1)/\(Step.allCases.count)")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(.black.opacity(0.45), in: Capsule())
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }

    private var bottomBar: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                ForEach(Step.allCases, id: \.rawValue) { s in
                    Capsule().fill(s.rawValue <= step.rawValue ? Theme.accent : .white.opacity(0.2)).frame(height: 4)
                }
            }
            Text(step.title).font(AppFont.title(22)).foregroundStyle(.white)
            Text(step.instruction)
                .font(AppFont.body(15))
                .foregroundStyle(.white.opacity(0.78))
                .fixedSize(horizontal: false, vertical: true)

            if step == .rotate {
                HStack(spacing: 12) {
                    Button { draft.rotationDegrees -= 1 } label: { Image(systemName: "rotate.left").frame(width: 52, height: 44) }
                    Text(String(format: "%.0f°", draft.rotationDegrees))
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .frame(maxWidth: .infinity)
                    Button { draft.rotationDegrees += 1 } label: { Image(systemName: "rotate.right").frame(width: 52, height: 44) }
                }
                .foregroundStyle(.white)
                .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
            }

            if step == .check, let probeLabel {
                HStack {
                    Text("Zásah:")
                    Text(probeLabel).font(AppFont.title(28)).monospacedDigit()
                    Spacer()
                }
                .foregroundStyle(.white)
            }

            HStack(spacing: 10) {
                if step != .frame {
                    Button("Zpět") { step = Step(rawValue: step.rawValue - 1) ?? .frame; probe = nil }
                        .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 15)
                        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 18))
                        .foregroundStyle(.white)
                }
                if step == .check {
                    Button("Uložit") { save() }
                        .buttonStyle(PrimaryButton())
                        .disabled(!mapper.isReady)
                        .opacity(mapper.isReady ? 1 : 0.45)
                } else {
                    Button(step == .frame ? "Terč mám v obraze" : "Další") {
                        step = Step(rawValue: step.rawValue + 1) ?? .check
                        probe = nil
                        probeLabel = nil
                    }
                    .buttonStyle(PrimaryButton())
                }
            }
        }
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    private func save() {
        var ready = draft.sanitized()
        // Sync radiusY via aspect so anchors stay a visual circle
        ready.calibratedAt = Date()
        store.saveBoardCalibration(ready)
        store.feedback()
        savedToast = true
    }

    private func screen(_ point: NormPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: point.x * size.width, y: point.y * size.height)
    }

    private func clamp(_ point: NormPoint) -> NormPoint {
        NormPoint(x: min(max(point.x, 0.05), 0.95), y: min(max(point.y, 0.08), 0.85))
    }
}
