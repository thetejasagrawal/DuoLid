import AppKit
import Carbon
import DuoLidCore
import MetalKit
import SwiftUI

@main
enum DuoLidApp {
    @MainActor
    static func main() {
        if CommandLine.arguments.contains("--export-demo") {
            _ = NSApplication.shared
            do { try DemoExport.run() } catch {
                fputs("Demo export failed: \(error.localizedDescription)\n", stderr)
                exit(1)
            }
            return
        }
        if CommandLine.arguments.contains("--presentation-check") {
            do { try PresentationVerification.run() } catch {
                fputs("Presentation check failed: \(error.localizedDescription)\n", stderr)
                exit(1)
            }
            return
        }
        if CommandLine.arguments.contains("--render-check") {
            _ = NSApplication.shared
            do { try RenderVerification.run() } catch {
                fputs("Render verification failed: \(error.localizedDescription)\n", stderr)
                exit(1)
            }
            return
        }
        if CommandLine.arguments.contains("--diagnose") {
            _ = NSApplication.shared
            Diagnostics.run()
            return
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSToolbarDelegate, NSMenuItemValidation {
    private let model = AppModel()
    private var window: NSWindow?
    private var statusItem: NSStatusItem?
    private var pauseItem: NSMenuItem?
    private var glowItem: NSMenuItem?
    private var hotKeys: HotKeys?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        makeMenu()
        makeStatusItem()
        model.showWindow = { [weak self] in self?.showSettings() }
        model.statusDidChange = { [weak self] in self?.refreshStatus() }
        hotKeys = HotKeys { [weak self] in self?.model.emergencyPause() }
        hotKeys?.onError = { [weak self] message in self?.model.message = message }
        model.effectDidChange = { [weak self] active in self?.hotKeys?.setEscapeEnabled(active) }
        model.start()
        refreshStatus()
        let launchedAtLogin =
            NSAppleEventManager.shared().currentAppleEvent?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue
            == keyAELaunchedAsLogInItem
        if !launchedAtLogin { showSettings() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        hotKeys?.stop()
        Task {
            await model.shutdown()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    private func makeMenu() {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "DuoLid")
        appMenu.addItem(withTitle: "About DuoLid", action: #selector(showAbout), keyEquivalent: "")
        let update = appMenu.addItem(
            withTitle: "Check for Updates…", action: #selector(checkUpdates), keyEquivalent: "")
        update.target = self
        appMenu.addItem(.separator())
        let preferences = appMenu.addItem(
            withTitle: "Settings…", action: #selector(openPreferences), keyEquivalent: ",")
        preferences.target = self
        let preview = appMenu.addItem(
            withTitle: "Preview on Desktop", action: #selector(previewDesktop), keyEquivalent: "p")
        preview.target = self
        let play = appMenu.addItem(
            withTitle: "Play Opening Sound", action: #selector(playOpeningSound), keyEquivalent: "p")
        play.keyEquivalentModifierMask = [.command, .shift]
        play.target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide DuoLid", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit DuoLid", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        menu.addItem(appItem)
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        menu.addItem(editItem)
        let viewItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")
        let animate = viewMenu.addItem(
            withTitle: "Animate Preview", action: #selector(previewEffect), keyEquivalent: "p")
        animate.keyEquivalentModifierMask = [.command, .option]
        animate.target = self
        let tuning = viewMenu.addItem(withTitle: "More Tuning…", action: #selector(showAdvanced), keyEquivalent: "t")
        tuning.keyEquivalentModifierMask = [.command, .shift]
        tuning.target = self
        viewItem.submenu = viewMenu
        menu.addItem(viewItem)
        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(
            withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowItem.submenu = windowMenu
        menu.addItem(windowItem)
        NSApp.mainMenu = menu
    }

    private func makeStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "macbook", accessibilityDescription: "DuoLid")
        item.button?.image?.isTemplate = true
        let menu = NSMenu()
        let title = NSMenuItem(title: "DuoLid", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())
        let show = menu.addItem(withTitle: "Open DuoLid…", action: #selector(openSettings), keyEquivalent: "")
        show.target = self
        pauseItem = menu.addItem(withTitle: "Pause DuoLid", action: #selector(togglePause), keyEquivalent: "d")
        pauseItem?.keyEquivalentModifierMask = [.control, .option, .command]
        pauseItem?.target = self
        glowItem = menu.addItem(withTitle: "Corner glow", action: #selector(toggleGlow), keyEquivalent: "")
        glowItem?.target = self
        let preview = menu.addItem(withTitle: "Preview effect…", action: #selector(previewEffect), keyEquivalent: "")
        preview.target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit DuoLid", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    private func refreshStatus() {
        pauseItem?.title = model.settings.enabled ? "Pause DuoLid" : "Resume DuoLid"
        glowItem?.state = model.settings.glowEnabled ? .on : .off
        statusItem?.button?.appearsDisabled = !model.settings.enabled
        statusItem?.button?.toolTip = "DuoLid · \(model.statusTitle)"
    }

    func showSettings() {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered,
                defer: false)
            window.title = "DuoLid"
            window.titleVisibility = .visible
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = false
            window.isReleasedWhenClosed = false
            window.backgroundColor = .windowBackgroundColor
            window.minSize = NSSize(width: 800, height: 660)
            let toolbar = NSToolbar(identifier: "DuoLid.Toolbar")
            toolbar.delegate = self
            toolbar.displayMode = .iconOnly
            toolbar.allowsUserCustomization = false
            window.toolbar = toolbar
            window.toolbarStyle = .unified
            window.contentView = NSHostingView(rootView: MainView(model: model))
            window.delegate = self
            window.setFrameAutosaveName("DuoLid.TuningWorkspaceWindow")
            window.center()
            self.window = window
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(nil)
    }

    func windowWillClose(_ notification: Notification) {
        model.stopPreview()
        model.followLid = false
        model.showingAdvanced = false
        model.showingPreferences = false
        NSApp.setActivationPolicy(.accessory)
    }

    @objc private func checkUpdates() { model.updater.checkForUpdates() }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(checkUpdates) { return model.updater.canCheck }
        if menuItem.action == #selector(previewDesktop) || menuItem.action == #selector(previewEffect) {
            return model.previewRenderingAllowed
        }
        return true
    }

    @objc private func openSettings() { showSettings() }
    @objc private func openPreferences() {
        showSettings()
        model.showingPreferences = true
    }
    @objc private func previewDesktop() { model.playPreview(onDesktop: true) }
    @objc private func playOpeningSound() { model.playSound() }
    @objc private func showAdvanced() {
        showSettings()
        model.showingAdvanced = true
    }
    @objc private func togglePause() { model.settings.enabled.toggle() }
    @objc private func toggleGlow() { model.settings.glowEnabled.toggle() }
    @objc private func previewEffect() {
        showSettings()
        model.playPreview()
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, .init("DuoLid.Controls")]
    }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarAllowedItemIdentifiers(toolbar)
    }
    func toolbar(
        _ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard identifier.rawValue == "DuoLid.Controls" else { return nil }
        let item = NSToolbarItem(itemIdentifier: identifier)
        let controls = NSHostingView(rootView: DuoToolbar(model: model))
        controls.sizingOptions = [.intrinsicContentSize]
        controls.setContentHuggingPriority(.required, for: .horizontal)
        controls.setContentCompressionResistancePriority(.required, for: .horizontal)
        controls.setFrameSize(controls.fittingSize)
        item.view = controls
        item.label = "DuoLid controls"
        return item
    }
    @objc private func showAbout() {
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "DuoLid",
            .applicationVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
                ?? "Development",
            .credits: NSAttributedString(
                string:
                    "A softer landing for your MacBook.\nNative blur, optional corner glow, and an original magnetic click."
            ),
        ])
    }
}

@MainActor
private final class HotKeys {
    private var handler: EventHandlerRef?
    private var pauseKey: EventHotKeyRef?
    private var escapeKey: EventHotKeyRef?
    private let action: () -> Void
    var onError: ((String) -> Void)?

    init(action: @escaping () -> Void) {
        self.action = action
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, context in
                guard let context else { return noErr }
                MainActor.assumeIsolated { Unmanaged<HotKeys>.fromOpaque(context).takeUnretainedValue().action() }
                return noErr
            }, 1, &type, context, &handler)
        // Avoid macOS's default Option-Command-D Dock shortcut.
        RegisterEventHotKey(
            UInt32(kVK_ANSI_D), UInt32(controlKey | optionKey | cmdKey), EventHotKeyID(signature: 0x4455_4F4C, id: 1),
            GetApplicationEventTarget(), 0, &pauseKey)
    }

    func setEscapeEnabled(_ enabled: Bool) {
        if enabled && escapeKey == nil {
            let result = RegisterEventHotKey(
                UInt32(kVK_Escape), 0, EventHotKeyID(signature: 0x4455_4F4C, id: 2), GetApplicationEventTarget(), 0,
                &escapeKey)
            if result != noErr {
                onError?("Esc is reserved by another app. Pause DuoLid from the menu bar or with ⌃⌥⌘D.")
            }
        } else if !enabled, let escapeKey {
            UnregisterEventHotKey(escapeKey)
            self.escapeKey = nil
        }
    }

    func stop() {
        if let pauseKey { UnregisterEventHotKey(pauseKey) }
        if let escapeKey { UnregisterEventHotKey(escapeKey) }
        if let handler { RemoveEventHandler(handler) }
        pauseKey = nil
        escapeKey = nil
        handler = nil
    }
}
