import Foundation
import ScreenCaptureKit

enum CaptureExclusion: String, Encodable { case window, application }

@MainActor
enum CaptureFilter {
    /// Prefer the specific surface: it keeps the settings window in the image
    /// without rebuilding a composition from an application exception list.
    /// Never fall through to an empty exclusion and capture the effect itself.
    static func make(
        content: SCShareableContent, display: SCDisplay, outputWindowNumber: Int,
        includingOwnWindows: [SCWindow] = []
    ) throws -> (SCContentFilter, CaptureExclusion) {
        guard outputWindowNumber > 0,
            !includingOwnWindows.contains(where: { Int($0.windowID) == outputWindowNumber })
        else { throw CaptureIsolationError() }
        let filter: SCContentFilter
        let exclusion: CaptureExclusion
        if let output = content.windows.first(where: { Int($0.windowID) == outputWindowNumber }) {
            filter = SCContentFilter(display: display, excludingWindows: [output])
            exclusion = .window
        } else {
            // A non-shared panel can be absent from the shareable-window list.
            // Excluding its entire owning process is the conservative fallback.
            let process = ProcessInfo.processInfo.processIdentifier
            let applications = content.applications.filter { $0.processID == process }
            guard !applications.isEmpty,
                includingOwnWindows.allSatisfy({ $0.owningApplication?.processID == process })
            else { throw CaptureIsolationError() }
            filter = SCContentFilter(
                display: display, excludingApplications: applications, exceptingWindows: includingOwnWindows)
            exclusion = .application
        }
        if #available(macOS 14.2, *) { filter.includeMenuBar = true }
        return (filter, exclusion)
    }
}

private struct CaptureIsolationError: LocalizedError {
    var errorDescription: String? {
        "DuoLid couldn’t exclude its effect window from capture. Close and reopen the app to try again."
    }
}
