import AppKit
import DuoLidCore
import ScreenCaptureKit
import ServiceManagement
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published var settings: DuoSettings { didSet { saveAndApply(previous: oldValue) } }
    @Published private(set) var angle: Double?
    @Published private(set) var sensorState: LidSensor.State = .searching
    @Published private var screenAccess = ScreenAccessState(preflightHint: false)
    var hasScreenAccess: Bool { screenAccess.hasAccess }
    @Published private(set) var checkingScreenAccess = false
    @Published private(set) var capturePhase: CapturePhase = .idle
    @Published private(set) var needsRecovery = false
    @Published private(set) var graphicsFailed = false
    private var lastPerformanceReport: PerformanceReport?
    @Published private(set) var effectActive = false
    @Published private(set) var launchAtLogin = false
    @Published var message: String?
    @Published var previewAngle = 112.0
    @Published private(set) var previewPlaying = false
    @Published var followLid = false
    @Published var showingPreferences = false
    @Published var showingAdvanced = false
    @Published private(set) var desktopPreview = false
    var stopPreviewRendering: (@MainActor @Sendable () async -> Void)?
    var showWindow: (() -> Void)?
    var statusDidChange: (() -> Void)?
    var effectDidChange: ((Bool) -> Void)?

    let settingsOnly: Bool
    let documentationPreview: NSImage?
    private var currentAngle: Double?
    private var lastReadoutTime = -Double.infinity
    private var interruptions = InterruptionState()
    let updater = UpdaterController()
    private let defaults: UserDefaults
    private let sensor = LidSensor()
    private let effect: DesktopEffect
    private let sound = LatchPlayer()
    private var latch = LatchDetector()
    private var observers: [NSObjectProtocol] = []
    private var permissionTimer: Timer?
    private var previewTask: Task<Void, Never>?
    private var suspended: Bool { interruptions.isSuspended }
    private var desktopPreviewAngle = 112.0
    private var started = false
    private var permissionTask: Task<Void, Never>?
    private var permissionRequested = false

    init(defaults: UserDefaults = .standard, settingsOnly: Bool = CommandLine.arguments.contains("--settings-only")) {
        let args = CommandLine.arguments
        if let index = args.firstIndex(of: "--documentation-preview"), args.indices.contains(index + 1) {
            documentationPreview = NSImage(contentsOfFile: args[index + 1])
        } else {
            documentationPreview = nil
        }
        self.settingsOnly = settingsOnly || args.contains("--documentation-preview")
        effect = DesktopEffect(liveAngle: sensor.samples, defaults: defaults, settingsOnly: self.settingsOnly)
        self.defaults = defaults
        needsRecovery = effect.failureLatched
        var loaded = DuoSettings.load(from: defaults.data(forKey: "DuoLid.settings.v1"))
        if documentationPreview != nil {
            loaded = DuoSettings()
            loaded.glowEnabled = true
            loaded.edgeBleed = 0.8
        }
        settings = loaded
        previewAngle = documentationPreview == nil ? 6 + (settings.clearAngle - 6) * 0.46 : 27
        screenAccess.observePreflight(CGPreflightScreenCaptureAccess())
        permissionRequested = defaults.bool(forKey: "DuoLid.permissionRequested")
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    var displayAngle: Double { followLid ? (angle ?? previewAngle) : previewAngle }
    var previewProgress: Double { LidMath.progress(angle: displayAngle, clearAngle: settings.clearAngle) }
    var sensorConnected: Bool { sensorState == .connected }
    var ready: Bool {
        !settingsOnly && DesktopEffect.builtInScreen != nil && !effect.failureLatched && sensorConnected
            && hasScreenAccess && settings.enabled
    }
    var statusTitle: String {
        if documentationPreview != nil { return "Documentation preview · synthetic screen content" }
        if settingsOnly { return "Settings only · effects stopped" }
        if effect.failureLatched { return "Effect paused after an interruption" }
        if !settings.enabled { return "Paused" }
        if !sensorConnected { return sensorState == .searching ? "Finding your lid…" : "Preview mode" }
        if DesktopEffect.builtInScreen == nil { return "Built-in display unavailable · preview only" }
        if !hasScreenAccess && settings.blurEnabled { return "One step to go" }
        if effectActive { return "Following your lid" }
        return "Ready when you are"
    }

    func start() {
        guard !started else { return }
        started = true
        if settingsOnly { updater.disableForReview() }
        if documentationPreview != nil {
            sensorState = .unavailable
            return
        }
        updater.prepareForInstallation = { [weak self] in await self?.shutdown() }
        if !settingsOnly { updater.start() }
        let samples = sensor.samples
        sensor.onAngle = { [weak self] _ in
            guard samples.scheduleDelivery() else { return }
            Task { @MainActor in if let angle = samples.takeForDelivery() { self?.receive(angle) } }
        }
        sensor.onState = { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                self.sensorState = state
                if state != .connected {
                    self.angle = nil
                    self.currentAngle = nil
                    self.effect.stop()
                }
                self.statusDidChange?()
            }
        }
        effect.onError = { [weak self] message in
            self?.message = message
            self?.needsRecovery = true
            self?.statusDidChange?()
        }
        if effect.failureLatched {
            message =
                "A previous graphics session did not finish safely. Automatic effects are paused. Open Settings to review and retry."
        }
        effect.onPermissionDenied = { [weak self] in
            self?.screenAccess.confirm(false)
            self?.statusDidChange?()
        }
        effect.onCaptureChanged = { [weak self] phase in self?.capturePhase = phase }
        effect.onGraphicsFailure = { [weak self] in self?.graphicsFailed = true }
        effect.onPerformanceReport = { [weak self] in self?.lastPerformanceReport = $0 }
        effect.onActiveChanged = { [weak self] active in
            self?.effectActive = active
            if active { self?.screenAccess.confirm(true) }
            self?.effectDidChange?(active)
        }
        sound.onError = { [weak self] in self?.message = $0 }
        sensor.configure(startAngle: settings.clearAngle, enabled: settings.enabled && settings.blurEnabled)
        sensor.start()
        observe(NSWorkspace.willSleepNotification) { [weak self] in self?.suspend(.sleeping) }
        observe(NSWorkspace.sessionDidResignActiveNotification) { [weak self] in self?.suspend(.inactiveSession) }
        observe(NSWorkspace.didWakeNotification) { [weak self] in self?.resume(.sleeping) }
        observe(NSWorkspace.sessionDidBecomeActiveNotification) { [weak self] in self?.resume(.inactiveSession) }
        observe(NSWorkspace.screensDidSleepNotification) { [weak self] in self?.suspend(.displaySleeping) }
        observe(NSWorkspace.screensDidWakeNotification) { [weak self] in self?.resume(.displaySleeping) }
        observers.append(
            NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.effect.stop()
                    self?.applyEffect()
                }
            })
        observers.append(
            NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.refreshPermissions()
                    if self?.permissionRequested == true && self?.hasScreenAccess == false {
                        self?.verifyScreenAccess(openSettingsOnFailure: false)
                    }
                }
            })
        observers.append(
            NotificationCenter.default.addObserver(
                forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.applyEffect() }
            })
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                if self?.hasScreenAccess == false { self?.refreshPermissions() }
            }
        }
        permissionTimer?.tolerance = 1
    }

    private func observe(_ name: Notification.Name, action: @escaping @MainActor @Sendable () -> Void) {
        observers.append(
            NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { action() }
            })
    }

    private func receive(_ newAngle: Double) {
        guard !suspended else { return }
        currentAngle = newAngle
        let now = ProcessInfo.processInfo.systemUptime
        if angle == nil || now - lastReadoutTime >= 0.1 {
            angle = newAngle
            lastReadoutTime = now
        }
        if !settingsOnly && settings.enabled && settings.soundEnabled && !desktopPreview {
            if latch.update(angle: newAngle, clearAngle: settings.clearAngle, at: ProcessInfo.processInfo.systemUptime)
            {
                sound.play(settings.tone, volume: settings.volume)
            }
        }
        applyEffect()
    }

    private func applyEffect() {
        guard let angle = desktopPreview ? Optional(desktopPreviewAngle) : currentAngle else {
            effect.stop()
            return
        }
        effect.update(
            angle: angle, settings: settings,
            allowed: !settingsOnly && !suspended && hasScreenAccess && (sensorConnected || desktopPreview),
            useLiveAngle: !desktopPreview)
    }

    private func saveAndApply(previous: DuoSettings) {
        if let data = try? JSONEncoder().encode(settings) { defaults.set(data, forKey: "DuoLid.settings.v1") }
        if !previous.enabled && settings.enabled, effect.acknowledgeFailure() {
            needsRecovery = false
            graphicsFailed = false
        }
        if previous.enabled != settings.enabled || previous.soundEnabled != settings.soundEnabled
            || previous.clearAngle != settings.clearAngle
        {
            latch.reset()
        }
        if previous.enabled != settings.enabled || previous.blurEnabled != settings.blurEnabled
            || previous.clearAngle != settings.clearAngle
        {
            sensor.configure(startAngle: settings.clearAngle, enabled: settings.enabled && settings.blurEnabled)
        }
        applyEffect()
        statusDidChange?()
    }

    func refreshPermissions() {
        let access = CGPreflightScreenCaptureAccess()
        let previous = hasScreenAccess
        screenAccess.observePreflight(access)
        if hasScreenAccess != previous {
            applyEffect()
            statusDidChange?()
        }
        let login = SMAppService.mainApp.status == .enabled
        if login != launchAtLogin { launchAtLogin = login }
    }

    func requestScreenAccess() {
        permissionRequested = true
        defaults.set(true, forKey: "DuoLid.permissionRequested")
        verifyScreenAccess(openSettingsOnFailure: true)
    }

    private func verifyScreenAccess(openSettingsOnFailure: Bool) {
        guard !checkingScreenAccess else { return }
        checkingScreenAccess = true
        permissionTask = Task { [weak self] in
            guard let self else { return }
            defer {
                self.checkingScreenAccess = false
                self.permissionTask = nil
            }
            do {
                _ = try await CaptureContent.fetch()
                guard !Task.isCancelled else { return }
                self.screenAccess.confirm(true)
                self.message = nil
                self.applyEffect()
                self.statusDidChange?()
            } catch {
                guard !Task.isCancelled else { return }
                let denied =
                    (error as NSError).domain == SCStreamErrorDomain
                    && (error as NSError).code == SCStreamError.Code.userDeclined.rawValue
                if denied {
                    self.screenAccess.confirm(false)
                    self.effect.stop()
                } else {
                    self.message = "Screen access could not be checked: \(error.localizedDescription)"
                }
                if denied && openSettingsOnFailure {
                    self.message =
                        "macOS hasn’t connected screen access yet. Enable DuoLid in Screen Recording, then use Relaunch DuoLid in Settings."
                    self.openScreenSettings()
                }
            }
        }
    }

    func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.activates = true
        Task {
            await shutdown()
            do {
                _ = try await NSWorkspace.shared.openApplication(
                    at: Bundle.main.bundleURL, configuration: configuration)
                NSApp.terminate(nil)
            } catch {
                message = "DuoLid couldn’t relaunch: \(error.localizedDescription)"
                interruptions.end(.shutdown)
                started = false
                start()
            }
        }
    }

    func openScreenSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            launchAtLogin = SMAppService.mainApp.status == .enabled
            if SMAppService.mainApp.status == .requiresApproval {
                message = "Allow DuoLid in System Settings → General → Login Items to finish setup."
            }
        } catch { message = "Launch at login could not be changed: \(error.localizedDescription)" }
    }

    func useDefaultStartAngle() { settings.clearAngle = DuoSettings().clearAngle }

    func playSound() { sound.play(settings.tone, volume: settings.volume) }

    func inspectFold() {
        stopPreview()
        followLid = false
        previewAngle = 6 + (settings.clearAngle - 6) * 0.46
    }

    /// Editing should show the effect, even if the preview was left fully open.
    func revealPreviewEffect() {
        guard !previewPlaying, !followLid, previewProgress < 0.15 else { return }
        previewAngle = 6 + (settings.clearAngle - 6) * 0.46
    }

    func copyDiagnostics() {
        var report = Diagnostics.baseReport(checkGraphics: false)
        report.sensor = sensorConnected ? .available : sensorState == .searching ? .checking : .unavailable
        report.lidAngle = angle
        report.screenRecording = hasScreenAccess ? .available : .permissionRequired
        report.capture = capturePhase
        report.graphics = graphicsFailed ? .failed : .checking
        struct SupportReport: Encodable {
            let capability: CapabilityReport
            let performance: PerformanceReport?
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(SupportReport(capability: report, performance: lastPerformanceReport)),
            let text = String(data: data, encoding: .utf8)
        {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            message = "Technical diagnostics copied. They contain no screenshots, window titles, or account details."
        }
    }

    func retryGraphics() {
        guard !settingsOnly else { return }
        guard effect.acknowledgeFailure() else { return }
        needsRecovery = false
        graphicsFailed = false
        message = nil
        applyEffect()
        statusDidChange?()
    }

    func playPreview(onDesktop: Bool = false) {
        guard !settingsOnly else {
            message = "Previews are unavailable while graphics are stopped."
            return
        }
        if previewPlaying {
            stopPreview()
            return
        }
        guard !onDesktop || (settings.enabled && settings.blurEnabled) else { return }
        guard !onDesktop || hasScreenAccess else {
            requestScreenAccess()
            return
        }
        guard !onDesktop || DesktopEffect.builtInScreen != nil else {
            message = "Open the MacBook’s built-in display to try the desktop effect."
            return
        }
        let heldAngle = previewAngle
        let wasFollowing = followLid
        followLid = false
        desktopPreview = onDesktop
        previewPlaying = true
        let openAngle = max(112, settings.clearAngle + 8)
        desktopPreviewAngle = openAngle
        previewTask = Task { [weak self] in
            guard let self else { return }
            let start = ProcessInfo.processInfo.systemUptime
            var previewLatch = LatchDetector()
            while !Task.isCancelled {
                let t = ProcessInfo.processInfo.systemUptime - start
                if t >= 3.7 { break }
                let fraction: Double
                if t < 1.6 {
                    fraction = self.ease(t / 1.6)
                } else if t < 2.0 {
                    fraction = 1
                } else {
                    fraction = 1 - self.ease((t - 2.0) / 1.7)
                }
                let animatedAngle = openAngle - fraction * (openAngle - 16)
                self.desktopPreviewAngle = animatedAngle
                // A desktop preview already animates the real display. Rebuilding the
                // SwiftUI illustration simultaneously needlessly competes for its GPU.
                if !self.desktopPreview { self.previewAngle = animatedAngle }
                if previewLatch.update(
                    angle: animatedAngle, clearAngle: self.settings.clearAngle, at: ProcessInfo.processInfo.systemUptime
                ), self.settings.soundEnabled {
                    self.playSound()
                }
                if self.desktopPreview { self.applyEffect() }
                try? await Task.sleep(for: .milliseconds(16))
            }
            guard !Task.isCancelled else { return }
            self.previewAngle = heldAngle
            self.followLid = wasFollowing
            self.stopPreview()
        }
    }

    private func ease(_ x: Double) -> Double {
        let x = min(1, max(0, x))
        return x * x * (3 - 2 * x)
    }

    func stopPreview() {
        previewTask?.cancel()
        previewTask = nil
        previewPlaying = false
        let wasDesktop = desktopPreview
        desktopPreview = false
        if wasDesktop {
            effect.stop()
            applyEffect()
        }
    }

    func emergencyPause() {
        settings.enabled = false
        stopPreview()
        effect.stop()
        sound.stop()
    }

    func resetAppearance() { restoreAppearance(from: DuoSettings()) }

    func restoreAppearance(from appearance: DuoSettings) {
        var updated = settings
        updated.style = appearance.style
        updated.intensity = appearance.intensity
        updated.perspective = appearance.perspective
        updated.shadow = appearance.shadow
        updated.response = appearance.response
        updated.glowEnabled = appearance.glowEnabled
        updated.glowPalette = appearance.glowPalette
        updated.glowIntensity = appearance.glowIntensity
        updated.glowSpread = appearance.glowSpread
        updated.edgeBleed = appearance.edgeBleed
        updated.glowCorners = appearance.glowCorners
        settings = updated
    }

    private func suspend(_ reason: InterruptionState.Reason) {
        let wasSuspended = suspended
        interruptions.begin(reason)
        guard !wasSuspended else { return }
        if isClamshellClosed() || (angle ?? 180) < 25 { latch.lidDidClose() } else { latch.reset() }
        stopPreview()
        effect.stop()
        sensor.stop()
        sound.stop()
    }

    private func resume(_ reason: InterruptionState.Reason) {
        let wasSuspended = suspended
        interruptions.end(reason)
        guard wasSuspended && !suspended else { return }
        refreshPermissions()
        sensor.start()
    }

    func shutdown() async {
        interruptions.begin(.shutdown)
        stopPreview()
        effect.stop()
        sensor.stop()
        sound.stop()
        permissionTimer?.invalidate()
        permissionTimer = nil
        permissionTask?.cancel()
        permissionTask = nil
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observers.removeAll()
        await stopPreviewRendering?()
        await effect.stopAndWait()
        await sensor.stopAndWait()
    }
}
