#if os(macOS)
import AppKit
import DisplayDomain
import SwiftUI
import TopologyCore

/// Production adapter for the same guided surface used by the isolated preview.
struct LiveComputerSetupView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var pairing: PeerPairing
    let onClose: () -> Void
    @State private var draft = ComputerSetupDraft()
    @State private var selectedPeerID: UUID?
    @State private var setupID = UUID()
    @State private var revision: UInt64 = 1
    @State private var digits = [1, 2]
    @State private var shortcutsReady = false
    @State private var localError = ""
    @State private var keyboardOptions: [String] = []
    @State private var mouseOptions: [String] = []

    var body: some View {
        ComputerSetupWizard(draft: $draft,
            nearbyMacs: pairing.nearbyComputers.compactMap { computer in
                guard let id = computer.peerID, id != pairing.localID else { return nil }
                return SetupNearbyMac(id: id, name: computer.name)
            }, connectedPeerID: selectedPeerID,
            connectionStatus: pairing.pairingStatus ?? "Looking for another Mac…",
            inputNames: DDCInputTransport.allCases.flatMap { $0.inputs.map(\.name) },
            keyboardOptions: keyboardOptions, mouseOptions: mouseOptions,
            saveStatus: model.sharedSetupSaveStatus ?? localError, isSaving: model.isSavingSharedSetup,
            onConnect: connect, onSave: save, onCancel: onClose,
            onRetry: model.hasPendingSharedSetup ? {
                Task { if await model.retrySharedSetup() { onClose() } }
            } : nil)
        .task {
            model.refreshPendingSharedSetup()
            draft.localName = Host.current().localizedName ?? ProcessInfo.processInfo.hostName
            if let display = model.displays.first(where: { $0.displayClass != .builtIn && $0.displayClass != .virtual }) {
                draft.monitor = model.displayName(for: display)
            }
            let devices = await Task.detached(priority: .utility) { LogitechHandoff.detectedDevices() }.value
            let savedDevices = model.settings.hotkeyShortcuts.inputSwitchBindings.compactMap(\.peripherals)
            keyboardOptions = Array(Set(devices.keyboards + savedDevices.map(\.keyboardName).filter { !$0.isEmpty })).sorted()
            mouseOptions = Array(Set(devices.mice + savedDevices.map(\.mouseName).filter { !$0.isEmpty })).sorted()
            draft.keyboard = keyboardOptions.count == 1 ? keyboardOptions[0] : ""
            draft.mouse = mouseOptions.count == 1 ? mouseOptions[0] : ""
            draft.keyboardIncluded = !keyboardOptions.isEmpty
            draft.mouseIncluded = draft.keyboardIncluded && !mouseOptions.isEmpty
            let free = (1...9).filter { !model.inputSwitchHotkeyConflicts(HotkeyDigitChords.binding(forDigit: $0), excludingInputSwitchID: nil) }
            if free.count >= 2 { digits = Array(free.prefix(2)) }
            shortcutsReady = free.count >= 2
            draft.shortcuts = digits.map(HotkeyDigitChords.label(forDigit:))
            pairing.discoverNearbyComputers()
            if let peerID = pairing.pairedPeerID {
                selectedPeerID = peerID
                draft.otherName = pairing.pairedPeerName ?? ""
                prefillExisting(peerID: peerID)
            }
        }
        .onChange(of: pairing.pairedPeerID) { _, id in
            if let id, let name = pairing.pairedPeerName {
                selectedPeerID = id; draft.otherName = name
                prefillExisting(peerID: id)
            }
        }
    }

    private func connect(_ computer: SetupNearbyMac) {
        if pairing.pairedPeerID == computer.id {
            selectedPeerID = computer.id; draft.otherName = computer.name
            prefillExisting(peerID: computer.id)
        } else if let discovered = pairing.nearbyComputers.first(where: { $0.peerID == computer.id }) {
            pairing.connect(to: discovered)
        }
    }

    private func save() {
        guard shortcutsReady else {
            localError = "Two available shortcuts are required. Free a shortcut and reopen setup."
            return
        }
        guard let selectedPeerID,
              let localInput = resolveInput(draft.localInput),
              let otherInput = resolveInput(draft.otherInput) else { return }
        let profiles = [pairing.localID, selectedPeerID].enumerated().map { index, id in
            SharedComputerSetup.Computer(peerID: id,
                name: index == 0 ? draft.localName : draft.otherName,
                inputCode: index == 0 ? localInput.code : otherInput.code,
                transport: index == 0 ? localInput.transport : otherInput.transport,
                keyboard: draft.keyboardIncluded ? .init(name: draft.keyboard, slot: draft.keyboardSlots[index]) : nil,
                mouse: draft.mouseIncluded ? .init(name: draft.mouse, slot: draft.mouseSlots[index]) : nil,
                shortcut: HotkeyDigitChords.binding(forDigit: digits[index]))
        }
        let display = model.displays.first { model.displayName(for: $0) == draft.monitor && $0.displayClass == .external }
        let record = display.flatMap { model.records[$0.recordID] ?? model.registryKnownRecords[$0.recordID] }
        let identity: SharedComputerSetup.MonitorIdentity?
        if let vendor = record?.fingerprint.vendorID, let serial = record?.fingerprint.serialNumber,
           vendor > 0, !serial.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            identity = .init(vendorID: vendor, serialNumber: serial)
        } else { identity = nil }
        let setup = SharedComputerSetup(id: setupID, revision: revision, monitorName: draft.monitor,
                                        monitorIdentity: identity, computers: profiles)
        Task { if await model.saveSharedSetup(setup) { onClose() } }
    }

    private func resolveInput(_ name: String) -> (transport: DDCInputTransport, code: Int)? {
        for mode in DDCInputTransport.allCases {
            if let input = mode.inputs.first(where: { $0.name == name }) {
                return (mode, input.code)
            }
        }
        return nil
    }

    /// Existing settings are suggestions for review, never an automatic name-based merge.
    private func prefillExisting(peerID: UUID) {
        if let directory = try? SettingsStore.defaultDirectory(),
           let data = try? Data(contentsOf: directory.appendingPathComponent("shared-setup-applied.json")),
           let previous = try? JSONDecoder().decode(SharedComputerSetup.self, from: data),
           Set(previous.computers.map(\.peerID)) == Set([pairing.localID, peerID]),
           previous.revision < UInt64.max {
            setupID = previous.id
            revision = previous.revision + 1
            draft.monitor = previous.monitorName
            if let local = previous.computers.first(where: { $0.peerID == pairing.localID }) {
                draft.localName = local.name
            }
            if let remote = previous.computers.first(where: { $0.peerID == peerID }) {
                draft.otherName = remote.name
            }
        }
        let candidates = model.settings.hotkeyShortcuts.inputSwitchBindings
        let local = candidates.filter {
            $0.availabilityPeerID == nil && ($0.destinationName ?? "")
                .localizedCaseInsensitiveCompare(draft.localName) == .orderedSame
        }
        let remote = candidates.filter { $0.availabilityPeerID == peerID.uuidString }
        let existing: [InputSwitchBinding?] = [local.count == 1 ? local[0] : nil,
                                                remote.count == 1 ? remote[0] : nil]
        var chosen: [Int?] = [nil, nil]
        for index in 0...1 {
            guard let binding = existing[index] else { continue }
            if let name = binding.effectiveTransport.inputs.first(where: { $0.code == binding.inputCode })?.name {
                if index == 0 { draft.localInput = name } else { draft.otherInput = name }
            }
            if let peripheral = binding.peripherals {
                if peripheral.keyboardName == draft.keyboard { draft.keyboardSlots[index] = peripheral.keyboardSlot }
                if peripheral.mode == .independent && peripheral.mouseName == draft.mouse { draft.mouseSlots[index] = peripheral.mouseSlot }
            }
            chosen[index] = (1...9).first { HotkeyDigitChords.binding(forDigit: $0) == binding.binding }
        }
        let free = (1...9).filter {
            !model.inputSwitchHotkeyConflicts(HotkeyDigitChords.binding(forDigit: $0), excludingInputSwitchID: nil)
        }
        var used = Set(chosen.compactMap { $0 })
        for index in 0...1 where chosen[index] == nil {
            if let next = free.first(where: { !used.contains($0) }) { chosen[index] = next; used.insert(next) }
        }
        shortcutsReady = chosen.allSatisfy { $0 != nil } && Set(chosen.compactMap { $0 }).count == 2
        if shortcutsReady { digits = chosen.compactMap { $0 }; draft.shortcuts = digits.map(HotkeyDigitChords.label(forDigit:)) }
    }
}
#endif
