#if os(macOS)
import AppKit
import DisplayDomain
import OpenDisplayDesignSystem
import SwiftUI
import TopologyCore

/// The small fixed set of ⌃⌥⌘-digit chords offered for a new input-switch hotkey (todo 4: Lunar's
/// "Input Hotkeys"). A short pick-list, like the input-code menu already offers with
/// `AppModel.standardInputs`, rather than an open-ended key-capture recorder — that's a bigger
/// feature saved for the general hotkey-rebind follow-up this repo already has pending.
enum HotkeyDigitChords {
    /// Carbon ANSI virtual key codes for the digit row, keyed by the digit itself (1...9).
    private static let keyCodesByDigit: [Int: UInt32] = [
        1: 0x12, 2: 0x13, 3: 0x14, 4: 0x15, 5: 0x17, 6: 0x16, 7: 0x1A, 8: 0x1C, 9: 0x19,
    ]
    private static let fallbackDigit = 1

    static func binding(forDigit digit: Int) -> KeyBinding {
        let keyCode = keyCodesByDigit[digit] ?? keyCodesByDigit[fallbackDigit] ?? 0
        return KeyBinding(keyCode: keyCode, modifiers: KeyBinding.controlOptionCommand)
    }

    static func label(forDigit digit: Int) -> String { "\u{2303}\u{2325}\u{2318}\(digit)" }

    static func label(for binding: KeyBinding) -> String? {
        guard binding.modifiers == KeyBinding.controlOptionCommand,
              let digit = (1...9).first(where: { self.binding(forDigit: $0) == binding }) else { return nil }
        return label(forDigit: digit)
    }
}

/// Settings → Computers section for input-switch hotkeys: lists the configured bindings and
/// lets the user add, edit or remove one. Each binding chooses a display, input value and command
/// channel; actual I2C writes remain in the shared DDC controller.
struct InputHotkeySection: View {
    @EnvironmentObject private var model: AppModel
    @State private var editorWindow: NSWindow?

    private var externalDisplays: [DisplayObservation] {
        model.displays.filter { $0.displayClass != .builtIn }
    }

    private var localComputerName: String {
        Host.current().localizedName ?? ProcessInfo.processInfo.hostName
    }

    private var hasOtherComputerSetup: Bool {
        model.settings.hotkeyShortcuts.inputSwitchBindings.contains { entry in
            guard let name = entry.destinationName else { return false }
            return name.localizedCaseInsensitiveCompare(localComputerName) != .orderedSame
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ODSpacing.sm) {
            if !hasOtherComputerSetup {
                setupIntroduction
            }
            ForEach(Array(model.settings.hotkeyShortcuts.inputSwitchBindings.enumerated()), id: \.element.id) { index, entry in
                if index > 0 { ODDivider(inset: 0) }
                InputHotkeyRow(entry: entry) { openEditor(entry) }
            }

            if let status = model.inputHandoffStatus {
                Text(status).appBodyFont().foregroundStyle(.secondary)
            }
            if let status = model.sharedSetupSaveStatus {
                Text(status).appBodyFont().foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }

            Button {
                openEditor(nil)
            } label: {
                Label("Add computer\u{2026}", systemImage: "plus")
            }
            if hasOtherComputerSetup {
                Text("Set up both computers here and save the reviewed setup to both Macs.")
                    .appBodyFont()
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var setupIntroduction: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Set up your Macs")
                .font(.title2.weight(.semibold))
            Text("This Mac: \(localComputerName)")
                .appBodyFont()
            VStack(alignment: .leading, spacing: 8) {
                Text("1. Open OpenSwitch on your other Mac.")
                Text("2. Choose Add computer here. This adds both Macs to this Mac’s switch menu.")
                Text("3. Accept the pairing request on the other Mac.")
            }
            .appBodyFont()
            .fixedSize(horizontal: false, vertical: true)
            if externalDisplays.isEmpty {
                Label("Connect the external monitor to this Mac before continuing.", systemImage: "display.trianglebadge.exclamationmark")
                    .appBodyFont()
                    .foregroundStyle(ODColor.caution)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(ODColor.cardBackground, in: RoundedRectangle(cornerRadius: ODRadius.card))
        .overlay(RoundedRectangle(cornerRadius: ODRadius.card).strokeBorder(ODColor.separator, lineWidth: 0.5))
    }

    @MainActor
    private func openEditor(_ entry: InputSwitchBinding?) {
        if let editorWindow, editorWindow.isVisible {
            editorWindow.makeKeyAndOrderFront(nil)
            return
        }

        let hosting = NSHostingController(rootView: AnyView(EmptyView()))
        let window = NSWindow(contentViewController: hosting)
        window.title = entry == nil ? "Add Computer" : "Edit Computer"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 620, height: 440)
        window.setContentSize(NSSize(width: 760, height: 560))
        let settingsWindow = NSApp.windows.first {
            $0.identifier?.rawValue == "OpenSwitch.Settings"
        }
        let closeEditor = { [weak window, weak settingsWindow] in
                if let window, let settingsWindow { settingsWindow.removeChildWindow(window) }
                window?.close()
        }
        if let entry {
            if entry.id.contains(":"), model.peerPairing.pairedPeerID != nil {
                hosting.rootView = AnyView(LiveComputerSetupView(pairing: model.peerPairing, onClose: closeEditor)
                    .environmentObject(model))
            } else {
                hosting.rootView = AnyView(AddInputHotkeySheet(entry: entry, pairing: model.peerPairing, onClose: closeEditor)
                    .environmentObject(model))
            }
        } else {
            hosting.rootView = AnyView(LiveComputerSetupView(pairing: model.peerPairing, onClose: closeEditor)
                .environmentObject(model))
        }
        editorWindow = window
        if let settingsWindow {
            settingsWindow.addChildWindow(window, ordered: .above)
            let parentFrame = settingsWindow.frame
            window.setFrameOrigin(NSPoint(
                x: parentFrame.midX - window.frame.width / 2,
                y: parentFrame.midY - window.frame.height / 2
            ))
        } else {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

}

/// One configured binding: display name, input name, and its chord, with a remove button.
private struct InputHotkeyRow: View {
    @EnvironmentObject private var model: AppModel
    let entry: InputSwitchBinding
    let onEdit: () -> Void
    @State private var showingRemoveConfirmation = false
    @State private var isRemoving = false

    var body: some View {
        ODRow(rowLabel, secondary: shortcutStatus) {
            Button("Edit", action: onEdit)
            Button("Remove", role: .destructive) {
                if isSharedSetupEntry { showingRemoveConfirmation = true }
                else { model.removeInputSwitchHotkey(id: entry.id) }
            }
            .disabled(isRemoving)
        }
        .alert("Remove this shared setup?", isPresented: $showingRemoveConfirmation) {
            Button("Remove from Both Macs", role: .destructive) {
                isRemoving = true
                Task {
                    _ = await model.removeSharedComputerSetup()
                    isRemoving = false
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This removes the monitor, keyboard, and mouse switch setup from both Macs. You can run setup again later.")
        }
    }

    private var shortcutStatus: String {
        let chord = HotkeyDigitChords.label(forDigit: digit)
        return model.unavailableInputHotkeys.contains(entry.id) ? "\(chord) — unavailable; try another shortcut" : chord
    }

    private var rowLabel: String {
        let name = entry.destinationName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !name.isEmpty else { return "\(displayLabel) \u{2192} \(entry.effectiveTransport.inputName(entry.inputCode))" }
        let localName = Host.current().localizedName ?? ProcessInfo.processInfo.hostName
        return name.localizedCaseInsensitiveCompare(localName) == .orderedSame ? "\(name) (This Mac)" : name
    }

    private var isSharedSetupEntry: Bool { entry.id.contains(":") }

    private var displayLabel: String {
        if let live = model.displays.first(where: { $0.recordID == entry.displayID }) {
            return model.displayName(for: live)
        }
        return model.records[entry.displayID]?.displayName ?? entry.displayID.rawValue
    }

    /// Recovers the digit this binding's key code maps to, for the secondary-line label — the chords
    /// offered are exactly the ⌃⌥⌘1...9 set `HotkeyDigitChords` mints, so every stored binding's key
    /// code round-trips back to one of them.
    private var digit: Int {
        (1...9).first { HotkeyDigitChords.binding(forDigit: $0).keyCode == entry.binding.keyCode } ?? 1
    }
}

/// Single-page editor for adding or editing one input-switch destination.
private struct AddInputHotkeySheet: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var pairing: PeerPairing
    let entry: InputSwitchBinding?
    let onClose: () -> Void

    @State private var destinationName = ""
    @State private var selectedDisplayID: DisplayRecordID?
    @State private var selectedPeerID: UUID?
    @State private var localInputCode: Int?
    @State private var selectedInputCode: Int?
    @State private var localSelectedDigit = 1
    @State private var selectedDigit = 1
    @State private var transport = DDCInputTransport.standard
    @State private var useCustomCode = false
    @State private var customCode = ""
    @State private var keyboardEnabled = false
    @State private var mouseEnabled = false
    @State private var mouseName = ""
    @State private var keyboardName = ""
    @State private var mouseSlot = 0
    @State private var keyboardSlot = 0
    @State private var localMouseSlot = 0
    @State private var localKeyboardSlot = 0
    @State private var detected = LogitechHandoff.DeviceChoices()
    @State private var editingDeviceName: DeviceNameField?
    @State private var isDiscoveringDevices = false
    @State private var showingForgetConfirmation = false

    init(entry: InputSwitchBinding? = nil, pairing: PeerPairing, onClose: @escaping () -> Void) {
        self.entry = entry
        self.pairing = pairing
        self.onClose = onClose
        let mode = entry?.peripherals?.mode ?? .monitorOnly
        let transport = entry?.effectiveTransport ?? .standard
        let input = entry?.inputCode
        _destinationName = State(initialValue: entry?.destinationName ?? "")
        _selectedDisplayID = State(initialValue: entry?.displayID)
        _selectedPeerID = State(initialValue: entry?.availabilityPeerID.flatMap(UUID.init(uuidString:)))
        _selectedInputCode = State(initialValue: input)
        _localInputCode = State(initialValue: nil)
        _selectedDigit = State(initialValue: entry.flatMap { value in
            (1...9).first { HotkeyDigitChords.binding(forDigit: $0) == value.binding }
        } ?? 1)
        _transport = State(initialValue: transport)
        _useCustomCode = State(initialValue: input.map { inputValue in
            !transport.inputs.contains { $0.code == inputValue }
        } ?? false)
        _customCode = State(initialValue: input.map { String($0, radix: 16, uppercase: true) } ?? "")
        _keyboardEnabled = State(initialValue: mode != .monitorOnly)
        _mouseEnabled = State(initialValue: mode == .independent)
        _mouseName = State(initialValue: entry?.peripherals?.mouseName ?? "")
        _keyboardName = State(initialValue: entry?.peripherals?.keyboardName ?? "")
        _mouseSlot = State(initialValue: entry?.peripherals?.mouseSlot ?? 0)
        _keyboardSlot = State(initialValue: entry?.peripherals?.keyboardSlot ?? 0)
    }

    private var duplicateName: Bool {
        let name = destinationName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return false }
        let currentID = entry?.id ?? existingDestinationProfile?.id
        return model.settings.hotkeyShortcuts.inputSwitchBindings.contains { saved in
            guard saved.id != currentID, let existing = saved.destinationName else { return false }
            return existing.trimmingCharacters(in: .whitespacesAndNewlines)
                .localizedCaseInsensitiveCompare(name) == .orderedSame
        }
    }

    private var existingDestinationProfile: InputSwitchBinding? {
        let name = destinationName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        return model.settings.hotkeyShortcuts.inputSwitchBindings.first { saved in
            guard saved.id != entry?.id, let savedName = saved.destinationName else { return false }
            return savedName.trimmingCharacters(in: .whitespacesAndNewlines)
                .localizedCaseInsensitiveCompare(name) == .orderedSame
        }
    }

    private var existingLocalProfile: InputSwitchBinding? {
        model.settings.hotkeyShortcuts.inputSwitchBindings.first { saved in
            guard saved.id != entry?.id, let name = saved.destinationName else { return false }
            return name.trimmingCharacters(in: .whitespacesAndNewlines)
                .localizedCaseInsensitiveCompare(localComputerName) == .orderedSame
        }
    }

    private var addBlockerMessage: String? {
        if destinationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Choose the other Mac to continue."
        }
        if entry == nil, selectedPeerID == nil {
            return "Connect to the other Mac and accept its pairing before continuing."
        }
        if selectedDisplayID == nil { return "Connect an external display to continue." }
        if entry == nil, existingLocalProfile == nil, localInputCode == nil {
            return "Choose the monitor input for \(localComputerName)."
        }
        if inputCode == nil { return "Choose the monitor input for \(destinationName)." }
        if keyboardEnabled {
            if keyboardName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "Choose a keyboard or turn off Switch keyboard."
            }
            if entry == nil, existingLocalProfile == nil, !(1...3).contains(localKeyboardSlot) {
                return "Choose the keyboard’s Easy-Switch slot for \(localComputerName)."
            }
            if !(1...3).contains(keyboardSlot) {
                return "Choose the keyboard’s Easy-Switch slot for \(destinationName)."
            }
        }
        if mouseEnabled {
            if mouseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "Choose a mouse or turn off Switch mouse separately."
            }
            if entry == nil, existingLocalProfile == nil, !(1...3).contains(localMouseSlot) {
                return "Choose the mouse’s Easy-Switch slot for \(localComputerName)."
            }
            if !(1...3).contains(mouseSlot) {
                return "Choose the mouse’s Easy-Switch slot for \(destinationName)."
            }
        }
        if duplicateName { return "A computer with this name is already set up." }
        if entry == nil, existingLocalProfile == nil, localSelectedDigit == selectedDigit {
            return "Choose different shortcuts for the two Macs."
        }
        if entry == nil, existingLocalProfile == nil, availableDigits.count < 1 {
            return "Two shortcuts are needed. Remove an existing shortcut to continue."
        }
        if availableDigits.isEmpty { return "All shortcuts are in use. Remove one to continue." }
        if hasConflict { return "Choose a different shortcut to continue." }
        if inputCode == nil { return "Enter a valid input value to continue." }
        return nil
    }

    private var peripheralMode: KVMPeripheralMode {
        guard keyboardEnabled else { return .monitorOnly }
        return mouseEnabled ? .independent : .keyboardLinked
    }

    private var inputCode: Int? {
        guard useCustomCode else { return selectedInputCode }
        let text = customCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = text.lowercased().hasPrefix("0x") ? String(text.dropFirst(2)) : text
        guard let code = Int(digits, radix: 16), (0...0xFFFF).contains(code) else { return nil }
        return code
    }

    private var externalDisplays: [DisplayObservation] {
        model.displays.filter { $0.displayClass != .builtIn }
    }

    private var candidateBinding: KeyBinding { HotkeyDigitChords.binding(forDigit: selectedDigit) }

    private var localCandidateBinding: KeyBinding { HotkeyDigitChords.binding(forDigit: localSelectedDigit) }

    private var localAvailableDigits: [Int] {
        (1...9).filter { digit in
            !model.inputSwitchHotkeyConflicts(
                HotkeyDigitChords.binding(forDigit: digit),
                excludingInputSwitchID: existingLocalProfile?.id
            )
        }
    }

    private var availableDigits: [Int] {
        (1...9).filter { digit in
            digit != (entry == nil ? localSelectedDigit : -1)
                && !model.inputSwitchHotkeyConflicts(
                HotkeyDigitChords.binding(forDigit: digit),
                excludingInputSwitchID: entry?.id ?? existingDestinationProfile?.id
            )
        }
    }

    private func nextAvailableDigit(after digit: Int) -> Int? {
        (1...9).map { offset in ((digit - 1 + offset) % 9) + 1 }
            .first { availableDigits.contains($0) }
    }

    private var hasConflict: Bool {
        (entry == nil && selectedDigit == localSelectedDigit)
            || model.inputSwitchHotkeyConflicts(candidateBinding,
                                                excludingInputSwitchID: entry?.id ?? existingDestinationProfile?.id)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    editorSection("Computer", icon: "desktopcomputer") {
                        computerSection
                    }
                    editorSection("Displays", icon: "display") {
                        monitorSection
                    }
                    editorSection("Keyboard", icon: "keyboard") {
                        keyboardSection
                    }
                    editorSection("Mouse", icon: "computermouse") {
                        mouseSection
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            HStack {
                if let addBlockerMessage {
                    Label(addBlockerMessage, systemImage: "info.circle")
                        .appBodyFont()
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button("Cancel") { onClose() }
                Button(entry == nil ? "Add computer" : "Save changes") { addBinding() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(addBlockerMessage != nil)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(minWidth: 620, idealWidth: 760, minHeight: 440, idealHeight: 560)
        .font(.body)
        .appTextSize(model.settings.openSwitchTextSize)
        .navigationTitle(entry == nil ? "Add Computer" : "Edit Computer")
        .sheet(item: $editingDeviceName) { field in
            DeviceNameEditorSheet(
                title: field.title,
                currentName: deviceName(for: field)
            ) { updatedName in
                setDeviceName(updatedName, for: field)
            }
        }
        .alert("Forget the paired Mac?", isPresented: $showingForgetConfirmation) {
            Button("Forget Pairing", role: .destructive) { _ = pairing.forget() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This removes the saved secure connection on this Mac so you can pair another nearby Mac.")
        }
        .onAppear {
            if entry == nil {
                if let existingLocalProfile,
                   let digit = (1...9).first(where: { HotkeyDigitChords.binding(forDigit: $0) == existingLocalProfile.binding }) {
                    localSelectedDigit = digit
                    if let input = model.inputSource[selectedDisplayID ?? existingLocalProfile.displayID] {
                        localInputCode = input
                    } else {
                        localInputCode = existingLocalProfile.inputCode
                    }
                    if let devices = existingLocalProfile.peripherals {
                        localKeyboardSlot = devices.keyboardSlot
                        localMouseSlot = devices.mouseSlot
                    }
                } else if let available = localAvailableDigits.first {
                    localSelectedDigit = available
                }
                if let available = availableDigits.first { selectedDigit = available }
            }
            if selectedDisplayID == nil { selectedDisplayID = externalDisplays.first?.recordID }
            // Keep the existing local route's transport when adding its paired destination.
            if entry == nil, let existingLocalProfile {
                transport = existingLocalProfile.effectiveTransport
            } else if entry == nil, let id = selectedDisplayID,
                      let configured = model.settings.hotkeyShortcuts.inputSwitchBindings.first(where: { $0.displayID == id }) {
                transport = configured.effectiveTransport
            }
            if entry == nil, localInputCode == nil,
               let id = selectedDisplayID,
               let current = model.inputSource[id], transport.inputs.contains(where: { $0.code == current }) {
                localInputCode = current
            }
            discoverDevices()
            if entry == nil {
                pairing.discoverNearbyComputers()
            }
        }
        .onChange(of: pairing.pairedPeerID) { _, peerID in
            guard entry == nil, peerID != nil,
                  let computer = pairing.nearbyComputers.first(where: isPaired) else { return }
            selectNearbyComputer(computer)
        }
        .onChange(of: pairing.pairedPeerDevices) { _, devices in
            guard entry == nil, devices != nil,
                  selectedPeerID == pairing.pairedPeerID,
                  let computer = pairing.nearbyComputers.first(where: isPaired) else { return }
            selectNearbyComputer(computer)
        }
        .onChange(of: selectedDigit) { _, _ in
            if hasConflict, let available = nextAvailableDigit(after: selectedDigit) {
                selectedDigit = available
            }
        }
        .onChange(of: localSelectedDigit) { _, _ in
            if entry == nil, selectedDigit == localSelectedDigit,
               let available = availableDigits.first {
                selectedDigit = available
            }
        }
    }

    private func editorSection<Content: View>(
        _ title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.title2.weight(.semibold))
            VStack(alignment: .leading, spacing: 0, content: content)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(ODColor.cardBackground, in: RoundedRectangle(cornerRadius: ODRadius.card))
                .overlay(RoundedRectangle(cornerRadius: ODRadius.card).strokeBorder(ODColor.separator, lineWidth: 0.5))
        }
    }

    private func settingRow<Control: View>(
        _ label: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        ODSettingsRow(label, control: control)
    }

    private var settingDivider: some View {
        ODDivider(inset: 0).padding(.horizontal, 14)
    }

    private var computerSection: some View {
        VStack(spacing: 0) {
            if entry == nil {
                computerChoicesSection
                settingDivider
            }
            if !destinationName.isEmpty {
                settingRow("Switch from this Mac") {
                    Text("\(localComputerName)  →  \(destinationName)")
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                settingDivider
            }
            if entry == nil {
                settingRow("Shortcut for \(localComputerName)") {
                    if let existingLocalProfile {
                        Text(HotkeyDigitChords.label(for: existingLocalProfile.binding) ?? "Already set")
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    } else {
                        Picker("This Mac shortcut", selection: $localSelectedDigit) {
                            ForEach(1...9, id: \.self) { digit in
                                Text(HotkeyDigitChords.label(forDigit: digit)).tag(digit)
                            }
                        }
                        .labelsHidden()
                    }
                }
                settingDivider
            }
            settingRow(entry == nil ? "Other Mac name" : "Computer name") {
                HStack(spacing: 8) {
                    Text(destinationName.isEmpty ? "Not set" : destinationName)
                        .foregroundStyle(destinationName.isEmpty ? .secondary : .primary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    Button("Edit") { editingDeviceName = .computer }
                }
            }
            settingDivider
            settingRow(entry == nil ? "Other Mac shortcut" : "Shortcut") {
                Picker("Shortcut", selection: $selectedDigit) {
                    ForEach(1...9, id: \.self) { digit in
                        Text(HotkeyDigitChords.label(forDigit: digit)).tag(digit)
                    }
                }
                .labelsHidden()
            }
            if duplicateName {
                settingDivider
                settingRow("Name") {
                    Text("This name is already in use.").foregroundStyle(ODColor.danger)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            if availableDigits.isEmpty {
                settingDivider
                settingRow("Shortcut") {
                    Text("No shortcut is available. Remove an existing shortcut to continue.")
                        .foregroundStyle(ODColor.danger)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
    }

    private var computerChoicesSection: some View {
        VStack(spacing: 0) {
            settingRow("This Mac") {
                Text(localSetupSummary)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            settingDivider
            settingRow("Switch menu") {
                Label(existingLocalProfile == nil ? "This Mac will be added" : "This Mac is already included",
                      systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            settingDivider
            settingRow("Nearby computers") {
                HStack(spacing: 8) {
                    if pairing.pairingStatus?.hasPrefix("Searching") == true {
                        ProgressView().controlSize(.small)
                    }
                    Text(pairing.pairingStatus ?? "Searching for OpenSwitch Macs…")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            settingDivider
            let otherComputers = pairing.nearbyComputers.filter { $0.peerID != pairing.localID }
            if otherComputers.isEmpty {
                settingRow("No other Mac found") {
                    Text("Open OpenSwitch on the other Mac and keep both Macs on the same network.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            } else {
                ForEach(otherComputers) { computer in
                    settingRow(computer.name) {
                        if isSelected(computer) {
                            Label("Selected", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else if isPaired(computer) {
                            Button("Choose") { selectNearbyComputer(computer) }
                        } else if pairing.pairedPeerID != nil {
                            Text("Forget the current pairing before choosing this Mac.")
                                .appBodyFont().foregroundStyle(.secondary)
                        } else {
                            Button(pairing.isConnecting ? "Waiting…" : "Connect") {
                                pairing.connect(to: computer)
                            }
                            .disabled(pairing.isConnecting || isDiscoveringDevices)
                        }
                    }
                    settingDivider
                }
            }
            if pairing.pairedPeerID != nil {
                settingRow("Pairing") {
                    Button("Forget pairing…", role: .destructive) { showingForgetConfirmation = true }
                }
            }
            if selectedPeerID == pairing.pairedPeerID, let peerDevices = pairing.pairedPeerDevices {
                settingDivider
                settingRow("Devices found on \(destinationName)") {
                    Text(deviceSummary(peerDevices))
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
    }

    private var monitorSection: some View {
        VStack(spacing: 0) {
            settingRow("Display") {
                Picker("Display", selection: $selectedDisplayID) {
                    ForEach(externalDisplays, id: \.recordID) { display in
                        Text(model.displayName(for: display)).tag(display.recordID as DisplayRecordID?)
                    }
                }
                .labelsHidden()
            }
            settingDivider
            if entry == nil {
                settingRow("Input for \(localComputerName)") {
                    if let existingLocalProfile {
                        Text(transport.inputName(existingLocalProfile.inputCode))
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    } else {
                        Picker("Input for this Mac", selection: $localInputCode) {
                            Text("Choose an input").tag(nil as Int?)
                            ForEach(transport.inputs, id: \.code) { input in
                                Text(input.name).tag(input.code as Int?)
                            }
                        }
                        .labelsHidden()
                    }
                }
                settingDivider
                settingRow("Input for \(destinationLabelForSlot)") {
                    inputPicker
                }
            } else {
                settingRow("Input") { inputPicker }
            }
            settingDivider
            settingRow("Monitor mode") {
                Picker("Monitor mode", selection: $transport) {
                    ForEach(DDCInputTransport.allCases, id: \.self) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .labelsHidden()
            }
            settingDivider
            settingRow("Custom input value") {
                Toggle("Custom input value", isOn: $useCustomCode)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            if useCustomCode {
                settingDivider
                settingRow("Input value (hex)") {
                    TextField("For example, 0xD1", text: $customCode)
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
        .onChange(of: transport) { _, mode in
            selectedInputCode = entry == nil ? nil : mode.inputs.first?.code
            if entry == nil { localInputCode = nil }
        }
    }

    private var inputPicker: some View {
        Picker("Input", selection: $selectedInputCode) {
            Text("Choose an input").tag(nil as Int?)
            ForEach(transport.inputs, id: \.code) { input in
                Text(input.name).tag(input.code as Int?)
            }
        }
        .labelsHidden()
        .disabled(useCustomCode)
    }

    private var keyboardSection: some View {
        VStack(spacing: 0) {
            settingRow("Switch keyboard") {
                Toggle("Switch keyboard", isOn: Binding(
                    get: { keyboardEnabled },
                    set: { enabled in
                        keyboardEnabled = enabled
                        if !enabled { mouseEnabled = false }
                    }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
            }
            if keyboardEnabled {
                settingDivider
                keyboardControls
                settingDivider
                settingRow("Detected devices") {
                    Button("Refresh") { discoverDevices() }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
    }

    private var mouseSection: some View {
        VStack(spacing: 0) {
            settingRow("Switch mouse separately") {
                Toggle("Switch mouse separately", isOn: $mouseEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(!keyboardEnabled)
            }
            if !keyboardEnabled {
                settingDivider
                settingRow("Mouse switching") {
                    Text("Enable keyboard switching first.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            } else if mouseEnabled {
                settingDivider
                mouseControls
            } else {
                settingDivider
                settingRow("Mouse behavior") {
                    Text("Follows keyboard when linked.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
    }

    private var keyboardControls: some View {
        VStack(spacing: 0) {
            settingRow("Keyboard") {
                HStack(spacing: 8) {
                    if detected.keyboards.isEmpty {
                        deviceNameDisplay(keyboardName)
                    } else {
                        Picker("Keyboard", selection: $keyboardName) {
                            Text("Choose a keyboard").tag("")
                            if !keyboardName.isEmpty && !detected.keyboards.contains(keyboardName) {
                                Text("\(LogitechHandoff.friendlyName(keyboardName)) (not connected)").tag(keyboardName)
                            }
                            ForEach(detected.keyboards, id: \.self) {
                                Text(LogitechHandoff.friendlyName($0)).tag($0)
                            }
                        }
                        .labelsHidden()
                    }
                    Button("Edit") { editingDeviceName = .keyboard }
                }
            }
            settingDivider
            if entry == nil {
                settingRow("Keyboard slot on \(localComputerName)") {
                    if let peripherals = existingLocalProfile?.peripherals {
                        Text("Slot \(peripherals.keyboardSlot)")
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    } else if existingLocalProfile != nil {
                        Text("Keyboard switching is off")
                            .foregroundStyle(.secondary)
                    } else {
                        slotPicker(label: "Keyboard slot on this Mac", selection: $localKeyboardSlot)
                    }
                }
                settingDivider
            }
            settingRow("Keyboard slot on \(destinationLabelForSlot)") {
                slotPicker(label: "Keyboard slot on other Mac", selection: $keyboardSlot)
            }
        }
    }

    private var mouseControls: some View {
        VStack(spacing: 0) {
            settingRow("Mouse") {
                HStack(spacing: 8) {
                    if detected.mice.isEmpty {
                        deviceNameDisplay(mouseName)
                    } else {
                        Picker("Mouse", selection: $mouseName) {
                            Text("Choose a mouse").tag("")
                            if !mouseName.isEmpty && !detected.mice.contains(mouseName) {
                                Text("\(LogitechHandoff.friendlyName(mouseName)) (not connected)").tag(mouseName)
                            }
                            ForEach(detected.mice, id: \.self) {
                                Text(LogitechHandoff.friendlyName($0)).tag($0)
                            }
                        }
                        .labelsHidden()
                    }
                    Button("Edit") { editingDeviceName = .mouse }
                }
            }
            settingDivider
            if entry == nil {
                settingRow("Mouse slot on \(localComputerName)") {
                    if let peripherals = existingLocalProfile?.peripherals,
                       peripherals.mode == .independent {
                        Text("Slot \(peripherals.mouseSlot)")
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    } else if existingLocalProfile != nil {
                        Text("Mouse follows the keyboard")
                            .foregroundStyle(.secondary)
                    } else {
                        slotPicker(label: "Mouse slot on this Mac", selection: $localMouseSlot)
                    }
                }
                settingDivider
            }
            settingRow("Mouse slot on \(destinationLabelForSlot)") {
                slotPicker(label: "Mouse slot on other Mac", selection: $mouseSlot)
            }
        }
    }

    private func slotPicker(label: String, selection: Binding<Int>) -> some View {
        Picker(label, selection: selection) {
            Text("Choose a slot").tag(0)
            ForEach(1...3, id: \.self) { slot in Text("Slot \(slot)").tag(slot) }
        }
        .labelsHidden()
    }

    private func deviceNameDisplay(_ name: String) -> some View {
        Text(name.isEmpty ? "Not set" : LogitechHandoff.friendlyName(name))
            .foregroundStyle(name.isEmpty ? .secondary : .primary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func deviceName(for field: DeviceNameField) -> String {
        switch field {
        case .computer: destinationName
        case .keyboard: keyboardName
        case .mouse: mouseName
        }
    }

    private func setDeviceName(_ name: String, for field: DeviceNameField) {
        switch field {
        case .computer: destinationName = name
        case .keyboard: keyboardName = name
        case .mouse: mouseName = name
        }
    }

    private func discoverDevices() {
        isDiscoveringDevices = true
        Task {
            let devices = await Task.detached(priority: .utility) { LogitechHandoff.detectedDevices() }.value
            detected = devices
            if keyboardName.isEmpty && devices.keyboards.count == 1 { keyboardName = devices.keyboards[0] }
            if mouseName.isEmpty && devices.mice.count == 1 { mouseName = devices.mice[0] }
            isDiscoveringDevices = false
        }
    }

    private var localComputerName: String {
        Host.current().localizedName ?? ProcessInfo.processInfo.hostName
    }

    private var localSetupSummary: String {
        if isDiscoveringDevices {
            return "\(localComputerName)\nChecking this Mac’s devices…"
        }
        let displayNames = externalDisplays.map { model.displayName(for: $0) }
        let displayText = displayNames.isEmpty ? "No external display detected" : displayNames.joined(separator: ", ")
        let keyboardText = detected.keyboards.isEmpty
            ? "No Logitech keyboard detected"
            : detected.keyboards.map(LogitechHandoff.friendlyName).joined(separator: ", ")
        let mouseText = detected.mice.isEmpty
            ? "No Logitech mouse detected"
            : detected.mice.map(LogitechHandoff.friendlyName).joined(separator: ", ")
        return "\(localComputerName)\nMonitor: \(displayText)\nKeyboard: \(keyboardText)\nMouse: \(mouseText)"
    }

    private func deviceSummary(_ devices: LogitechHandoff.DeviceChoices) -> String {
        let names = devices.keyboards.map(LogitechHandoff.friendlyName)
            + devices.mice.map(LogitechHandoff.friendlyName)
        return names.isEmpty ? "No Logitech devices detected" : names.joined(separator: ", ")
    }

    private var destinationLabelForSlot: String {
        destinationName.isEmpty ? "the other Mac" : destinationName
    }

    private func selectNearbyComputer(_ computer: NearbyOpenSwitchMac) {
        destinationName = computer.name
        let sameName = computer.name.localizedCaseInsensitiveCompare(pairing.pairedPeerName ?? "") == .orderedSame
        selectedPeerID = computer.peerID ?? (sameName ? pairing.pairedPeerID : nil)
        if let saved = existingDestinationProfile {
            selectedDisplayID = saved.displayID
            selectedInputCode = saved.inputCode
            transport = saved.effectiveTransport
            useCustomCode = !transport.inputs.contains { $0.code == saved.inputCode }
            customCode = String(saved.inputCode, radix: 16, uppercase: true)
            selectedDigit = (1...9).first(where: { HotkeyDigitChords.binding(forDigit: $0) == saved.binding }) ?? selectedDigit
            if let peripherals = saved.peripherals {
                keyboardEnabled = peripherals.mode != .monitorOnly
                mouseEnabled = peripherals.mode == .independent
                keyboardName = peripherals.keyboardName
                mouseName = peripherals.mouseName
                keyboardSlot = peripherals.keyboardSlot
                mouseSlot = peripherals.mouseSlot
            } else {
                keyboardEnabled = false
                mouseEnabled = false
                keyboardName = detected.keyboards.first ?? ""
                mouseName = detected.mice.first ?? ""
                keyboardSlot = 0
                mouseSlot = 0
            }
            return
        }
        keyboardEnabled = !detected.keyboards.isEmpty
        mouseEnabled = keyboardEnabled && !detected.mice.isEmpty
        keyboardName = detected.keyboards.first ?? ""
        mouseName = detected.mice.first ?? ""
        // The helper reports the device's active channel, not a verified mapping from
        // Easy-Switch slots to Mac names. Ask the user to select each destination slot.
        keyboardSlot = 0
        mouseSlot = 0
    }

    private func isPaired(_ computer: NearbyOpenSwitchMac) -> Bool {
        if let pairedID = pairing.pairedPeerID, let discoveredID = computer.peerID {
            return pairedID == discoveredID
        }
        return pairing.pairedPeerName != nil
            && computer.name.localizedCaseInsensitiveCompare(pairing.pairedPeerName ?? "") == .orderedSame
    }

    private func isSelected(_ computer: NearbyOpenSwitchMac) -> Bool {
        guard let selectedPeerID else { return false }
        if let peerID = computer.peerID { return peerID == selectedPeerID }
        return selectedPeerID == pairing.pairedPeerID && isPaired(computer)
    }

    private func addBinding() {
        guard let displayID = selectedDisplayID, let remoteInputCode = inputCode else { return }
        let transportValue = transport == .standard ? nil : transport
        let remoteName = destinationName.trimmingCharacters(in: .whitespacesAndNewlines)
        let remotePeripherals = peripheralMode == .monitorOnly ? nil : KVMPeripheralConfiguration(
            mode: peripheralMode, mouseName: mouseName, keyboardName: keyboardName,
            mouseSlot: mouseSlot, keyboardSlot: keyboardSlot)

        if let entry {
            model.addInputSwitchHotkey(InputSwitchBinding(
                id: entry.id, displayID: displayID, inputCode: remoteInputCode, binding: candidateBinding,
                transport: transportValue, peripherals: remotePeripherals,
                destinationName: remoteName, availabilityPeerID: selectedPeerID?.uuidString
            ))
        } else {
            if existingLocalProfile == nil, let localInputCode {
                let localPeripherals = peripheralMode == .monitorOnly ? nil : KVMPeripheralConfiguration(
                    mode: peripheralMode, mouseName: mouseName, keyboardName: keyboardName,
                    mouseSlot: localMouseSlot, keyboardSlot: localKeyboardSlot)
                model.addInputSwitchHotkey(InputSwitchBinding(
                    displayID: displayID, inputCode: localInputCode, binding: localCandidateBinding,
                    transport: transportValue, peripherals: localPeripherals,
                    destinationName: localComputerName
                ))
            }
            model.addInputSwitchHotkey(InputSwitchBinding(
                id: existingDestinationProfile?.id ?? UUID().uuidString,
                displayID: displayID, inputCode: remoteInputCode, binding: candidateBinding,
                transport: transportValue, peripherals: remotePeripherals,
                destinationName: remoteName, availabilityPeerID: selectedPeerID?.uuidString
            ))
        }
        onClose()
    }
}

private enum DeviceNameField: String, Identifiable {
    case computer, keyboard, mouse

    var id: Self { self }
    var title: String {
        switch self {
        case .computer: "Computer name"
        case .keyboard: "Keyboard device name"
        case .mouse: "Mouse device name"
        }
    }
}

private struct DeviceNameEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let currentName: String
    let onSave: (String) -> Void
    @State private var draft: String

    init(title: String, currentName: String, onSave: @escaping (String) -> Void) {
        self.title = title
        self.currentName = currentName
        self.onSave = onSave
        _draft = State(initialValue: currentName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.title3.weight(.semibold))
            TextField("Device name", text: $draft)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    onSave(draft.trimmingCharacters(in: .whitespacesAndNewlines))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 440)
    }
}
#endif
