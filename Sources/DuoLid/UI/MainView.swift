import AppKit
import DuoLidCore
import SwiftUI

struct MainView: View {
    @ObservedObject var model: AppModel
    @AppStorage("DuoLid.appearance") private var appearance = "system"
    @State private var angleText = "62"
    @State private var angleValidation: String?
    @FocusState private var editingAngle: Bool

    var body: some View {
        VStack(spacing: 0) {
            if let message = model.message {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "info.circle").foregroundStyle(.secondary)
                    Text(message).textSelection(.enabled)
                    Spacer()
                    Button {
                        model.message = nil
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain).help("Dismiss message")
                }.font(.callout).padding(12).background(.quaternary.opacity(0.35))
                Divider()
            }
            HStack(spacing: 0) {
                PreviewWorkspace(model: model)
                    .frame(minWidth: 350, maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                ScrollView { inspector.padding(20) }.frame(width: 350)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .background(DuoTheme.surface.opacity(0.35))
            }
            footer
        }
        .frame(minWidth: 750, minHeight: 570)
        .background(DuoTheme.canvas)
        .sheet(isPresented: $model.showingPreferences) { PreferencesView(model: model, appearance: $appearance) }
        .onAppear {
            editingAngle = false
            angleText = String(Int(model.settings.clearAngle))
            applyAppearance()
        }
        .onChange(of: model.settings.clearAngle) { _, value in if !editingAngle { angleText = String(Int(value)) } }
        .onChange(of: editingAngle) { _, editing in if !editing { commitAngle() } }
        .onChange(of: appearance) { _, _ in applyAppearance() }
        .onChange(of: model.settings) { old, new in
            if old.style != new.style || old.intensity != new.intensity || old.perspective != new.perspective
                || old.shadow != new.shadow || old.glowEnabled != new.glowEnabled || old.glowPalette != new.glowPalette
                || old.glowIntensity != new.glowIntensity || old.glowSpread != new.glowSpread
                || old.glowCorners != new.glowCorners || old.edgeBleed != new.edgeBleed
            {
                model.revealPreviewEffect()
            }
        }
    }

    private var inspector: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Customize").font(.system(size: 17, weight: .semibold)).padding(.bottom, 2)
            VStack(alignment: .leading, spacing: 10) {
                settingToggle("Lid effect", isOn: $model.settings.blurEnabled)
                Picker("Effect style", selection: $model.settings.style) {
                    ForEach(EffectStyle.allCases, id: \.self) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented).labelsHidden()
                    .disabled(!model.settings.blurEnabled)
                TuningSlider("Blur", value: $model.settings.intensity, range: 0.15...1)
                    .disabled(!model.settings.blurEnabled)
            }
            Divider()
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text("Start angle").fontWeight(.semibold)
                    Spacer()
                    Button("Use 62°") {
                        model.useDefaultStartAngle()
                        angleText = "62"
                        angleValidation = nil
                    }
                    .buttonStyle(.link).font(.caption).disabled(model.settings.clearAngle == 62)
                }
                HStack(spacing: 9) {
                    Slider(value: $model.settings.clearAngle, in: 45...140, step: 1)
                        .accessibilityLabel("Effect start angle")
                    TextField("Degrees", text: $angleText)
                        .labelsHidden().textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing)
                        .frame(width: 44).focused($editingAngle)
                        .onSubmit { editingAngle = false }
                        .accessibilityLabel("Start angle in degrees")
                    Text("°").foregroundStyle(.secondary)
                    Stepper("Start angle", value: $model.settings.clearAngle, in: 45...140, step: 1).labelsHidden()
                }
                if let angleValidation { Text(angleValidation).font(.caption).foregroundStyle(.secondary) }
                Text("Begins below \(Int(model.settings.clearAngle))°. Clears completely above it.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                settingToggle("Colorful glow", isOn: $model.settings.glowEnabled)
                HStack(spacing: 7) {
                    ForEach(GlowPalette.allCases, id: \.self) { palette in
                        Button {
                            model.settings.glowPalette = palette
                        } label: {
                            VStack(spacing: 5) {
                                LinearGradient(colors: palette.swiftUIColors, startPoint: .leading, endPoint: .trailing)
                                    .frame(height: 18).clipShape(RoundedRectangle(cornerRadius: 4))
                                Text(palette.title).font(.system(size: 11))
                            }.padding(5).frame(maxWidth: .infinity)
                                .background(
                                    model.settings.glowPalette == palette ? Color.accentColor.opacity(0.13) : .clear,
                                    in: RoundedRectangle(cornerRadius: 7)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 7).stroke(
                                        model.settings.glowPalette == palette ? Color.accentColor : .clear,
                                        lineWidth: 1.5)
                                )
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                            .accessibilityLabel("\(palette.title) glow palette")
                            .accessibilityAddTraits(model.settings.glowPalette == palette ? .isSelected : [])
                    }
                }.disabled(!model.settings.glowEnabled).opacity(model.settings.glowEnabled ? 1 : 0.4)
                TuningSlider("Brightness", value: $model.settings.glowIntensity).disabled(!model.settings.glowEnabled)
                TuningSlider("Edge bleed", value: $model.settings.edgeBleed)
                    .help("How much soft light spills into the black background")
                Text(
                    model.settings.glowEnabled
                        ? "Edge bleed softens the fold against black."
                        : "Turn on colorful glow to edit its colors. Edge bleed works independently."
                )
                .font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                settingToggle("Opening sound", isOn: $model.settings.soundEnabled)
                HStack(spacing: 10) {
                    Picker("Sound", selection: $model.settings.tone) {
                        ForEach(LatchTone.allCases, id: \.self) { Text($0.title).tag($0) }
                    }.labelsHidden().accessibilityLabel("Opening sound tone")
                    Button {
                        model.playSound()
                    } label: {
                        Label("Listen", systemImage: "play.fill")
                    }
                    .help("Play opening sound (⇧⌘P)")
                }
                TuningSlider("Volume", value: $model.settings.volume)
            }
            Button {
                model.showingAdvanced.toggle()
            } label: {
                HStack {
                    Image(systemName: "slider.horizontal.3")
                    Text("More tuning…")
                    Spacer()
                    Text("Fold, shadow & glow spread").font(.caption).foregroundStyle(.secondary)
                }.padding(.vertical, 3).contentShape(Rectangle())
            }.buttonStyle(.bordered)
                .help("More tuning (⇧⌘T)")
                .popover(isPresented: $model.showingAdvanced, arrowEdge: .bottom) { AdvancedTuningView(model: model) }
        }.font(.system(size: 13))
    }

    private func settingToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title).fontWeight(.semibold)
            Spacer()
            Toggle(title, isOn: isOn).labelsHidden().toggleStyle(.switch).controlSize(.small).accessibilityLabel(title)
        }
    }

    private var footer: some View {
        HStack(spacing: 7) {
            Circle().fill(model.ready ? Color.green : Color.secondary).frame(width: 6, height: 6)
            if !model.settingsOnly && !model.hasScreenAccess && model.settings.blurEnabled {
                Text("Screen Recording access needed").foregroundStyle(.secondary)
                Button("Set up…") { model.showingPreferences = true }.buttonStyle(.link)
            } else {
                Text(model.statusTitle).foregroundStyle(.secondary)
            }
            Spacer()
            if let angle = model.angle {
                Image(systemName: "laptopcomputer").foregroundStyle(.secondary)
                Text("Your lid: \(Int(angle))°").monospacedDigit().foregroundStyle(.secondary)
            }
            Divider().frame(height: 11).padding(.horizontal, 5)
            Text("Changes save automatically").foregroundStyle(.tertiary)
        }.font(.system(size: 11)).padding(.horizontal, 24).padding(.vertical, 11)
            .overlay(alignment: .top) { Divider() }
    }

    private func commitAngle() {
        var input = angleText.trimmingCharacters(in: .whitespacesAndNewlines)
        if input.hasSuffix("°") { input.removeLast() }
        let scanner = Scanner(string: input)
        scanner.locale = Locale.current
        if let number = scanner.scanDouble(), number.isFinite, scanner.isAtEnd {
            let clamped = min(140, max(45, number.rounded()))
            model.settings.clearAngle = clamped
            angleValidation = number < 45 || number > 140 ? "Start angle must be between 45° and 140°." : nil
        } else {
            angleValidation = "Enter an angle from 45° to 140°. Your previous angle is kept."
        }
        angleText = String(Int(model.settings.clearAngle))
    }

    private func applyAppearance() {
        if model.documentationPreview != nil {
            NSApp.appearance = NSAppearance(named: .aqua)
            return
        }
        NSApp.appearance =
            appearance == "dark"
            ? NSAppearance(named: .darkAqua) : appearance == "light" ? NSAppearance(named: .aqua) : nil
    }
}

struct TuningSlider: View {
    let title: String
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    var display: String? = nil
    init(_ title: String, value: Binding<Double>, range: ClosedRange<Double> = 0...1, display: String? = nil) {
        self.title = title
        self._value = value
        self.range = range
        self.display = display
    }
    var body: some View {
        HStack(spacing: 10) {
            Text(title).frame(width: 70, alignment: .leading)
            Slider(value: $value, in: range).accessibilityLabel(title)
            Text(display ?? "\(Int(value * 100))%")
                .font(.system(size: 12).monospacedDigit()).foregroundStyle(.secondary).frame(
                    width: 39, alignment: .trailing)
        }
    }
}

private struct AdvancedTuningView: View {
    @ObservedObject var model: AppModel
    @State private var beforeReset: DuoSettings?
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("More tuning").font(.headline)
                Spacer()
                Button("Done") { model.showingAdvanced = false }.keyboardShortcut(.cancelAction)
            }
            VStack(alignment: .leading, spacing: 12) {
                Text("Motion & shading").fontWeight(.semibold)
                TuningSlider("Fold depth", value: $model.settings.perspective).disabled(model.settings.style == .frost)
                if model.settings.style == .frost {
                    Text("Frost keeps the screen flat. Choose Duo or Quiet to fold.").font(.caption).foregroundStyle(
                        .secondary)
                }
                TuningSlider("Shadow", value: $model.settings.shadow)
                TuningSlider(
                    "Smoothing", value: $model.settings.response, range: 0.025...0.18,
                    display: "\(Int(model.settings.response * 1_000)) ms")
                Picker("Frame rate", selection: $model.settings.frameRateMode) {
                    ForEach(FrameRateMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }.pickerStyle(.segmented)
                Text("Automatic follows your display, up to 120 fps, and adapts to graphics load.").font(.caption)
                    .foregroundStyle(.secondary)
            }
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                Text("Glow").fontWeight(.semibold)
                TuningSlider("Spread", value: $model.settings.glowSpread, range: 0.15...1)
                Picker("Corners", selection: $model.settings.glowCorners) {
                    ForEach(GlowCorners.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Text("A soft edge light remains when colorful glow is off.").font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            HStack {
                Button("Reset blur & glow") {
                    beforeReset = model.settings
                    model.resetAppearance()
                }
                Spacer()
                if let saved = beforeReset {
                    Button("Undo reset") {
                        model.restoreAppearance(from: saved)
                        beforeReset = nil
                    }
                }
            }
        }.font(.system(size: 13)).padding(20).frame(width: 360)
    }
}

private struct PreferencesView: View {
    @ObservedObject var model: AppModel
    @Binding var appearance: String
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Settings").font(.system(size: 17, weight: .semibold))
                Spacer()
                Button("Done") { model.showingPreferences = false }.keyboardShortcut(.defaultAction)
            }.padding(20)
            Divider()
            Form {
                Section("Access") {
                    LabeledContent("Lid sensor") {
                        Label(
                            model.sensorConnected
                                ? "Connected" : model.sensorState == .searching ? "Searching…" : "Preview only",
                            systemImage: model.sensorConnected ? "checkmark.circle.fill" : "exclamationmark.circle"
                        )
                        .foregroundStyle(model.sensorConnected ? Color.green : Color.secondary)
                    }
                    LabeledContent("Screen Recording") {
                        if model.hasScreenAccess {
                            Label("Allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        } else {
                            Button(model.checkingScreenAccess ? "Checking…" : "Allow access") {
                                model.requestScreenAccess()
                            }.disabled(model.checkingScreenAccess)
                        }
                    }
                    if !model.hasScreenAccess {
                        Text("Enable DuoLid in Screen Recording, then relaunch if macOS asks.").font(.caption)
                            .foregroundStyle(.secondary)
                        HStack {
                            Button("Check access") { model.requestScreenAccess() }
                            Button("Relaunch DuoLid") { model.relaunch() }
                        }
                    }
                    LabeledContent("Desktop capture", value: model.capturePhase.rawValue.capitalized)
                    LabeledContent(
                        "Graphics",
                        value: model.settingsOnly
                            ? "Stopped by launch option"
                            : model.graphicsFailed ? "Paused after an error" : "Ready to prepare")
                    if model.needsRecovery || model.capturePhase == .failed || model.graphicsFailed {
                        Button("Retry effect") { model.retryGraphics() }.disabled(model.settingsOnly)
                    }
                    if !model.sensorConnected {
                        Text(
                            "Automatic effects need a compatible lid-angle sensor. The sample preview works without one."
                        )
                        .font(.caption).foregroundStyle(.secondary)
                    }
                    Button("Copy diagnostics") { model.copyDiagnostics() }
                    Button("Open Screen Recording settings…") { model.openScreenSettings() }
                    Text("Screen frames stay on this Mac and are never saved.").font(.caption).foregroundStyle(
                        .secondary)
                }
                Section("General") {
                    Toggle(
                        "Launch at login",
                        isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
                    Picker("Appearance", selection: $appearance) {
                        Text("System").tag("system")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }.pickerStyle(.segmented)
                    Toggle("Respect Reduce Motion", isOn: $model.settings.respectReduceMotion)
                    Toggle("Use 30 fps in Low Power Mode", isOn: $model.settings.batterySaver)
                }
                UpdatePreferences(updater: model.updater)
                Section("Shortcuts") {
                    LabeledContent("Test on desktop", value: "⌘P")
                    LabeledContent("Animate preview", value: "⌥⌘P")
                    LabeledContent("Listen to opening sound", value: "⇧⌘P")
                    LabeledContent("Pause from anywhere", value: "⌃⌥⌘D")
                    LabeledContent("Pause a visible effect", value: "Esc")
                }
            }.formStyle(.grouped)
        }.frame(width: 530, height: 650)
    }
}

struct DuoToolbar: View {
    @ObservedObject var model: AppModel
    var body: some View {
        HStack(spacing: 20) {
            HStack(spacing: 8) {
                Text(model.settings.enabled ? "DuoLid is on" : "DuoLid is paused").font(.system(size: 12))
                Toggle("Enable DuoLid", isOn: $model.settings.enabled).labelsHidden().toggleStyle(.switch).controlSize(
                    .small
                )
                .accessibilityLabel("Enable DuoLid").help("Pause or resume DuoLid (⌃⌥⌘D)")
            }
            Button {
                model.showingPreferences = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "gearshape")
                    Text("Settings")
                }
            }.help("Settings (⌘,)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
        .fixedSize()
    }
}

private struct UpdatePreferences: View {
    @ObservedObject var updater: UpdaterController
    var body: some View {
        Section("Updates") {
            Toggle("Check for updates automatically", isOn: $updater.automaticallyChecks)
                .disabled(updater.configurationError != nil)
            Toggle("Include beta releases", isOn: $updater.includesBetas)
                .disabled(updater.configurationError != nil)
            HStack {
                Button("Check for Updates…") { updater.checkForUpdates() }.disabled(!updater.canCheck)
                Spacer()
                Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development")
                    .foregroundStyle(.secondary)
            }
            Text(
                updater.configurationError
                    ?? "Checks contact GitHub. Installation always asks you; screen content stays on your Mac."
            )
            .font(.caption).foregroundStyle(.secondary)
        }
    }
}
