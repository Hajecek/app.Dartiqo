import SwiftUI

struct BoardFitCanvas: View {
    var calibration: BoardCalibration
    var rim: [NormPoint] = []
    var readiness: BoardReadiness
    var marks: [(point: NormPoint, label: String)] = []
    /// Malá 20 nad terčem, aby šlo poznat otočení. V zápase není potřeba.
    var showsTwenty = true

    private let locked = Color(red: 0.28, green: 0.93, blue: 0.52)

    var body: some View {
        Canvas { context, size in
            guard readiness != .searching else { return }
            func point(_ normalized: NormPoint) -> CGPoint {
                CGPoint(x: normalized.x * size.width, y: normalized.y * size.height)
            }
            func outline(_ points: [NormPoint]) -> Path {
                var path = Path()
                guard let first = points.first else { return path }
                path.move(to: point(first))
                for next in points.dropFirst() { path.addLine(to: point(next)) }
                path.closeSubpath()
                return path
            }
            let mapper = BoardMapper(calibration: calibration)

            if readiness == .aligned, mapper.isReady {
                let red = Color(red: 0.95, green: 0.18, blue: 0.2)
                let green = Color(red: 0.2, green: 0.85, blue: 0.35)
                for (index, segment) in BoardGeometry.sectors.enumerated() {
                    let color = index.isMultiple(of: 2) ? red : green
                    for multiplier in [2, 3] {
                        guard let band = mapper.bandOutline(segment: segment, multiplier: multiplier) else { continue }
                        context.stroke(outline(band), with: .color(color.opacity(0.95)), lineWidth: 1.6)
                    }
                }
                context.stroke(outline(mapper.circle(radius: 1, samples: 120)), with: .color(Theme.brand), lineWidth: 2.4)
                context.stroke(outline(mapper.circle(radius: BoardRings.outerBull, samples: 40)), with: .color(green), lineWidth: 1.6)
                context.stroke(outline(mapper.circle(radius: BoardRings.innerBull, samples: 24)), with: .color(red), lineWidth: 1.6)
                if let bull = mapper.imagePoint(boardX: 0, boardY: 0) {
                    let center = point(bull)
                    let arm = max(8, calibration.radius * size.width * 0.07)
                    var cross = Path()
                    cross.move(to: CGPoint(x: center.x - arm, y: center.y))
                    cross.addLine(to: CGPoint(x: center.x + arm, y: center.y))
                    cross.move(to: CGPoint(x: center.x, y: center.y - arm))
                    cross.addLine(to: CGPoint(x: center.x, y: center.y + arm))
                    context.stroke(cross, with: .color(.white), lineWidth: 1.4)
                }
                if showsTwenty, let top = mapper.imagePoint(boardX: 0, boardY: -1.1) {
                    context.draw(
                        Text("20").font(.system(size: max(11, calibration.radius * size.width * 0.07), weight: .heavy, design: .rounded))
                            .foregroundColor(Theme.brand),
                        at: point(top)
                    )
                }
            } else if rim.count > 8 {
                context.stroke(outline(rim), with: .color(locked), style: StrokeStyle(lineWidth: 3, dash: [8, 6]))
            }

            for mark in marks {
                let point = CGPoint(x: mark.point.x * size.width, y: mark.point.y * size.height)
                let dot = Path(ellipseIn: CGRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10))
                context.fill(dot, with: .color(Theme.brand))
                context.stroke(dot, with: .color(.black), lineWidth: 1.5)
                context.draw(
                    Text(mark.label)
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .foregroundColor(.white),
                    at: CGPoint(x: point.x, y: point.y - 14)
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
    @State private var lastFrame: VisionFrame?
    @State private var zoom = 1.0
    @State private var showHelp = false

    private let good = Color(red: 0.28, green: 0.93, blue: 0.52)

    init(initial: BoardCalibration? = nil) {}

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(.white.opacity(0.12))
            ScrollView {
                VStack(spacing: 16) {
                    gauges
                    preview
                    zoomRow
                    Divider().overlay(.white.opacity(0.12))
                    Text("Navádění je jen doporučení. Uložit jde, jakmile zelená mapa sedí na drátech.")
                        .font(AppFont.caption(13))
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                    actions
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .sheet(isPresented: $showHelp) { help }
        .task {
            await camera.prepare()
            if let saved = store.boardCalibration?.zoom, saved > 1 {
                zoom = min(saved, camera.maxZoom)
                camera.setZoom(zoom)
            }
        }
        .onAppear {
            camera.noteMode(.calibrate)
            camera.onPacket = { packet in
                guard packet.previewWidth > 1, packet.previewHeight > 1 else { return }
                let frame = VisionFrame(
                    bufferWidth: packet.bufferWidth, bufferHeight: packet.bufferHeight,
                    previewWidth: packet.previewWidth, previewHeight: packet.previewHeight
                )
                if lastFrame != frame { lastFrame = frame }
                track.ingest(BoardVision.solve(packet.detection, frame: frame))
            }
        }
        .onDisappear { camera.stop() }
        .onChange(of: zoom) { _, value in
            camera.setZoom(value)
            track.reset()
            camera.resetVision()
        }
        .onChange(of: track.readiness) { old, new in
            if new == .aligned, old != .aligned { store.feedback() }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left").font(.system(size: 20, weight: .semibold))
            }
            .accessibilityLabel("Zpět")
            Text("Kalibrace").font(AppFont.title(24))
            Spacer()
            Button { showHelp = true } label: {
                Image(systemName: "questionmark.circle").font(.system(size: 22))
            }
            .accessibilityLabel("Nápověda")
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var gauges: some View {
        HStack(spacing: 10) {
            ForEach(CalibrationGuide.gauges(for: track)) { gauge in
                GaugeCard(gauge: gauge, good: good)
            }
        }
    }

    private var preview: some View {
        ZStack {
            Color.black
            cameraLayer
            BoardFitCanvas(calibration: track.calibration, rim: track.rim, readiness: track.readiness)
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(alignment: .topTrailing) {
            Image(systemName: track.readiness == .aligned ? "camera.fill" : "camera")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(track.readiness == .aligned ? good : .white.opacity(0.7))
                .padding(8)
                .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(track.readiness == .aligned ? good : .clear, lineWidth: 1))
                .padding(10)
        }
        .overlay(alignment: .bottom) {
            HStack(spacing: 8) {
                if track.readiness == .aligned {
                    Button { track.rotate(by: -1) } label: { Image(systemName: "arrow.counterclockwise") }
                        .accessibilityLabel("Otočit čísla doleva")
                }
                Text(track.status)
                    .font(AppFont.caption(13, weight: .bold))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                if track.readiness == .aligned {
                    Button { track.rotate(by: 1) } label: { Image(systemName: "arrow.clockwise") }
                        .accessibilityLabel("Otočit čísla doprava")
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(.black.opacity(0.6), in: Capsule())
            .padding(10)
        }
    }

    private var zoomRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "minus.magnifyingglass")
            Slider(value: $zoom, in: 1...max(1.1, camera.maxZoom), step: 0.1)
                .tint(Theme.brand)
            Image(systemName: "plus.magnifyingglass")
            Text(String(format: "%.1fx", zoom))
                .font(AppFont.caption(13, weight: .bold))
                .monospacedDigit()
                .frame(width: 40, alignment: .trailing)
        }
        .foregroundStyle(.white.opacity(0.8))
        .padding(.top, 4)
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Button {
                persist()
                store.feedback()
                dismiss()
            } label: {
                Label("Uložit", systemImage: "checkmark")
                    .font(AppFont.body(17, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            .tint(Theme.brand)
            .foregroundStyle(.black)
            .disabled(track.readiness != .aligned)

            Button {
                dismiss()
            } label: {
                Text("Zrušit")
                    .font(AppFont.body(17, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.glass)
        }
    }

    private var help: some View {
        NavigationStack {
            List {
                Section("Postavení telefonu") {
                    Label("Telefon dej na stativ před terč, ideálně ve výšce bullu.", systemImage: "iphone")
                    Label("Celý terč s čísly má být ve čtverci. Pomůže zoom.", systemImage: "viewfinder")
                    Label("Terč osvětli rovnoměrně, bez ostrých stínů.", systemImage: "lightbulb")
                }
                Section("Jak poznám, že sedí") {
                    Label("Zelené kruhy leží na doublu, triplu a bullu.", systemImage: "circle.circle")
                    Label("Žlutá 20 je nad segmentem 20. Jinak ji otoč šipkami.", systemImage: "arrow.clockwise")
                }
                Section("Učení") {
                    Label("V zápase klepni na hod z kamery a oprav ho. Mapa se z oprav doučí.", systemImage: "brain")
                }
            }
            .navigationTitle("Nápověda")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Hotovo") { showHelp = false } }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var cameraLayer: some View {
        Group {
            switch camera.status {
            case .ready, .idle, .requesting:
                CameraPreview(session: camera.session, device: camera.device, onLayout: { camera.notePreviewSize($0) }, onCaptureAngle: { camera.setCaptureRotation($0) })
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

    private func persist() {
        var ready = track.calibration.sanitized()
        ready.calibratedAt = Date()
        ready.zoom = zoom > 1.01 ? zoom : nil
        if let frame = lastFrame, let matrix = ready.homography,
           let back = PlaneFit.invert(BoardVision.previewTransform(frame)) {
            ready.camera = PlaneFit.multiply(back, matrix)
            ready.cameraAspect = frame.bufferAspect
        }
        store.saveBoardCalibration(ready)
        track.markSaved()
    }
}

private struct GaugeCard: View {
    var gauge: CalibrationGauge
    var good: Color

    private var color: Color { gauge.isGood ? good : Theme.brand }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().stroke(.white.opacity(0.12), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: max(0.02, gauge.value))
                    .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int((gauge.value * 100).rounded()))%")
                    .font(AppFont.caption(13, weight: .bold))
                    .foregroundStyle(.white)
                    .monospacedDigit()
            }
            .frame(width: 48, height: 48)
            .animation(.smooth(duration: 0.3), value: gauge.value)
            Text(gauge.title)
                .font(AppFont.body(14, weight: .semibold))
                .foregroundStyle(.white)
            Text(gauge.hint)
                .font(AppFont.caption(12, weight: .bold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 6)
        .background(color.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(color.opacity(0.7), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}
