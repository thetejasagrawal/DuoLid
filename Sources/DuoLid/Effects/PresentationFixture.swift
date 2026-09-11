import AppKit
import QuartzCore

/// A moving, synthetic window for the live ScreenCaptureKit diagnostic. The
/// capture filter includes this window and excludes the rendered test output.
/// No image from this test is written to disk or included in its timing report.
@MainActor
final class PresentationFixture {
    let window: NSWindow

    init(screen: NSScreen) {
        let area = screen.visibleFrame
        let size = CGSize(width: min(720, area.width - 40), height: 220)
        window = NSWindow(
            contentRect: CGRect(x: area.minX + 20, y: area.minY + 20, width: size.width, height: size.height),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "DuoLid · Moving capture test"
        window.isReleasedWhenClosed = false
        window.isOpaque = true
        window.backgroundColor = .black
        let view = NSView(frame: CGRect(origin: .zero, size: size))
        view.wantsLayer = true
        window.contentView = view
        guard let root = view.layer else { return }
        root.masksToBounds = true
        root.backgroundColor = NSColor(srgbRed: 0.06, green: 0.07, blue: 0.10, alpha: 1).cgColor

        let title = CATextLayer()
        title.string = "Live capture · moving text and fine edges"
        title.font = NSFont.systemFont(ofSize: 16, weight: .medium)
        title.fontSize = 16
        title.contentsScale = screen.backingScaleFactor
        title.foregroundColor = NSColor.white.cgColor
        title.frame = CGRect(x: 20, y: size.height - 42, width: size.width - 40, height: 24)
        root.addSublayer(title)

        for row in 0..<3 {
            let tile = CALayer()
            tile.bounds = CGRect(x: 0, y: 0, width: 180, height: 34)
            tile.position = CGPoint(x: 120, y: 36 + row * 46)
            tile.cornerRadius = 6
            tile.backgroundColor =
                NSColor(
                    srgbRed: 0.23 + Double(row) * 0.16, green: 0.37, blue: 0.72, alpha: 1
                ).cgColor
            root.addSublayer(tile)
            let label = CATextLayer()
            label.string = "DuoLid  Aa  0123456789"
            label.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)
            label.fontSize = 12
            label.contentsScale = screen.backingScaleFactor
            label.foregroundColor = NSColor.white.cgColor
            label.frame = CGRect(x: 10, y: 8, width: 170, height: 18)
            tile.addSublayer(label)

            let animation = CABasicAnimation(keyPath: "position.x")
            animation.fromValue = row % 2 == 0 ? 120 : size.width - 120
            animation.toValue = row % 2 == 0 ? size.width - 120 : 120
            animation.duration = 1.2 + Double(row) * 0.4
            animation.autoreverses = true
            animation.repeatCount = .infinity
            animation.timingFunction = CAMediaTimingFunction(name: .linear)
            tile.add(animation, forKey: "capture-motion")
        }
    }

    func show() { window.orderFront(nil) }
    func close() {
        window.orderOut(nil)
        window.contentView?.layer?.sublayers?.forEach { $0.removeAllAnimations() }
        window.close()
    }
}
