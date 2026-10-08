import SwiftUI

struct BoardFitCanvas: View {
    var calibration: BoardCalibration
    var edgeRadius: Double
    var readiness: BoardReadiness
    var marks: [(point: NormPoint, label: String)] = []

    private let locked = Color(red: 0.28, green: 0.93, blue: 0.52)

    var body: some View {
        Canvas { context, size in
            guard readiness != .searching, edgeRadius > 0.02 else { return }
            let center = CGPoint(x: calibration.center.x * size.width, y: calibration.center.y * size.height)
            let edge = edgeRadius * size.width
            let scoring = max(calibration.radius, 0.02) * size.width
            var dim = Path(CGRect(origin: .zero, size: size))
            dim.addEllipse(in: CGRect(x: center.x - edge, y: center.y - edge, width: edge * 2, height: edge * 2))
            context.fill(dim, with: .color(.black.opacity(0.38)), style: FillStyle(eoFill: true))

            let rim = Path(ellipseIn: CGRect(x: center.x - edge, y: center.y - edge, width: edge * 2, height: edge * 2))
            context.stroke(rim, with: .color(locked), lineWidth: readiness == .edge ? 4 : 2)

            if readiness == .aligned {
                for ratio in [1, BoardRings.doubleInner, BoardRings.tripleOuter, BoardRings.tripleInner, BoardRings.outerBull, BoardRings.innerBull] {
                    let radius = scoring * ratio
                    let ring = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
                    context.stroke(ring, with: .color(locked.opacity(ratio == 1 ? 1 : 0.75)), lineWidth: ratio == 1 ? 3 : 1.1)
                }
                for index in 0..<20 {
                    let angle = Double(index) * (.pi / 10) - .pi / 2 - .pi / 20 + calibration.rotationDegrees * .pi / 180
                    var wire = Path()
                    wire.move(to: CGPoint(x: center.x + cos(angle) * scoring * BoardRings.outerBull, y: center.y + sin(angle) * scoring * BoardRings.outerBull))
                    wire.addLine(to: CGPoint(x: center.x + cos(angle) * scoring, y: center.y + sin(angle) * scoring))
                    context.stroke(wire, with: .color(locked.opacity(0.7)), lineWidth: 1)
                    let mid = angle + .pi / 20
                    let label = CGPoint(x: center.x + cos(mid) * scoring * 1.12, y: center.y + sin(mid) * scoring * 1.12)
                    context.draw(
                        Text("\(BoardGeometry.sectors[index])")
                            .font(.system(size: max(10, scoring * 0.08), weight: .bold, design: .rounded))
                            .foregroundColor(.white),
                        at: label
                    )
                }
            }

            context.fill(Path(ellipseIn: CGRect(x: center.x - 5, y: center.y - 5, width: 10, height: 10)), with: .color(locked))
            for mark in marks {
                let point = CGPoint(x: mark.point.x * size.width, y: mark.point.y * size.height)
                context.fill(Path(ellipseIn: CGRect(x: point.x - 7, y: point.y - 7, width: 14, height: 14)), with: .color(.white))
                context.draw(
                    Text(mark.label)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(.white),
                    at: CGPoint(x: point.x, y: point.y - 18)
                )
            }
        }
        .allowsHitTesting(false)
    }
}

struct BoardCalibrationView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var camera = CameraSession()
    @State private var track = BoardTrack()

    init(initial: BoardCalibration? = nil) {}

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            cameraLayer
            BoardFitCanvas(calibration: track.calibration, edgeRadius: track.edgeRadius, readiness: track.readiness)
                .ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").padding(12).background(.black.opacity(0.45), in: Circle())
                    }
                    Spacer()
                    if track.readiness != .searching {
                        Label(track.readiness == .aligned ? "Segmenty" : "Okraj", systemImage: "circle.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color(red: 0.28, green: 0.93, blue: 0.52))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.black.opacity(0.45), in: Capsule())
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.top, 10)
                Spacer()
                panel
            }
        }
        .preferredColorScheme(.dark)
        .toolbar(.hidden, for: .navigationBar)
        .task { await camera.prepare() }
        .onAppear {
            camera.noteMode(.calibrate)
            camera.onPacket = { packet in
                guard packet.previewWidth > 1, packet.previewHeight > 1 else { return }
                let frame = VisionFrame(
                    bufferWidth: packet.bufferWidth, bufferHeight: packet.bufferHeight,
                    previewWidth: packet.previewWidth, previewHeight: packet.previewHeight
                )
                let solution: BoardSolution?
                if packet.hasCircle {
                    solution = BoardVision.solve(
                        circle: BoardVision.CircleSample(
                            center: NormPoint(x: packet.circleX, y: packet.circleY),
                            radius: packet.circleRadius,
                            residual: packet.residual
                        ),
                        numbers: packet.numbers.map { BoardVision.NumberSample(value: $0.value, center: NormPoint(x: $0.x, y: $0.y)) },
                        frame: frame
                    )
                } else {
                    solution = nil
                }
                track.ingest(solution)
            }
        }
        .onDisappear {
            camera.stop()
            if track.readiness == .aligned { persist() }
        }
        .onChange(of: track.wantsSave) { _, wants in
            guard wants else { return }
            persist()
            track.markSaved()
        }
        .onChange(of: track.readiness) { old, new in
            if new == .edge, old == .searching { store.feedback() }
            if new == .aligned, old != .aligned { store.feedback() }
        }
    }

    private var cameraLayer: some View {
        Group {
            switch camera.status {
            case .ready, .idle, .requesting:
                CameraPreview(session: camera.session, device: camera.device, onLayout: { camera.notePreviewSize($0) }, onCaptureAngle: { camera.setCaptureRotation($0) })
                    .ignoresSafeArea()
                if camera.status != .ready {
                    ProgressView("Kamera…").tint(.white)
                }
            case .denied:
                fallback("Povol kameru v Nastavení", settings: true)
            case .unavailable:
                fallback("Kamera není dostupná", settings: false)
            }
        }
    }

    private func fallback(_ text: String, settings: Bool) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.fill").font(.system(size: 40)).foregroundStyle(Theme.accent)
            Text(text).font(AppFont.title(20)).foregroundStyle(.white).multilineTextAlignment(.center)
            if settings {
                Button("Nastavení") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                .buttonStyle(.glassProminent)
                .tint(Theme.brand)
            }
        }
        .padding(24)
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(track.status)
                .font(AppFont.title(20))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            Text("Celý terč nech ve snímku. Kruh zezelená na okraji a čísla sama otočí segmenty.")
                .font(AppFont.body(14))
                .foregroundStyle(.white.opacity(0.76))
            HStack(spacing: 10) {
                Button("Znovu") {
                    track.reset()
                    camera.resetVision()
                }
                .buttonStyle(.glass)
                Button("Hotovo") { dismiss() }
                    .buttonStyle(.glassProminent)
                    .tint(Theme.brand)
                    .disabled(track.readiness != .aligned)
            }
            .font(.headline)
        }
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    private func persist() {
        var ready = track.calibration.sanitized()
        ready.calibratedAt = Date()
        store.saveBoardCalibration(ready)
    }
}
