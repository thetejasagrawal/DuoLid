import CoreGraphics
import CoreMedia
import CoreVideo
import ScreenCaptureKit

@MainActor
enum CaptureConfiguration {
    /// Shared by production and presentation diagnostics. The latest-frame slot
    /// and two GPU readers remain bounded; reserve capacity for capture and
    /// compositor handoff instead of building a queue of old frames in the app.
    static func make(filter: SCContentFilter, framesPerSecond: Int) -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        configuration.width = Int((filter.contentRect.width * CGFloat(filter.pointPixelScale)).rounded())
        configuration.height = Int((filter.contentRect.height * CGFloat(filter.pointPixelScale)).rounded())
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: Int32(framesPerSecond))
        // Apple's ScreenCaptureKit guidance recommends five surfaces for 4K/60.
        // https://developer.apple.com/videos/play/wwdc2022/10155/
        configuration.queueDepth = 5
        configuration.showsCursor = false
        configuration.capturesAudio = false
        configuration.colorSpaceName = CGColorSpace.sRGB
        return configuration
    }
}
