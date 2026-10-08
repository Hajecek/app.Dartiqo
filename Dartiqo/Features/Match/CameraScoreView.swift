import SwiftUI
import simd

/// Živá kamera v zápase. Uloženou mapu terče přepočítá na velikost tohoto náhledu a novou šipku zapíše, jakmile chvíli drží na místě.
struct CameraScoreView: View {
    var calibration: BoardCalibration?
    var labels: [String]
    var dartCount: Int
    var onDart: (Dart, SIMD2<Double>?) -> Bool
    /// Klepnutí na hod z kamery otevře opravu.
    var onCorrect: ((Int) -> Void)? = nil

    @EnvironmentObject private var store: AppStore
    @StateObject private var camera = CameraSession()
    @State private var watch = DartWatch()
    /// Mapa dorovnaná podle živého obrazu, když se telefon trochu pohne.
    @State private var liveCamera: [Double]?
    @State private var calibrating = false
    @State private var region: (key: String, mask: [Bool])?

    private var usable: BoardCalibration? {
        guard let calibration, calibration.isCalibrated, calibration.isCameraMapped else { return nil }
        return calibration
    }

    var body: some View {
        Group {
            if let usable, !calibrating {
                live(calibration: usable)
            } else {
                missing
            }
        }
        .sheet(isPresented: $calibrating) {
            BoardCalibrationView()
        }
        .onChange(of: calibrating) { _, open in
            if open { camera.stop() }
        }
        .onChange(of: dartCount) { old, new in
            guard new < old else { return }
            let extra = watch.known.count - new
            if extra > 0 { watch.undo(steps: extra) }
        }
        .onChange(of: watch.phaseIsSettling) { _, settling in
            camera.holdExposure(!settling)
        }
    }

    private func live(calibration: BoardCalibration) -> some View {
        GeometryReader { proxy in
            let fitted = current(calibration).fitted(previewWidth: proxy.size.width, previewHeight: proxy.size.height)
            let mapper = BoardMapper(calibration: fitted)
            let marks = watch.known.map { point in (point: point, label: mapper.dart(at: point).label) }
            ZStack(alignment: .bottom) {
                CameraPreview(
                    session: camera.session,
                    device: camera.device,
                    onLayout: { camera.notePreviewSize($0) },
                    onCaptureAngle: { camera.setCaptureRotation($0) }
                )
                BoardFitCanvas(calibration: fitted, readiness: .aligned, marks: marks, showsTwenty: false)
                VStack(spacing: 10) {
                    Text(watch.status)
                        .font(AppFont.caption(13, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.55), in: Capsule())
                    if !labels.isEmpty { CameraHitChips(labels: labels, onCorrect: onCorrect) }
                    Button("Mimo") { _ = onDart(.miss, nil) }
                        .buttonStyle(.glass)
                        .disabled(dartCount >= 3)
                }
                .padding(.bottom, 12)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .task {
            camera.noteMode(.score)
            camera.onPacket = { packet in consume(packet, calibration: calibration) }
            await camera.prepare()
            camera.setZoom(calibration.zoom ?? 1)
        }
        .onDisappear {
            camera.stop()
            if let liveCamera, liveCamera != calibration.camera {
                var updated = calibration
                updated.camera = liveCamera
                store.saveBoardCalibration(updated)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Kamera, \(watch.status)")
    }

    private var missing: some View {
        let stale = calibration?.isCalibrated == true
        return VStack(spacing: 14) {
            Image(systemName: "camera.viewfinder").font(.system(size: 36)).foregroundStyle(Theme.brand)
            Text(stale ? "Nastav terč ještě jednou." : "Kamera potřebuje nastavený terč.")
                .font(AppFont.title(20))
                .multilineTextAlignment(.center)
            Text(stale
                 ? "Nová kalibrace si mapu uloží vůči kameře, takže pak sedí i v tomhle okně."
                 : "Sama najde terč podle barev segmentů a podle mapy pak pozná hod.")
                .font(AppFont.body(15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Nastavit terč") { calibrating = true }
                .buttonStyle(.glassProminent)
                .tint(Theme.brand)
                .foregroundStyle(.black)
        }
        .foregroundStyle(.white)
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: 280)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func consume(_ packet: VisionPacket, calibration: BoardCalibration) {
        guard packet.lumaWidth > 1, packet.previewWidth > 1, dartCount < 3 else { return }
        let frame = VisionFrame(
            bufferWidth: packet.bufferWidth, bufferHeight: packet.bufferHeight,
            previewWidth: packet.previewWidth, previewHeight: packet.previewHeight
        )
        let base = current(calibration)
        refresh(with: packet.detection, base: base)
        let fitted = current(calibration).fitted(previewWidth: packet.previewWidth, previewHeight: packet.previewHeight)
        let vanish = base.camera.flatMap { DartAxis.vanishingPoint(camera: $0, aspect: base.cameraAspect ?? 0.5625, zoom: base.zoom ?? 1) }
        let mapper = BoardMapper(calibration: fitted)
        guard mapper.isReady else { return }
        let mask = boardMask(width: packet.lumaWidth, height: packet.lumaHeight, frame: frame, mapper: mapper)
        guard let point = watch.ingest(
            luma: packet.luma,
            width: packet.lumaWidth,
            height: packet.lumaHeight,
            frame: frame,
            center: fitted.center,
            region: mask,
            vanish: vanish,
            accept: { point in
                guard let board = mapper.boardPoint(from: point) else { return false }
                return hypot(board.x, board.y) <= 1.02
            }
        ) else { return }
        let seen = frame.bufferPoint(point)
        if onDart(mapper.dart(at: point), SIMD2(seen.x, seen.y)) {
            watch.confirm()
        } else {
            watch.reject()
        }
    }

    private func current(_ calibration: BoardCalibration) -> BoardCalibration {
        guard let liveCamera else { return calibration }
        var copy = calibration
        copy.camera = liveCamera
        return copy
    }

    /// Zapamatovanou mapu průběžně porovná s tím, co kamera vidí. Malý posun telefonu se dorovná sám,
    /// otočení čísel zůstává podle kalibrace.
    private func refresh(with detection: BoardDetection?, base: BoardCalibration) {
        guard watch.isIdle, let detection, detection.boundaries == 20, detection.error < 0.012,
              let found = detection.homography, let saved = base.camera else { return }
        let anchors = BoardTrack.boardAnchors
        let target = anchors.compactMap { PlaneFit.project(saved, $0) }
        guard target.count == anchors.count else { return }
        var best: (deviation: Double, matrix: [Double])?
        for step in 0..<20 {
            let angle = Double(step) * 18 * .pi / 180
            let matrix = PlaneFit.multiply(found, [cos(angle), -sin(angle), 0, sin(angle), cos(angle), 0, 0, 0, 1])
            let points = anchors.compactMap { PlaneFit.project(matrix, $0) }
            guard points.count == target.count else { continue }
            let deviation = zip(points, target).reduce(0) { $0 + simd_distance($1.0, $1.1) } / Double(points.count)
            if best == nil || deviation < best!.deviation { best = (deviation, matrix) }
        }
        guard let best, best.deviation > 0.002 else { return }
        liveCamera = best.matrix
        if best.deviation > 0.03 { watch.reset() }
    }

    /// Buňky jasu, které leží na terči nebo kousek za ním. Pohyb mimo terč se nesleduje.
    private func boardMask(width: Int, height: Int, frame: VisionFrame, mapper: BoardMapper) -> [Bool] {
        let key = "\(width)x\(height)-\(frame.previewWidth)x\(frame.previewHeight)-\(mapper.calibration.center.x)-\(mapper.calibration.radius)"
        if let region, region.key == key { return region.mask }
        var mask = [Bool](repeating: false, count: width * height)
        for row in 0..<height {
            for column in 0..<width {
                let buffer = NormPoint(x: (Double(column) + 0.5) / Double(width), y: (Double(row) + 0.5) / Double(height))
                guard let board = mapper.boardPoint(from: frame.previewPoint(buffer)) else { continue }
                mask[row * width + column] = hypot(board.x, board.y) <= 1.35
            }
        }
        region = (key, mask)
        return mask
    }
}

/// Hody z kamery v tomto kole. Klepnutím se otevře oprava, ze které se kamera učí.
struct CameraHitChips: View {
    var labels: [String]
    var ink: Color = .white
    var fill: Color = .black.opacity(0.55)
    var onCorrect: ((Int) -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                Button { onCorrect?(index) } label: {
                    HStack(spacing: 5) {
                        Text(label).font(AppFont.body(16, weight: .bold)).monospacedDigit()
                        if onCorrect != nil {
                            Image(systemName: "pencil").font(.system(size: 11, weight: .bold)).opacity(0.7)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .foregroundStyle(ink)
                    .background(fill, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(onCorrect == nil)
                .accessibilityLabel("\(index + 1). šipka \(label)")
                .accessibilityHint(onCorrect == nil ? "" : "Opravit pole")
            }
        }
    }
}
