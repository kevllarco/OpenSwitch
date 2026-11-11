#if os(macOS)
import AppKit
import AutomationSchema
import DisplayDomain
import OpenDisplayDesignSystem
import SwiftUI
import TopologyCore

/// The per-display detail pane (Settings → Displays). This is where everything that used to crowd the
/// menu-bar card now lives: resolution & refresh, appearance (colour), hardware controls,
/// input, "use as", identity, and read-only info — grouped into System-Settings-style cards. The menu
/// bar deep-links here via "Display settings…". See `Docs/InterfaceRedesign.md`.
struct DisplayDetailView: View {
    @EnvironmentObject private var model: AppModel
    let display: DisplayObservation

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let pending = model.pendingRevert {
                    // Timed auto-revert prompt for a change made here in Settings (Issue 6).
                    VStack(alignment: .leading, spacing: 6) {
                        ODInlineBanner(tone: .orange, systemImage: "clock.arrow.circlepath",
                                       title: "Keep these display settings?",
                                       message: "\(pending.message). Reverting in \(pending.secondsRemaining)s…")
                        HStack(spacing: 8) {
                            Button("Keep") { model.confirmArrangementChange() }
                                .keyboardShortcut(.defaultAction)
                            Button("Revert now") { Task { await model.revertArrangementChange() } }
                            Spacer()
                        }
                    }
                }
                DisplayKeyAndBrightnessOptions()
                ResolutionCard(display: display)
                AppearanceCard(display: display)
                if display.displayClass != .builtIn { ControlsCard(display: display) }
                DimmingCard(display: display)
                IdentityCard(display: display)
                InformationCard(display: display)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .task(id: display.recordID) {
            // Opening the detail pane is a deliberate act — if this display currently has NO working
            // hardware control, retry even negatively-cached DDC features so a monitor that just
            // recovered (power-cycle, input switch) shows its controls now. Healthy displays keep
            // their probe cache, so reopening the pane stays fast.
            model.retryDDCDiscoveryIfDead(for: display)
            await model.refreshBrightness(for: display)
            await model.refreshColorProfile(for: display)
            if display.displayClass != .builtIn {
                await model.refreshHardwareControls(for: display)
                await model.refreshColorPreset(for: display)
                await model.refreshInputSource(for: display)
            }
        }
    }
}

/// The two display automations retained in OpenSwitch settings.
private struct DisplayKeyAndBrightnessOptions: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ODCard(title: "Display behavior", padded: true) {
            VStack(alignment: .leading, spacing: 12) {
                #if !PUBLIC_API_ONLY
                HStack {
                    Text("Match external brightness to the built-in display")
                    Spacer(minLength: 12)
                    Toggle("Match external brightness to the built-in display", isOn: Binding(
                        get: { model.settings.adaptiveBrightnessSyncEnabled },
                        set: { model.setAdaptiveBrightnessSyncEnabled($0) }))
                        .labelsHidden().toggleStyle(.switch)
                }
                #endif
                HStack {
                    Text("Use keyboard brightness and volume keys")
                    Spacer(minLength: 12)
                    Toggle("Use keyboard brightness and volume keys", isOn: Binding(
                        get: { model.settings.mediaKeyInterceptionEnabled },
                        set: { model.setMediaKeyInterceptionEnabled($0) }))
                        .labelsHidden().toggleStyle(.switch)
                }
                HStack {
                    Text("Keep displays awake while an external display is connected")
                    Spacer(minLength: 12)
                    Toggle("Keep displays awake while an external display is connected", isOn: Binding(
                        get: { model.settings.preventDisplaySleepWithExternal },
                        set: { model.setPreventDisplaySleepWithExternal($0) }))
                        .labelsHidden().toggleStyle(.switch)
                }
                HStack {
                    Text("Notify when displays connect or disconnect")
                    Spacer(minLength: 12)
                    Toggle("Notify when displays connect or disconnect", isOn: Binding(
                        get: { model.settings.displayNotificationsEnabled },
                        set: { model.setDisplayNotificationsEnabled($0) }))
                        .labelsHidden().toggleStyle(.switch)
                }
                if model.settings.mediaKeyInterceptionEnabled {
                    Picker("Brightness keys control", selection: Binding(
                        get: { model.settings.mediaKeyTargetMode },
                        set: { model.setMediaKeyTargetMode($0) })) {
                        Text("Display under the pointer").tag(MediaKeyTargetMode.underCursor)
                        Text("Main display").tag(MediaKeyTargetMode.mainDisplay)
                        Text("Built-in display").tag(MediaKeyTargetMode.builtInAlways)
                    }
                    if !MediaKeyTap.isAccessibilityTrusted {
                        Text("Allow Accessibility access to use the keyboard keys.")
                            .appBodyFont().foregroundStyle(.secondary)
                        Button("Open Accessibility Settings…") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Resolution

private struct ResolutionCard: View {
    @EnvironmentObject private var model: AppModel
    let display: DisplayObservation
    /// Full mode list, enumerated once per display (off the per-render path) and filtered locally for
    /// the resolution list, refresh rates, and HiDPI toggle — avoids three CGDisplayCopyAllDisplayModes
    /// enumerations on every body evaluation. Filters use the *current* display.mode, so they stay
    /// correct across resolution switches without re-enumerating.
    @State private var allModes: [DisplayMode] = []
    /// One area-sorted choice per point-size (HiDPI preferred, then highest refresh).
    private var resolutions: [DisplayMode] { ResolutionStops.areaSorted(from: allModes) }

    /// Refresh rates at the current resolution (same point-size + HiDPI), descending.
    private var rates: [Double] {
        guard let current = display.mode else { return [] }
        let hz = allModes
            .filter { $0.pointWidth == current.pointWidth && $0.pointHeight == current.pointHeight && $0.isHiDPI == current.isHiDPI }
            .map { ($0.refreshHz * 10).rounded() / 10 }
        return Array(Set(hz)).sorted(by: >)
    }

    /// True when the current resolution offers both a HiDPI and a non-HiDPI variant.
    private var hiDPIAvailable: Bool {
        guard let current = display.mode else { return false }
        let here = allModes.filter { $0.pointWidth == current.pointWidth && $0.pointHeight == current.pointHeight }
        return here.contains(where: { $0.isHiDPI }) && here.contains(where: { !$0.isHiDPI })
    }

    var body: some View {
        ODCard(title: "Resolution",
               footnote: "Scaled resolutions use HiDPI (Retina) rendering for crisper text.") {
            ODRow("Resolution") {
                if resolutions.count > 1 {
                    Picker("Resolution", selection: Binding(
                        get: { display.mode.map(resolutionKey) ?? "" },
                        set: { selected in
                            guard let mode = resolutions.first(where: { resolutionKey($0) == selected }),
                                  !isCurrentResolution(mode) else { return }
                            Task { await model.setMode(mode, for: display) }
                        })) {
                        if display.mode == nil { Text("—").tag("") }
                        ForEach(resolutions, id: \.self) { mode in
                            Text("\(mode.pointWidth) × \(mode.pointHeight)").tag(resolutionKey(mode))
                        }
                    }
                    .labelsHidden().pickerStyle(.menu).fixedSize().disabled(model.busy)
                } else {
                    // Single-mode display: no dead control, just the current resolution.
                    Text(display.mode.map { "\($0.pointWidth) × \($0.pointHeight)" } ?? "—")
                        .appBodyFont().foregroundStyle(.secondary)
                }
            }
            if rates.count > 1, let mode = display.mode {
                ODDivider()
                ODRow("Refresh rate") {
                Picker("Refresh rate", selection: Binding(
                    get: { rates.first(where: { abs($0 - mode.refreshHz) < 0.11 }) ?? mode.refreshHz },
                    set: { newValue, _ in Task { await model.setRefresh(newValue, for: display) } })) {
                    ForEach(rates, id: \.self) { hz in
                        Text("\(Int(hz.rounded())) Hz").tag(hz)
                        }
                    }
                .labelsHidden().pickerStyle(.menu).fixedSize()
                }
            }
            if hiDPIAvailable, let mode = display.mode {
                ODDivider()
                ODRow("Retina (HiDPI)") {
                    Toggle("", isOn: Binding(get: { mode.isHiDPI },
                                             set: { on in Task { await model.setHiDPI(on, for: display) } }))
                        .labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
            }
        }
        .task(id: display.recordID) {
            allModes = model.allModes(for: display)
        }
    }

    private func resolutionKey(_ mode: DisplayMode) -> String {
        "\(mode.pointWidth)x\(mode.pointHeight)"
    }

    private func isCurrentResolution(_ mode: DisplayMode) -> Bool {
        guard let current = display.mode else { return false }
        return current.pointWidth == mode.pointWidth && current.pointHeight == mode.pointHeight
    }
}

// MARK: - Appearance

private struct AppearanceCard: View {
    @EnvironmentObject private var model: AppModel
    let display: DisplayObservation
    @State private var detectingModes = false
    /// Set when an explicit "Detect…" came back empty; cleared after a few seconds so a transient
    /// failure doesn't sit on the card as if it were a permanent property of the monitor.
    @State private var detectFoundNothing = false

    /// Displayed kelvin for the temperature slider (absent cache = neutral).
    private var temperature: Float {
        model.colorTemperature[display.recordID] ?? ColorTemperatureCurve.neutralKelvin
    }

    var body: some View {
        ODCard(title: "Appearance") {
            ODRow("Colour temperature") {
                HStack(spacing: 8) {
                    Image(systemName: "thermometer.sun").font(.body).foregroundStyle(.orange)
                    Slider(value: Binding(get: { Double(temperature) },
                                          set: { model.setColorTemperature(Float($0), for: display) }),
                           in: Double(ColorTemperatureCurve.minKelvin)...Double(ColorTemperatureCurve.maxKelvin))
                        .frame(width: 140)
                    Image(systemName: "thermometer.snowflake").font(.body).foregroundStyle(.cyan)
                    Text(model.colorTemperature[display.recordID] == nil
                         ? "Native" : "\(Int(temperature)) K")
                        .appBodyFont().monospacedDigit().foregroundStyle(.secondary)
                        .fixedSize(horizontal: true, vertical: false)
                        .frame(minWidth: 76, alignment: .trailing)
                }
            }
            if display.displayClass != .builtIn {
                ODDivider()
                ODRow("Colour mode") {
                    // Offer only the preset codes the panel advertises (VCP 0x14 is a non-continuous
                    // enum); a contiguous 1...max guess offers codes the monitor silently ignores.
                    // NOTE: capabilities are only populated by an explicit read (the 0xF3 read can
                    // wedge panels, so the app never runs it automatically) — until then this takes
                    // the 1...max fallback path.
                    let codes = model.colorPresetCodes(for: display)
                    HStack(spacing: 8) {
                        if codes.isEmpty {
                            Text(model.colorPreset[display.recordID].map { model.presetName($0) } ?? "—")
                                .appBodyFont().foregroundStyle(.secondary)
                        } else {
                            Picker("Colour mode", selection: Binding(
                                get: { model.colorPreset[display.recordID] },
                                set: { if let code = $0 { model.setColorPreset(code, for: display) } })) {
                                if let selected = model.colorPreset[display.recordID], !codes.contains(selected) {
                                    Text(model.presetName(selected)).tag(Optional(selected))
                                }
                                ForEach(codes, id: \.self) { code in
                                    Text(model.presetName(code)).tag(Optional(code))
                                }
                            }
                            .labelsHidden().pickerStyle(.menu).fixedSize()
                        }
                        #if !PUBLIC_API_ONLY
                        if model.ddcCapabilities[display.recordID] == nil {
                            Button(detectingModes ? "Detecting…" : "Detect…") { detectModes() }
                                .disabled(detectingModes)
                        }
                        #endif
                    }
                }
                if model.ddcWriteWasIgnored(0x14, for: display), let current = model.colorPreset[display.recordID] {
                    secondaryNote("The monitor stayed on \(model.presetName(current)).")
                }
                #if !PUBLIC_API_ONLY
                if detectFoundNothing {
                    secondaryNote("No capabilities reported")
                } else if model.ddcCapabilities[display.recordID] == nil {
                    secondaryNote("Detecting asks the monitor which modes it supports. A few monitors stop "
                                  + "answering DDC afterwards until power-cycled.")
                }
                #endif
            }
            ODDivider()
            ODRow("Colour profile") {
                if model.colorProfileControllable[display.recordID] == true {
                    let profiles = model.availableColorProfilesCache
                    let currentName = model.colorProfileName[display.recordID]
                    let currentID = profiles.first(where: { $0.name == currentName })?.id
                    Picker("Colour profile", selection: Binding(
                        get: { currentID ?? (currentName == nil || currentName == "Factory Default" ? "" : "__current__") },
                        set: { selected in
                            if selected.isEmpty {
                                Task { await model.resetColorProfile(for: display) }
                            } else if let profile = profiles.first(where: { $0.id == selected }) {
                                Task { await model.setColorProfile(profile, for: display) }
                            }
                        })) {
                        Text("Factory Default").tag("")
                        if let currentName, currentID == nil, currentName != "Factory Default" {
                            Text(currentName).tag("__current__")
                        }
                        ForEach(profiles) { profile in
                            Text(profile.name).tag(profile.id)
                        }
                    }
                    .labelsHidden().pickerStyle(.menu).fixedSize()
                } else {
                    Text("Unavailable").appBodyFont().foregroundStyle(.secondary)
                }
            }
        }
    }

    private func secondaryNote(_ text: String) -> some View {
        Text(text)
            .appBodyFont().foregroundStyle(.secondary)
            .padding(.horizontal, 10).padding(.bottom, 4)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Explicit, user-initiated capabilities read (the 0xF3 read is never run automatically — see
    /// `AppModel.refreshCapabilities`). Re-reads the preset afterwards so the menu, now narrowed to
    /// the advertised codes, shows the panel's real current mode.
    private func detectModes() {
        detectingModes = true
        detectFoundNothing = false
        Task {
            await model.refreshCapabilities(for: display)
            await model.refreshColorPreset(for: display)
            detectingModes = false
            guard model.ddcCapabilities[display.recordID] == nil else { return }
            detectFoundNothing = true
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            detectFoundNothing = false
        }
    }
}

// MARK: - Hardware controls (DDC, external only)

private struct ControlsCard: View {
    @EnvironmentObject private var model: AppModel
    let display: DisplayObservation
    @State private var confirmingReset = false
    @State private var resetting = false

    /// Shown under a slider whose last write the panel answered with a different value.
    private static let ignoredNote = "The monitor ignored this change. Its picture mode may lock this setting."

    var body: some View {
        ODCard(title: "Controls",
               footnote: "Hardware controls sent over DDC/CI. Availability depends on the monitor.") {
            // Brightness first, and always: it has a software fallback, so it's usable even on a
            // panel that reports none of the DDC extras below. Same model funnel as the popover.
            ODRow("Brightness", secondary: model.brightnessCaption(for: display)) {
                sliderWithReadout(level: model.brightness[display.recordID] ?? 1) { value in
                    model.setBrightness(value, for: display)
                }
            }
            if model.ddcWriteWasIgnored(0x10, for: display) { ignoredCaption(Self.ignoredNote) }
            ODDivider()
            let controls = HardwareControl.allCases.filter { model.ddcControl($0, for: display) != nil }
            if controls.isEmpty {
                ODRow("No other adjustable hardware controls reported") {}
                // A panel that answers nothing usually isn't DDC-less — its scaler's DDC channel is
                // often just stuck (a state that survives display sleep; only its own power button
                // clears it). Say so, or "unsupported" reads as a dead feature the user can't act on.
                Text("If this monitor supported hardware control before, its DDC channel may be stuck — try turning the monitor off and on with its own power button, then reopen this pane.")
                    .appBodyFont().foregroundStyle(.secondary)
                    .padding(.horizontal, 10).padding(.bottom, 6)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(Array(controls.enumerated()), id: \.element) { index, control in
                    if index > 0 { ODDivider() }
                    ODRow(control.label) {
                        sliderWithReadout(level: model.ddcControl(control, for: display) ?? 0.5) { value in
                            model.setHardwareControl(control, value, for: display)
                        }
                    }
                    if model.ddcWriteWasIgnored(control.vcp, for: display) { ignoredCaption(Self.ignoredNote) }
                }
            }
            #if !PUBLIC_API_ONLY
            if let status = model.adaptiveStatusLine(for: display) {
                ODDivider()
                Text(status)
                    .appBodyFont().foregroundStyle(.secondary)
                    .padding(.horizontal, 10).padding(.vertical, 4)
            }
            #endif
            ODDivider()
            ODRow("Input source") {
                Picker("Input source", selection: Binding(
                    get: { model.inputSource[display.recordID] },
                    set: { if let code = $0 { model.setInputSource(code, for: display) } })) {
                    if model.inputSource[display.recordID] == nil {
                        Text("—").tag(Optional<Int>.none)
                    }
                    ForEach(AppModel.standardInputs, id: \.code) { input in
                        Text(input.name).tag(Optional(input.code))
                    }
                }
                .labelsHidden().pickerStyle(.menu).fixedSize()
            }
            ODDivider()
            ODRow("Power", secondary: "Some displays can't wake over DDC once off") {
                Menu("Set power…") {
                    ForEach(DDCPowerMode.allCases, id: \.self) { mode in
                        Button(mode.label) { model.setPowerMode(mode, for: display) }
                    }
                }
                .menuStyle(.borderedButton).controlSize(.regular)
                .frame(minWidth: 132, alignment: .trailing)
            }
            #if !PUBLIC_API_ONLY
            ODDivider()
            ODRow("Reset to defaults", secondary: "Restores the monitor's factory settings") {
                Button(resetting ? "Resetting…" : "Reset to defaults…") { confirmingReset = true }
                    .controlSize(.regular)
                    .appBodyFont()
                    .frame(minWidth: 164)
                    .disabled(resetting)
            }
            #endif
        }
        .confirmationDialog("Reset \(model.displayName(for: display)) to defaults?",
                            isPresented: $confirmingReset, titleVisibility: .visible) {
            Button("Reset to Defaults", role: .destructive) {
                resetting = true
                Task {
                    await model.resetToDefaults(for: display)
                    resetting = false
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The monitor restores its factory settings — brightness, contrast, colour mode, and "
                 + "anything else it resets. OpenSwitch also clears its software dimming and colour "
                 + "temperature for this display.")
        }
    }

    private func ignoredCaption(_ text: String) -> some View {
        Text(text)
            .appBodyFont().foregroundStyle(.secondary)
            .padding(.horizontal, 10).padding(.bottom, 4)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func sliderWithReadout(level: Float, set: @escaping (Float) -> Void) -> some View {
        HStack(spacing: 8) {
            Slider(value: Binding(get: { Double(level) }, set: { set(Float($0)) }), in: 0...1)
                .frame(width: 160)
            Text("\(Int((level * 100).rounded()))%")
                .appBodyFont().monospacedDigit().foregroundStyle(.secondary)
                .fixedSize(horizontal: true, vertical: false)
                .frame(minWidth: 58, alignment: .trailing)
        }
    }
}

// MARK: - Software dimming (any display)

private struct DimmingCard: View {
    @EnvironmentObject private var model: AppModel
    let display: DisplayObservation

    /// Gamma alone bottoms out at its floor; the overlay methods can keep going (still capped short
    /// of full black by the composer).
    private var range: ClosedRange<Double> {
        model.settings.dimmingMethod == .gamma ? 0.15...1 : 0...1
    }

    private var footnote: String {
        switch model.settings.dimmingMethod {
        case .gamma:
            return "Software gamma dim, applied on top of brightness. Works on any display, "
                + "including below the hardware minimum."
        case .overlay:
            return "A black overlay at adjustable opacity, applied on top of brightness. Works on "
                + "any display; the menu bar stays visible so you can always find your way back."
        case .combined:
            return "Gamma dim first, then a black overlay on top \u{2014} darker than either method "
                + "alone, and still never fully black."
        }
    }

    var body: some View {
        ODCard(title: "Dimming", footnote: footnote) {
            ODRow("Software dimming") {
                HStack(spacing: 8) {
                    Slider(value: Binding(get: { Double(model.softwareDim[display.recordID] ?? 1) },
                                          set: { model.setSoftwareDim(Float($0), for: display) }), in: range)
                        .frame(width: 160)
                    Text("\(Int(((model.softwareDim[display.recordID] ?? 1) * 100).rounded()))%")
                        .appBodyFont().monospacedDigit().foregroundStyle(.secondary)
                        .fixedSize(horizontal: true, vertical: false)
                        .frame(minWidth: 58, alignment: .trailing)
                }
            }
            ODRow("Method") {
                Picker("", selection: Binding(
                    get: { model.settings.dimmingMethod },
                    set: { model.setDimmingMethod($0) })) {
                    Text("Gamma").tag(DimmingMethod.gamma)
                    Text("Overlay").tag(DimmingMethod.overlay)
                    Text("Combined").tag(DimmingMethod.combined)
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
            }
        }
    }
}

// MARK: - Identity (rename)

private struct IdentityCard: View {
    @EnvironmentObject private var model: AppModel
    let display: DisplayObservation
    @State private var alias = ""
    @State private var showingNameEditor = false

    private var displayName: String {
        alias.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? model.displayName(for: display)
            : alias
    }

    var body: some View {
        ODCard(title: "Name") {
            ODRow("Display name") {
                HStack(spacing: 8) {
                    Text(displayName)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    Button("Edit") { showingNameEditor = true }
                }
            }
        }
        .sheet(isPresented: $showingNameEditor) {
            DisplayNameEditorSheet(currentName: displayName) { updatedName in
                alias = updatedName
                Task { await model.setAlias(updatedName, for: display) }
            }
        }
        .onAppear { alias = model.records[display.recordID]?.alias ?? "" }
    }
}

private struct DisplayNameEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (String) -> Void
    @State private var draft: String

    init(currentName: String, onSave: @escaping (String) -> Void) {
        self.onSave = onSave
        _draft = State(initialValue: currentName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Display name").font(.title3.weight(.semibold))
            TextField("Display name", text: $draft)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Save") {
                    onSave(draft.trimmingCharacters(in: .whitespacesAndNewlines))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 440)
        .appBodyFont()
    }
}

// MARK: - Information (read-only)

private struct InformationCard: View {
    @EnvironmentObject private var model: AppModel
    let display: DisplayObservation

    var body: some View {
        ODCard(title: "Information") {
            let info = model.displayInfo(for: display)
            ForEach(Array(info.enumerated()), id: \.element.label) { index, item in
                if index > 0 { ODDivider() }
                ODRow(item.label) {
                    Text(item.value).appBodyFont().foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
    }
}
#endif
