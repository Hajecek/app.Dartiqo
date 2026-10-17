import ImageIO
import SwiftUI
import UIKit

/// Oslavná animace 180 — hold návštěvy ji nesmí useknout.
enum OneEightyCelebration {
    static let resource = "180"
    /// Délka `Resources/180.gif` (43 snímků). Přesný konec hlásí přehrávač.
    static let duration: TimeInterval = 2.9

    static func shouldPlay(credited: Int, bust: Bool, reduceMotion: Bool) -> Bool {
        !reduceMotion && !bust && credited == 180
    }
}

/// Celá obrazovka edge-to-edge — GIF jednou doběhne a zmizí.
struct OneEightyCelebrationOverlay: View {
    let onFinished: () -> Void

    @State private var visible = false
    @State private var finished = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black
                CelebrationFillGIF(resource: OneEightyCelebration.resource) {
                    dismiss()
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .scaleEffect(visible ? 1 : 1.03)
            .opacity(visible ? 1 : 0)
        }
        .ignoresSafeArea()
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            withAnimation(.easeOut(duration: 0.28)) { visible = true }
            // Pojistka, kdyby notifikace o konci GIFu nepřišla.
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64((OneEightyCelebration.duration + 0.6) * 1_000_000_000))
                dismiss()
            }
        }
    }

    private func dismiss() {
        guard !finished else { return }
        finished = true
        withAnimation(.easeIn(duration: 0.32)) { visible = false }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 320_000_000)
            onFinished()
        }
    }
}

/// GIF přes celý rámec, jednou, bez ovládání.
private struct CelebrationFillGIF: UIViewRepresentable {
    let resource: String
    let onEnded: () -> Void

    final class Coordinator: NSObject, CAAnimationDelegate {
        var onEnded: (() -> Void)?
        private var fired = false

        func animationDidStop(_ anim: CAAnimation, finished flag: Bool) {
            guard flag, !fired else { return }
            fired = true
            onEnded?()
        }
    }

    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator()
        coordinator.onEnded = onEnded
        return coordinator
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        view.clipsToBounds = true
        view.isUserInteractionEnabled = false
        view.layer.contentsGravity = .resizeAspectFill
        view.layer.masksToBounds = true

        guard let animation = Self.makeAnimation(resource: resource) else {
            DispatchQueue.main.async {
                context.coordinator.animationDidStop(CAAnimation(), finished: true)
            }
            return view
        }
        animation.delegate = context.coordinator
        view.layer.add(animation, forKey: "gif")
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.onEnded = nil
        uiView.layer.removeAnimation(forKey: "gif")
    }

    private static func makeAnimation(resource: String) -> CAKeyframeAnimation? {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "gif")
                ?? Bundle.main.url(forResource: resource, withExtension: "gif", subdirectory: "Resources"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil)
        else { return nil }

        let count = CGImageSourceGetCount(source)
        guard count > 0 else { return nil }

        var frames: [CGImage] = []
        var delays: [TimeInterval] = []
        frames.reserveCapacity(count)
        for index in 0..<count {
            guard let frame = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }
            frames.append(frame)
            delays.append(frameDelay(source: source, index: index))
        }
        guard !frames.isEmpty else { return nil }

        let total = delays.reduce(0, +)
        var elapsed: TimeInterval = 0
        let keyTimes: [NSNumber] = delays.map { delay in
            let time = total > 0 ? elapsed / total : 0
            elapsed += delay
            return NSNumber(value: time)
        }

        let animation = CAKeyframeAnimation(keyPath: "contents")
        animation.values = frames
        animation.keyTimes = keyTimes
        animation.duration = total > 0 ? total : OneEightyCelebration.duration
        animation.repeatCount = 1
        animation.calculationMode = .discrete
        animation.isRemovedOnCompletion = false
        animation.fillMode = .forwards
        return animation
    }

    private static func frameDelay(source: CGImageSource, index: Int) -> TimeInterval {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
              let gif = props[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        else { return 0.1 }
        let unclamped = gif[kCGImagePropertyGIFUnclampedDelayTime] as? Double
        let clamped = gif[kCGImagePropertyGIFDelayTime] as? Double
        let delay = unclamped ?? clamped ?? 0.1
        return delay > 0 ? delay : 0.1
    }
}
