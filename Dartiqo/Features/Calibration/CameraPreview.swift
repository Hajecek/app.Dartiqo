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
    private var configured = false

    func prepare() async {
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
        guard session.isRunning else { return }
        session.stopRunning()
    }

    private func start() {
        guard configured else { status = .unavailable; return }
        let capture = session
        DispatchQueue.global(qos: .userInitiated).async {
            if !capture.isRunning { capture.startRunning() }
            Task { @MainActor in self.status = .ready }
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
        session.addInput(input)
        configured = true
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.videoPreviewLayer.session = session
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoPreviewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
