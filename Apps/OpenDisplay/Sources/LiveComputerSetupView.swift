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
    @State private var currentSetup: SharedComputerSetup?

    private var existingComputerIDs: Set<UUID> {
        Set(currentSetup?.computers.map(\.peerID) ?? [])
    }

    private var reviewComputers: [SetupReviewComputer] {
        var profiles = currentSetup?.computers ?? []
        let localInput = resolveInput(draft.localInput)
        if currentSetup == nil, let localInput {
            let local = SharedComputerSetup.Computer(peerID: pairing.localID, name: draft.localName,
                inputCode: localInput.code, transport: localInput.transport,
                keyboard: draft.keyboardIncluded ? .init(name: draft.keyboard, slot: draft.keyboardSlots[0]) : nil,
                mouse: draft.mouseIncluded ? .init(name: draft.mouse, slot: draft.mouseSlots[0]) : nil,
                shortcut: HotkeyDigitChords.binding(forDigit: digits[safe: 0] ?? 1))
            insert(local, into: &profiles)
        }
        if let selectedPeerID, let input = resolveInput(draft.otherInput) {
            let remote = SharedComputerSetup.Computer(peerID: selectedPeerID, name: draft.otherName,
                inputCode: input.code, transport: input.transport,
                keyboard: draft.keyboardIncluded ? .init(name: draft.keyboard, slot: draft.keyboardSlots[1]) : nil,
                mouse: draft.mouseIncluded ? .init(name: draft.mouse, slot: draft.mouseSlots[1]) : nil,
                shortcut: HotkeyDigitChords.binding(forDigit: digits[safe: 1] ?? 2))
            insert(remote, into: &profiles)
        }
        return profiles.map { computer in
            SetupReviewComputer(id: computer.peerID, name: computer.name,
                input: inputName(for: computer),
                keyboard: computer.keyboard.map { "\($0.name) · Button \($0.slot)" } ?? "Skipped",
                mouse: computer.mouse.map { "\($0.name) · Button \($0.slot)" } ?? "Skipped",
                shortcut: HotkeyDigitChords.label(for: computer.shortcut) ?? "Custom")
        }
    }

    var body: some View {
        ComputerSetupWizard(draft: $draft,
            nearbyMacs: pairing.nearbyComputers.compactMap { computer in
                guard let id = computer.peerID, id != pairing.localID, !existingComputerIDs.contains(id) else { return nil }
                return SetupNearbyMac(id: id, name: computer.name)
            }, connectedPeerID: selectedPeerID,
            connectionStatus: pairing.pairingStatus ?? "Looking for another Mac…",
            inputNames: DDCInputTransport.allCases.flatMap { $0.inputs.map(\.name) },
            existingComputers: existingComputersForReview,
            reviewComputers: reviewComputers,
            keyboardOptions: keyboardOptions, mouseOptions: mouseOptions,
            saveStatus: model.sharedSetupSaveStatus ?? localError, isSaving: model.isSavingSharedSetup,
            onConnect: connect, onSave: save, onCancel: onClose,
            onRetry: model.hasPendingSharedSetup ? {
                Task { if await model.retrySharedSetup() { onClose() } }
            } : nil)
        .task {
            model.refreshPendingSharedSetup()
            draft.localName = Host.current().localizedName ?? ProcessInfo.processInfo.hostName
            currentSetup = loadCurrentSetup()
            if let display = model.displays.first(where: { $0.displayClass != .builtIn && $0.displayClass != .virtual }) {
                draft.monitor = model.displayName(for: display)
            }
            if let currentSetup {
                setupID = currentSetup.id
                revision = currentSetup.revision < UInt64.max ? currentSetup.revision + 1 : currentSetup.revision
                draft.monitor = currentSetup.monitorName
                if let local = currentSetup.computers.first(where: { $0.peerID == pairing.localID }) {
                    draft.localName = local.name
                    draft.localInput = inputName(for: local)
                    if let digit = (1...9).first(where: { HotkeyDigitChords.binding(forDigit: $0) == local.shortcut }) {
                        digits = [digit, 2]
                        draft.shortcuts = digits.map(HotkeyDigitChords.label(forDigit:))
                    }
                    if let keyboard = local.keyboard {
                        draft.keyboard = keyboard.name
                        draft.keyboardSlots[0] = keyboard.slot
                        draft.keyboardIncluded = true
                    } else { draft.keyboardIncluded = false }
                    if let mouse = local.mouse {
                        draft.mouse = mouse.name
                        draft.mouseSlots[0] = mouse.slot
                        draft.mouseIncluded = true
                    } else { draft.mouseIncluded = false }
                }
            }
            let devices = await Task.detached(priority: .utility) { LogitechHandoff.detectedDevices() }.value
            let savedDevices = model.settings.hotkeyShortcuts.inputSwitchBindings.compactMap(\.peripherals)
            keyboardOptions = Array(Set(devices.keyboards + savedDevices.map(\.keyboardName).filter { !$0.isEmpty })).sorted()
            mouseOptions = Array(Set(devices.mice + savedDevices.map(\.mouseName).filter { !$0.isEmpty })).sorted()
            if draft.keyboard.isEmpty { draft.keyboard = keyboardOptions.count == 1 ? keyboardOptions[0] : "" }
            if draft.mouse.isEmpty { draft.mouse = mouseOptions.count == 1 ? mouseOptions[0] : "" }
            if currentSetup == nil {
                draft.keyboardIncluded = !keyboardOptions.isEmpty
                draft.mouseIncluded = draft.keyboardIncluded && !mouseOptions.isEmpty
            } else {
                draft.keyboardIncluded = !keyboardOptions.isEmpty
                draft.mouseIncluded = draft.keyboardIncluded && !mouseOptions.isEmpty
                draft.keyboardSlots[1] = 0
                draft.mouseSlots[1] = 0
            }
            let free = (1...9).filter { !model.inputSwitchHotkeyConflicts(HotkeyDigitChords.binding(forDigit: $0), excludingInputSwitchID: nil) }
            if currentSetup == nil {
                if free.count >= 2 { digits = Array(free.prefix(2)) }
                shortcutsReady = free.count >= 2
                draft.shortcuts = digits.map(HotkeyDigitChords.label(forDigit:))
            } else {
                shortcutsReady = free.count >= 1 && currentSetup?.computers.contains(where: { $0.peerID == pairing.localID }) == true
            }
            pairing.discoverNearbyComputers()
            if currentSetup == nil, let peerID = pairing.pairedPeerID {
                selectedPeerID = peerID
                draft.otherName = pairing.pairedPeerName ?? ""
                prefillExisting(peerID: peerID)
            }
        }
        .onChange(of: pairing.pairedPeerID) { _, id in
            if let id, let name = pairing.pairedPeerName {
                selectPeer(id: id, name: name)
            }
        }
    }

    private func connect(_ computer: SetupNearbyMac) {
        if pairing.pairedPeerID == computer.id || pairing.trustedPeerIDs.contains(computer.id) {
            selectPeer(id: computer.id, name: computer.name)
        } else if let discovered = pairing.nearbyComputers.first(where: { $0.peerID == computer.id }) {
            pairing.connect(to: discovered)
        }
    }

    private func selectPeer(id: UUID, name: String) {
        if selectedPeerID != id {
            draft.otherInput = ""
            draft.keyboardSlots[1] = 0
            draft.mouseSlots[1] = 0
        }
        selectedPeerID = id
        draft.otherName = name
        prefillExisting(peerID: id)
    }

    private func save() {
        guard shortcutsReady else {
            localError = isExtendingSetup
                ? "A free shortcut is required for the new Mac. Free one and reopen setup."
                : "Two available shortcuts are required. Free a shortcut and reopen setup."
            return
        }
        guard let selectedPeerID, let otherInput = resolveInput(draft.otherInput) else { return }
        var profiles = currentSetup?.computers ?? []
        let remote = SharedComputerSetup.Computer(peerID: selectedPeerID, name: draft.otherName,
            inputCode: otherInput.code, transport: otherInput.transport,
            keyboard: draft.keyboardIncluded ? .init(name: draft.keyboard, slot: draft.keyboardSlots[1]) : nil,
            mouse: draft.mouseIncluded ? .init(name: draft.mouse, slot: draft.mouseSlots[1]) : nil,
            shortcut: HotkeyDigitChords.binding(forDigit: digits[1]))
        if currentSetup == nil {
            guard let localInput = resolveInput(draft.localInput) else { return }
            let local = SharedComputerSetup.Computer(peerID: pairing.localID, name: draft.localName,
                inputCode: localInput.code, transport: localInput.transport,
                keyboard: draft.keyboardIncluded ? .init(name: draft.keyboard, slot: draft.keyboardSlots[0]) : nil,
                mouse: draft.mouseIncluded ? .init(name: draft.mouse, slot: draft.mouseSlots[0]) : nil,
                shortcut: HotkeyDigitChords.binding(forDigit: digits[0]))
            insert(local, into: &profiles)
        }
        insert(remote, into: &profiles)
        let display = model.displays.first { model.displayName(for: $0) == draft.monitor && $0.displayClass == .external }
        let record = display.flatMap { model.records[$0.recordID] ?? model.registryKnownRecords[$0.recordID] }
        let identity: SharedComputerSetup.MonitorIdentity?
        if let vendor = record?.fingerprint.vendorID, let serial = record?.fingerprint.serialNumber,
           vendor > 0, !serial.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            identity = .init(vendorID: vendor, serialNumber: serial)
        } else { identity = currentSetup?.monitorIdentity }
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

    private var existingComputersForReview: [SetupReviewComputer] {
        guard let currentSetup else { return [] }
        return currentSetup.computers.map { computer in
            SetupReviewComputer(id: computer.peerID, name: computer.name,
                input: inputName(for: computer),
                keyboard: computer.keyboard.map { "\($0.name) · Button \($0.slot)" } ?? "Skipped",
                mouse: computer.mouse.map { "\($0.name) · Button \($0.slot)" } ?? "Skipped",
                shortcut: HotkeyDigitChords.label(for: computer.shortcut) ?? "Custom")
        }
    }

    private func loadCurrentSetup() -> SharedComputerSetup? {
        guard let directory = try? SettingsStore.defaultDirectory(),
              let data = try? Data(contentsOf: directory.appendingPathComponent("shared-setup-applied.json")) else { return nil }
        return try? JSONDecoder().decode(SharedComputerSetup.self, from: data)
    }

    private func inputName(for computer: SharedComputerSetup.Computer) -> String {
        computer.transport.inputs.first(where: { $0.code == computer.inputCode })?.name ?? String(format: "Input 0x%02X", computer.inputCode)
    }

    private func insert(_ computer: SharedComputerSetup.Computer, into computers: inout [SharedComputerSetup.Computer]) {
        if let index = computers.firstIndex(where: { $0.peerID == computer.peerID }) { computers[index] = computer }
        else { computers.append(computer) }
    }

    /// Existing settings are suggestions for review, never an automatic name-based merge.
    private func prefillExisting(peerID: UUID) {
        if let directory = try? SettingsStore.defaultDirectory(),
           let data = try? Data(contentsOf: directory.appendingPathComponent("shared-setup-applied.json")),
           let previous = try? JSONDecoder().decode(SharedComputerSetup.self, from: data),
           previous.computers.contains(where: { $0.peerID == pairing.localID }),
           previous.revision < UInt64.max {
            setupID = previous.id
            revision = previous.revision + 1
            draft.monitor = previous.monitorName
            currentSetup = previous
            if let local = previous.computers.first(where: { $0.peerID == pairing.localID }) { draft.localName = local.name }
            if let remote = previous.computers.first(where: { $0.peerID == peerID }) {
                draft.otherName = remote.name
            } else if let peer = pairing.trustedPeers.first(where: { $0.id == peerID }) {
                draft.otherName = peer.name
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
        for index in (isExtendingSetup ? [1] : [0, 1]) where chosen[index] == nil {
            if let next = free.first(where: { !used.contains($0) }) { chosen[index] = next; used.insert(next) }
        }
        if chosen[0] == nil, let local = currentSetup?.computers.first(where: { $0.peerID == pairing.localID }),
           let digit = (1...9).first(where: { HotkeyDigitChords.binding(forDigit: $0) == local.shortcut }) {
            chosen[0] = digit
        }
        shortcutsReady = isExtendingSetup
            ? chosen[1] != nil
            : chosen.allSatisfy { $0 != nil } && Set(chosen.compactMap { $0 }).count == 2
        if chosen[0] != nil, chosen[1] != nil {
            digits = chosen.compactMap { $0 }
            draft.shortcuts = digits.map(HotkeyDigitChords.label(forDigit:))
        }
    }

    private var isExtendingSetup: Bool { currentSetup?.computers.contains(where: { $0.peerID == pairing.localID }) == true }
}

private extension Collection {
    subscript(safe index: Index) -> Element? { indices.contains(index) ? self[index] : nil }
}
#endif
