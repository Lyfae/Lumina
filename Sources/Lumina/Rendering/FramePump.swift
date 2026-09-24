// Lumina/Rendering/FramePump — AVPlayerItemVideoOutput + display-link presentation cap.
// Caps presentation/compositing rate only; decode savings come from variants.
// Enabled only when `power.experimentalRenderCap` is true (off by default; measure first).
import AppKit
import AVFoundation
import QuartzCore

@MainActor
final class FramePump {
    private let output: AVPlayerItemVideoOutput
    private var link: CADisplayLink?
    private var layers: [ObjectIdentifier: CALayer] = [:]
    private let preferredFPS: Float

    init(item: AVPlayerItem, maxFPS: Int) {
        preferredFPS = Float(max(1, maxFPS))
        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
        ]
        output = AVPlayerItemVideoOutput(pixelBufferAttributes: attrs)
        item.add(output)
    }

    func add(_ layer: CALayer) {
        layers[ObjectIdentifier(layer)] = layer
    }

    func remove(_ layer: CALayer) {
        layers.removeValue(forKey: ObjectIdentifier(layer))
    }

    func start() {
        guard link == nil else { return }
        guard let screen = NSScreen.main else { return }
        let displayLink = screen.displayLink(target: self, selector: #selector(tick))
        let fps = preferredFPS
        displayLink.preferredFrameRateRange = CAFrameRateRange(
            minimum: max(1, fps / 2),
            maximum: fps,
            preferred: fps
        )
        displayLink.add(to: .main, forMode: .common)
        link = displayLink
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    func teardown(item: AVPlayerItem?) {
        stop()
        item?.remove(output)
        layers.removeAll()
    }

    @objc private func tick() {
        let host = CACurrentMediaTime()
        let itemTime = output.itemTime(forHostTime: host)
        guard output.hasNewPixelBuffer(forItemTime: itemTime),
              let buffer = output.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: nil)
        else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for layer in layers.values {
            layer.contents = buffer
        }
        CATransaction.commit()
    }
}
