import AppKit
import DuoLidCore
import MetalKit

@MainActor
enum Diagnostics {
    static func baseReport(checkGraphics: Bool = true) -> CapabilityReport {
        var report = CapabilityReport()
        report.version =
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
        report.build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "development"
        report.system = ProcessInfo.processInfo.operatingSystemVersionString
        #if arch(arm64)
            report.architecture = "arm64"
        #else
            report.architecture = "x86_64"
        #endif
        var size = 0
        if sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 {
            var bytes = [UInt8](repeating: 0, count: size)
            if sysctlbyname("hw.model", &bytes, &size, nil, 0) == 0 {
                report.model = String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
            }
        }
        report.screenRecording = CGPreflightScreenCaptureAccess() ? .available : .permissionRequired
        report.builtInDisplayActive = DesktopEffect.builtInScreen != nil
        if checkGraphics {
            do {
                _ = try MetalRenderer(frames: CapturedFrame())
                report.graphics = .available
            } catch {
                report.graphics = .failed
                report.graphicsError = "initialization_failed"
            }
        }
        return report
    }

    static func run() {
        let collector = DiagnosticCollector(report: baseReport())
        let sensor = LidSensor()
        sensor.onAngle = { [collector] angle in Task { @MainActor in collector.report.lidAngle = angle } }
        sensor.onState = { [collector] state in
            Task { @MainActor in
                switch state {
                case .searching: collector.report.sensor = .checking
                case .connected: collector.report.sensor = .available
                case .unavailable: collector.report.sensor = .unavailable
                case .failed: collector.report.sensor = .failed
                }
            }
        }
        sensor.start()
        let deadline = Date().addingTimeInterval(1)
        while Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        sensor.stop()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(collector.report) {
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data("\n".utf8))
        }
    }
}

@MainActor
private final class DiagnosticCollector {
    var report: CapabilityReport
    init(report: CapabilityReport) { self.report = report }
}
