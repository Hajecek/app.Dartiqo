import SwiftUI

/// Živá kamera v zápase. Použije uloženou mapu terče a novou šipku zapíše, jakmile chvíli drží na místě.
struct CameraScoreView: View {
    var calibration: BoardCalibration?
    var labels: [String]
    var dartCount: Int
    var onDart: (Dart) -> Bool

    @StateObject private var camera = CameraSession()
    @State private var watch = DartWatch()
    @State private var calibrating = false

    private var mapper: BoardMapper? {
        guard let calibration else { return nil }
        let mapper = BoardMapper(calibration: calibration)
        return mapper.isReady ? mapper : nil
    }

    var body: some View {
        Group {
            if let calibration, let mapper, !calibrating {
                live(calibration: calibration, mapper: mapper)
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
    }

    private func live(calibration: BoardCalibration, mapper: BoardMapper) -> some View {
        let marks = watch.known.map { point in (point: point, label: mapper.dart(at: point).label) }
        return ZStack(alignment: .bottom) {
            CameraPreview(
                session: camera.session,
                device: camera.device,
                onLayout: { camera.notePreviewSize($0) },
                onCaptureAngle: { camera.setCaptureRotation($0) }
            )
            BoardFitCanvas(calibration: calibration, edgeRadius: calibration.radius, readiness: .aligned, marks: marks)
            VStack(spacing: 10) {
                Text(watch.status)
                    .font(AppFont.caption(13, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.55), in: Capsule())
                if !labels.isEmpty {
                    Text(labels.joined(separator: " · "))
                        .font(AppFont.body(16, weight: .bold))
                        .foregroundStyle(.white)
                }
                Button("Mimo") { _ = onDart(.miss) }
                    .buttonStyle(.glass)
                    .disabled(dartCount >= 3)
            }
            .padding(.bottom, 12)
        }
        .frame(minHeight: 460)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .task {
            camera.noteMode(.score)
            camera.onPacket = { packet in consume(packet, calibration: calibration, mapper: mapper) }
            await camera.prepare()
        }
        .onDisappear { camera.stop() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Kamera, \(watch.status)")
    }

    private var missing: some View {
        VStack(spacing: 14) {
            Image(systemName: "camera.viewfinder").font(.system(size: 36)).foregroundStyle(Theme.brand)
            Text("Kamera potřebuje nastavený terč.")
                .font(AppFont.title(20))
                .multilineTextAlignment(.center)
            Text("Sama najde okraj, přečte čísla a podle toho pak pozná hod.")
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

    private func consume(_ packet: VisionPacket, calibration: BoardCalibration, mapper: BoardMapper) {
        guard packet.lumaWidth > 1, packet.previewWidth > 1, dartCount < 3 else { return }
        let frame = VisionFrame(
            bufferWidth: packet.bufferWidth, bufferHeight: packet.bufferHeight,
            previewWidth: packet.previewWidth, previewHeight: packet.previewHeight
        )
        guard let point = watch.ingest(
            luma: packet.luma,
            width: packet.lumaWidth,
            height: packet.lumaHeight,
            frame: frame,
            center: calibration.center,
            accept: { point in
                guard let board = mapper.boardPoint(from: point) else { return false }
                return hypot(board.x, board.y) <= 1.02
            }
        ) else { return }
        if onDart(mapper.dart(at: point)) {
            watch.confirm()
        } else {
            watch.reject()
        }
    }
}
