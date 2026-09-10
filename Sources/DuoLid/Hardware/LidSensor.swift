import DuoLidCore
import Foundation
import IOKit
import IOKit.hid

/// All HID access stays on this utility queue. No device is seized.
/// Input reports are event-driven; a low-rate feature-report watchdog covers
/// Macs whose driver exposes the angle but does not deliver input callbacks.
final class LidSensor: @unchecked Sendable {
    enum State: Equatable, Sendable {
        case searching, connected, unavailable
        case failed(String)
    }
    let samples = LatestLidSample()
    var onAngle: (@Sendable (Double) -> Void)?
    var onState: (@Sendable (State) -> Void)?
    private let queue = DispatchQueue(label: "app.duolid.sensor", qos: .utility)
    private var device: IOHIDDevice?
    private var timer: DispatchSourceTimer?
    private var lastInput = -Double.infinity
    private var lastValue: Double?
    private var failures = 0
    private var retryTicks = 0
    private var active = false
    private var fastPolling = false
    private var lastMotion = -Double.infinity
    private var effectStart = 62.0
    private var effectEnabled = true

    func start() { queue.async { [weak self] in self?.begin() } }
    func stop() { queue.async { [weak self] in self?.end() } }
    func stopAndWait() async {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                end()
                continuation.resume()
            }
        }
    }
    func configure(startAngle: Double, enabled: Bool) {
        queue.async { [weak self] in
            guard let self else { return }
            self.effectStart = startAngle
            self.effectEnabled = enabled
            if !enabled { self.setFastPolling(false) }
        }
    }

    private func begin() {
        guard !active else { return }
        active = true
        onState?(.searching)
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(80), leeway: .milliseconds(10))
        timer.setEventHandler { [weak self] in self?.watchdog() }
        self.timer = timer
        discover()
        timer.resume()
    }

    private func end() {
        active = false
        timer?.cancel()
        timer = nil
        disconnect()
        lastValue = nil
        samples.set(nil)
        fastPolling = false
    }

    private func disconnect() {
        if let device {
            IOHIDDeviceCancel(device)
            IOHIDDeviceClose(device, 0)
        }
        device = nil
        setFastPolling(false)
    }

    private func discover() {
        guard device == nil, let matching = IOServiceMatching("IOHIDDevice") else { return }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            onState?(.failed("The lid sensor could not be reached."))
            return
        }
        defer { IOObjectRelease(iterator) }
        var service = IOIteratorNext(iterator)
        while service != 0 {
            let current = service
            service = IOIteratorNext(iterator)
            defer { IOObjectRelease(current) }
            func value(_ key: String) -> Int? {
                (IORegistryEntryCreateCFProperty(current, key as CFString, nil, 0)?.takeRetainedValue() as? NSNumber)?
                    .intValue
            }
            guard value("PrimaryUsagePage") == 0x20, value("PrimaryUsage") == 0x8A,
                let candidate = IOHIDDeviceCreate(kCFAllocatorDefault, current),
                IOHIDDeviceOpen(candidate, 0) == kIOReturnSuccess
            else { continue }
            if service != 0 {
                IOObjectRelease(service)
                service = 0
            }
            device = candidate
            let context = Unmanaged.passUnretained(self).toOpaque()
            IOHIDDeviceRegisterInputValueCallback(
                candidate,
                { context, result, _, value in
                    guard let context, result == kIOReturnSuccess else { return }
                    let sensor = Unmanaged<LidSensor>.fromOpaque(context).takeUnretainedValue()
                    let element = IOHIDValueGetElement(value)
                    guard IOHIDElementGetUsagePage(element) == 0x20,
                        IOHIDElementGetUsage(element) == 0x047F
                    else { return }
                    let angle = Double(IOHIDValueGetIntegerValue(value))
                    guard (0...180).contains(angle) else { return }
                    sensor.lastInput = ProcessInfo.processInfo.systemUptime
                    sensor.receive(angle)
                }, context)
            IOHIDDeviceSetDispatchQueue(candidate, queue)
            IOHIDDeviceActivate(candidate)
            poll()
            return
        }
        onState?(.unavailable)
    }

    private func watchdog() {
        guard active else { return }
        guard device != nil else {
            retryTicks += 1
            if retryTicks >= 62 {
                retryTicks = 0
                discover()
            }
            return
        }
        if (ProcessInfo.processInfo.systemUptime - lastInput) > (fastPolling ? 0.032 : 0.24) { poll() }
    }

    private func poll() {
        guard let device else { return }
        var report = [UInt8](repeating: 0, count: 8)
        var length = report.count
        let result = IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 1, &report, &length)
        guard result == kIOReturnSuccess, let angle = LidMath.decode(report: Array(report.prefix(max(0, length))))
        else {
            failures += 1
            if failures >= 15 {
                disconnect()
                lastValue = nil
                samples.set(nil)
                onState?(.failed("The lid sensor stopped responding. Reconnecting…"))
            }
            return
        }
        receive(angle)
    }

    private func receive(_ angle: Double) {
        failures = 0
        if lastValue == nil { onState?(.connected) }
        let now = ProcessInfo.processInfo.systemUptime
        if let lastValue, abs(angle - lastValue) >= 0.5 { lastMotion = now }
        setFastPolling(effectEnabled && (angle < effectStart || now - lastMotion < 1))
        lastValue = angle
        samples.set(angle)
        onAngle?(angle)
    }

    private func setFastPolling(_ fast: Bool) {
        guard fast != fastPolling else { return }
        fastPolling = fast
        timer?.schedule(
            deadline: .now() + .milliseconds(fast ? 16 : 80),
            repeating: .milliseconds(fast ? 16 : 80), leeway: .milliseconds(fast ? 1 : 10))
    }
}

func isClamshellClosed() -> Bool {
    let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
    guard service != 0 else { return false }
    defer { IOObjectRelease(service) }
    return
        (IORegistryEntryCreateCFProperty(service, "AppleClamshellState" as CFString, nil, 0)?.takeRetainedValue()
        as? Bool) ?? false
}
