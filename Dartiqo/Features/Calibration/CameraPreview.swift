import SwiftUI
import AVFoundation
import Combine

@MainActor
final class CameraSession: NSObject, ObservableObject {
    enum Status: Equatable {
        case idle, requesting, ready, denied, unavailable
    }

    @Published private(set) var status: Status = .idle
    let session = AVCaptureSession()
    private(set) var device: AVCaptureDevice?
    var onPacket: ((VisionPacket) -> Void)?

    private let relay = FrameRelay()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "dartiqo.camera.session")
    private var configured = false
    private var captureAngle: CGFloat = 90

    func prepare() async {
        relay.deliver = { [weak self] packet in
            Task { @MainActor in self?.onPacket?(packet) }
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureIfNeeded()
            start()
        case .notDetermined:
            status = .requesting
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if granted { configureIfNeeded(); start() } else { status = .denied }
        case .denied, .restricted:
            status = .denied
        @unknown default:
            status = .unavailable
        }
    }

    func stop() {
        let capture = session
        sessionQueue.async {
            if capture.isRunning { capture.stopRunning() }
        }
    }

    func notePreviewSize(_ size: CGSize) { relay.setPreview(size) }
    func noteMode(_ mode: VisionMode) { relay.setMode(mode) }
    func resetVision() { relay.reset() }

    func setCaptureRotation(_ angle: CGFloat) {
        captureAngle = angle
        applyCaptureRotation()
    }

    private func start() {
        guard configured else { status = .unavailable; return }
        let capture = session
        sessionQueue.async {
            if !capture.isRunning { capture.startRunning() }
            Task { @MainActor in
                self.status = .ready
                self.applyCaptureRotation()
            }
        }
    }

    private func configureIfNeeded() {
        guard !configured else { return }
        session.beginConfiguration()
        session.sessionPreset = .high
        defer { session.commitConfiguration() }
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            status = .unavailable
            return
        }
        try? device.lockForConfiguration()
        if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
        if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
        device.unlockForConfiguration()
        session.addInput(input)
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
        videoOutput.setSampleBufferDelegate(relay, queue: relay.queue)
        guard session.canAddOutput(videoOutput) else {
            status = .unavailable
            return
        }
        session.addOutput(videoOutput)
        self.device = device
        configured = true
    }

    private func applyCaptureRotation() {
        let angle = captureAngle
        let output = videoOutput
        sessionQueue.async {
            guard let connection = output.connection(with: .video),
                  connection.isVideoRotationAngleSupported(angle) else { return }
            connection.videoRotationAngle = angle
        }
    }
}

nonisolated private final class FrameRelay: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let queue = DispatchQueue(label: "dartiqo.camera.frames", qos: .userInitiated)
    let analyzer = BoardFrameAnalyzer()
    var deliver: ((VisionPacket) -> Void)?
    private let lock = NSLock()
    private var preview = CGSize.zero
    private var mode = VisionMode.calibrate
    private var busy = false
    private var last = CFAbsoluteTime(0)

    func setPreview(_ size: CGSize) {
        lock.lock(); preview = size; lock.unlock()
    }

    func setMode(_ mode: VisionMode) {
        lock.lock(); self.mode = mode; lock.unlock()
    }

    func reset() { analyzer.reset() }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = CFAbsoluteTimeGetCurrent()
        lock.lock()
        if busy || now - last < 0.12 { lock.unlock(); return }
        busy = true
        last = now
        let preview = preview
        let mode = mode
        lock.unlock()
        guard preview.width > 1, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            lock.lock(); busy = false; lock.unlock(); return
        }
        let packet = analyzer.makePacket(buffer, preview: preview, mode: mode)
        deliver?(packet)
        lock.lock(); busy = false; lock.unlock()
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    var device: AVCaptureDevice?
    var onLayout: (CGSize) -> Void
    var onCaptureAngle: (CGFloat) -> Void

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        view.onLayout = onLayout
        view.onCaptureAngle = onCaptureAngle
        view.attach(session: session, device: device)
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.onLayout = onLayout
        uiView.onCaptureAngle = onCaptureAngle
        uiView.attach(session: session, device: device)
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoPreviewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
        var onLayout: ((CGSize) -> Void)?
        var onCaptureAngle: ((CGFloat) -> Void)?
        private var coordinator: AVCaptureDevice.RotationCoordinator?
        private var observations: [NSKeyValueObservation] = []
        private weak var attachedDevice: AVCaptureDevice?

        func attach(session: AVCaptureSession, device: AVCaptureDevice?) {
            if videoPreviewLayer.session !== session { videoPreviewLayer.session = session }
            guard let device, attachedDevice !== device else { return }
            attachedDevice = device
            let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: videoPreviewLayer)
            self.coordinator = coordinator
            observations = [
                coordinator.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.initial, .new]) { [weak self] coordinator, _ in
                    let angle = coordinator.videoRotationAngleForHorizonLevelPreview
                    DispatchQueue.main.async { self?.applyPreview(angle) }
                },
                coordinator.observe(\.videoRotationAngleForHorizonLevelCapture, options: [.initial, .new]) { [weak self] coordinator, _ in
                    let angle = coordinator.videoRotationAngleForHorizonLevelCapture
                    DispatchQueue.main.async { self?.onCaptureAngle?(angle) }
                }
            ]
            applyPreview(coordinator.videoRotationAngleForHorizonLevelPreview)
            onCaptureAngle?(coordinator.videoRotationAngleForHorizonLevelCapture)
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            onLayout?(bounds.size)
            if let coordinator { applyPreview(coordinator.videoRotationAngleForHorizonLevelPreview) }
        }

        private func applyPreview(_ angle: CGFloat) {
            guard let connection = videoPreviewLayer.connection, connection.isVideoRotationAngleSupported(angle) else { return }
            connection.videoRotationAngle = angle
        }
    }
}
