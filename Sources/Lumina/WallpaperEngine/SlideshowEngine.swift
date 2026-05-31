import AppKit
import AVFoundation

/// Manages image slideshow cycling for a single monitor.
/// Uses a timer to advance slides and a crossfade CAAnimation for smooth transitions.
@MainActor
final class SlideshowEngine {
    private var imagePaths: [String] = []
    private var interval: Double = 10
    private var transition: MonitorAssignment.SlideshowTransition = .fade
    private var currentIndex: Int = 0
    private var timer: Timer?
    private weak var hostLayer: CALayer?

    private var currentImageLayer: CALayer?

    func configure(assignment: MonitorAssignment, hostLayer: CALayer) {
        configure(items: assignment.slideshowItems,
                  interval: assignment.slideshowInterval,
                  transition: assignment.slideshowTransition,
                  hostLayer: hostLayer)
    }

    /// Direct configuration used by the renderer (no MonitorAssignment needed).
    func configure(items: [String],
                   interval: Double,
                   transition: MonitorAssignment.SlideshowTransition,
                   hostLayer: CALayer) {
        self.imagePaths   = items
        self.interval     = max(1, interval)
        self.transition   = transition
        self.hostLayer    = hostLayer
        self.currentIndex = 0
        start()
    }

    /// Stops the slideshow and removes its layer from the host (full teardown).
    func teardown() {
        stop()
        currentImageLayer?.removeFromSuperlayer()
        currentImageLayer = nil
        hostLayer = nil
        imagePaths = []
    }

    /// Resizes the current slide to match a new host-layer bounds (display reconfiguration).
    func relayout() {
        guard let host = hostLayer else { return }
        currentImageLayer?.frame = host.bounds
    }

    func start() {
        stop()
        guard !imagePaths.isEmpty, let host = hostLayer else { return }

        // Show first image immediately
        showImage(at: 0, in: host, animated: false)

        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.advance() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func advance() {
        guard !imagePaths.isEmpty, let host = hostLayer else { return }
        currentIndex = (currentIndex + 1) % imagePaths.count
        showImage(at: currentIndex, in: host, animated: transition == .fade)
    }

    private func showImage(at index: Int, in host: CALayer, animated: Bool) {
        guard index < imagePaths.count else { return }
        let path = (imagePaths[index] as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: path)
        // Decode at display resolution to avoid holding full-size photos in memory.
        let maxDim = max(host.bounds.width, host.bounds.height) * max(1, host.contentsScale)
        let maxPixel = maxDim > 1 ? maxDim : 3840
        guard let cgImage = CGImageSourceCreateWithURL(url as CFURL, nil)
                .flatMap({ AVVideoRenderer.downsampledImage(source: $0, index: 0, maxPixelSize: maxPixel) })
                ?? NSImage(contentsOfFile: path)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return }

        let newLayer = CALayer()
        newLayer.contents = cgImage
        newLayer.contentsGravity = .resizeAspectFill
        newLayer.frame = host.bounds
        host.addSublayer(newLayer)

        if animated {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0.0
            fade.toValue   = 1.0
            fade.duration  = min(1.5, interval * 0.3)
            newLayer.opacity = 1.0
            newLayer.add(fade, forKey: "fadeIn")
        }

        // Remove the old layer after transition
        let old = currentImageLayer
        let delay = animated ? min(1.5, interval * 0.3) : 0
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            old?.removeFromSuperlayer()
        }
        currentImageLayer = newLayer
    }
}
