import AppKit
import Combine
import Sparkle
import DuoLidCore

@MainActor
final class UpdaterController: NSObject, ObservableObject, SPUUpdaterDelegate {
    @Published private(set) var canCheck = false
    @Published private(set) var configurationError: String?
    @Published var automaticallyChecks = false {
        didSet {
            if started && native.updater.automaticallyChecksForUpdates != automaticallyChecks {
                native.updater.automaticallyChecksForUpdates = automaticallyChecks
            }
        }
    }
    @Published var includesBetas: Bool {
        didSet { defaults.set(includesBetas, forKey: "DuoLid.includeBetaUpdates") }
    }
    var prepareForInstallation: (@MainActor @Sendable () async -> Void)?
    private let defaults: UserDefaults
    private var started = false
    private var observations: [NSKeyValueObservation] = []
    private lazy var native = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
        let preference = defaults.object(forKey: "DuoLid.includeBetaUpdates") as? Bool
        includesBetas = UpdatePolicy.allowedChannels(version: version, betaPreference: preference).contains("beta")
        super.init()
    }

    func start() {
        guard !started else { return }
        guard Bundle.main.bundleIdentifier == "app.duolid.DuoLid",
              Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String == UpdatePolicy.feedURL,
              UpdatePolicy.validPublicKey(Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String),
              Bundle.main.object(forInfoDictionaryKey: "SURequireSignedFeed") as? Bool == true,
              Bundle.main.object(forInfoDictionaryKey: "SUSignedFeedFailureExpirationInterval") as? Int == 0,
              Bundle.main.object(forInfoDictionaryKey: "SUVerifyUpdateBeforeExtraction") as? Bool == true else {
            configurationError = "Updates are available in signed release builds."
            return
        }
        do {
            try native.updater.start()
            started = true
            automaticallyChecks = native.updater.automaticallyChecksForUpdates
            observations = [
                native.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] _, change in
                    let value = change.newValue ?? false
                    Task { @MainActor in self?.canCheck = value }
                },
                native.updater.observe(\.automaticallyChecksForUpdates, options: [.new]) { [weak self] _, change in
                    let value = change.newValue ?? false
                    Task { @MainActor in self?.automaticallyChecks = value }
                }
            ]
        } catch { configurationError = error.localizedDescription }
    }

    func disableForReview() {
        configurationError = "Update checks are unavailable while DuoLid is running in review mode."
    }

    @objc func checkForUpdates(_ sender: Any? = nil) {
        guard canCheck else { return }
        native.checkForUpdates(sender)
    }

    func allowedChannels(for updater: SPUUpdater) -> Set<String> { includesBetas ? ["beta"] : [] }

    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem,
                 untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        let continuation = InstallationContinuation(installHandler)
        Task {
            await prepareForInstallation?()
            continuation.resume()
        }
        return true
    }
}

/// Sparkle invokes its delegate on the main actor. Keep its unannotated ObjC
/// completion there while capture and the rendering owner finish asynchronously.
@MainActor
private final class InstallationContinuation {
    private let handler: () -> Void
    init(_ handler: @escaping () -> Void) { self.handler = handler }
    func resume() { handler() }
}
