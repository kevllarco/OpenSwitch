#if os(macOS)
import SwiftUI

struct ComputerSetupDraft: Equatable {
    var localName = ""
    var otherName = ""
    var monitor = ""
    var keyboard = ""
    var mouse = ""
    var localInput = ""
    var otherInput = ""
    var keyboardIncluded = true
    var mouseIncluded = true
    var keyboardSlots = [0, 0]
    var mouseSlots = [0, 0]
    var shortcuts = ["⌃⌥⌘1", "⌃⌥⌘2"]
}

struct SetupNearbyMac: Identifiable {
    let id: UUID
    let name: String
}

struct SetupReviewComputer: Identifiable {
    let id: UUID
    let name: String
    let input: String
    let keyboard: String
    let mouse: String
    let shortcut: String
}

/// The setup surface is independent of hardware and network operations. The host supplies
/// discovery, an approved connection and a durable save operation; previews use sample data.
struct ComputerSetupWizard: View {
    @EnvironmentObject private var model: AppModel
    @Binding var draft: ComputerSetupDraft
    let nearbyMacs: [SetupNearbyMac]
    let connectedPeerID: UUID?
    let connectionStatus: String
    let inputNames: [String]
    var existingComputers: [SetupReviewComputer] = []
    var reviewComputers: [SetupReviewComputer] = []
    var keyboardOptions: [String] = []
    var mouseOptions: [String] = []
    let saveStatus: String
    let isSaving: Bool
    let onConnect: (SetupNearbyMac) -> Void
    let onSave: () -> Void
    let onCancel: () -> Void
    var onRetry: (() -> Void)? = nil
    @State private var step = 0
    @State private var editingName = false
    @State private var pendingName = ""
    @FocusState private var nameFieldFocused: Bool

    private var titles: [String] {
        [existingComputers.isEmpty ? "Your first Mac" : "Add another Mac",
         existingComputers.isEmpty ? "Choose your second Mac" : "Choose another Mac",
         "Choose monitor inputs", "Set up your devices", "Review your setup"]
    }

    private var requirement: String? {
        switch step {
        case 0:
            if existingComputers.count >= 9 { return "OpenSwitch supports up to 9 Macs in one setup." }
            return draft.localName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Enter a name for this Mac." : nil
        case 1: return connectedPeerID == nil ? "Choose the other Mac and accept its connection request." : nil
        case 2:
            if draft.monitor.isEmpty { return "Select the shared monitor." }
            if !isAddingToExistingSetup && draft.localInput.isEmpty { return "Choose the monitor input for \(draft.localName)." }
            if draft.otherInput.isEmpty { return "Choose the monitor input for \(draft.otherName)." }
            if !isAddingToExistingSetup && draft.localInput == draft.otherInput { return "Choose a different monitor input for each Mac." }
            if isAddingToExistingSetup && existingComputers.contains(where: { $0.input == draft.otherInput }) {
                return "That monitor input is already assigned to a Mac in this setup."
            }
            return nil
        case 3:
            if draft.keyboardIncluded {
                if draft.keyboard.isEmpty { return "Choose a keyboard or skip keyboard switching." }
                if isAddingToExistingSetup {
                    if draft.keyboardSlots[1] == 0 { return "Choose an unused keyboard button for \(draft.otherName)." }
                    if reservedSlots(for: draft.keyboard, mouse: false).contains(draft.keyboardSlots[1]) { return "That keyboard button is already assigned to a Mac in this setup." }
                } else {
                    for i in 0...1 where draft.keyboardSlots[i] == 0 { return "Choose the keyboard button for \(i == 0 ? draft.localName : draft.otherName)." }
                    if draft.keyboardSlots[0] == draft.keyboardSlots[1] { return "Choose a different keyboard button for each Mac." }
                }
            }
            if draft.mouseIncluded {
                if draft.mouse.isEmpty { return "Choose a mouse or skip mouse switching." }
                if isAddingToExistingSetup {
                    if draft.mouseSlots[1] == 0 { return "Choose an unused mouse button for \(draft.otherName)." }
                    if reservedSlots(for: draft.mouse, mouse: true).contains(draft.mouseSlots[1]) { return "That mouse button is already assigned to a Mac in this setup." }
                } else {
                    for i in 0...1 where draft.mouseSlots[i] == 0 { return "Choose the mouse button for \(i == 0 ? draft.localName : draft.otherName)." }
                    if draft.mouseSlots[0] == draft.mouseSlots[1] { return "Choose a different mouse button for each Mac." }
                }
            }
            return nil
        default: return nil
        }
    }

    private var isAddingToExistingSetup: Bool { !existingComputers.isEmpty }

    private func reservedSlots(for device: String, mouse: Bool) -> Set<Int> {
        Set(existingComputers.compactMap { computer in
            let summary = mouse ? computer.mouse : computer.keyboard
            let prefix = device + " · Button "
            guard summary.hasPrefix(prefix) else { return nil }
            return Int(summary.dropFirst(prefix.count))
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Step \(step + 1) of \(titles.count)").foregroundStyle(.secondary)
            Text(titles[step]).font(.title.weight(.semibold))
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch step {
                    case 0:
                        if existingComputers.isEmpty {
                            Text("This wizard sets up this Mac and connects another Mac. OpenSwitch needs to be running on both.")
                            row("This Mac") {
                                HStack(spacing: 12) {
                                    Text(draft.localName).frame(maxWidth: .infinity, alignment: .trailing)
                                    Button("Edit") {
                                        pendingName = draft.localName
                                        editingName = true
                                    }
                                    .accessibilityLabel("Edit computer name")
                                }
                            }
                            row("Monitor") { Text(draft.monitor.isEmpty ? "No monitor detected" : draft.monitor) }
                            row("Keyboard") { Text(draft.keyboard.isEmpty ? "No keyboard detected" : draft.keyboard) }
                            row("Mouse") { Text(draft.mouse.isEmpty ? "No mouse detected" : draft.mouse) }
                        } else {
                            Text("Your existing setup will be kept. Add one Mac at a time; you can return here to add more.")
                            VStack(spacing: 0) {
                                ForEach(Array(existingComputers.enumerated()), id: \.element.id) { index, computer in
                                    if index > 0 { Divider() }
                                    HStack {
                                        Label(computer.name, systemImage: "desktopcomputer")
                                        Spacer()
                                        Text(computer.input).foregroundStyle(.secondary)
                                    }
                                    .padding(12)
                                }
                            }
                            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
                        }
                    case 1:
                        Text("Open OpenSwitch on the other Mac. Keep both Macs awake and on the same network.")
                        if nearbyMacs.isEmpty { Text("Looking for another Mac…").foregroundStyle(.secondary) }
                        ForEach(nearbyMacs) { mac in
                            row(mac.name) {
                                if connectedPeerID == mac.id { Label("Connected", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                                else { Button("Connect") { onConnect(mac) } }
                            }
                        }
                        Text(connectionStatus).foregroundStyle(.secondary)
                    case 2:
                        Text("Which input on \(draft.monitor) connects to each Mac?")
                        if isAddingToExistingSetup {
                            row(draft.localName) {
                                Text(existingComputers.first(where: { $0.name == draft.localName })?.input ?? draft.localInput)
                            }
                        } else {
                            row(draft.localName) { inputPicker($draft.localInput) }
                        }
                        row(draft.otherName) { inputPicker($draft.otherInput) }
                    case 3:
                        Text(isAddingToExistingSetup
                            ? "Your current Mac settings stay as they are. Choose the devices and Easy-Switch buttons for the new Mac."
                            : "Choose each device and the Easy-Switch button that selects each Mac.")
                        if isAddingToExistingSetup {
                            Label("Existing assignments: \(existingComputers.count) Macs", systemImage: "checkmark.circle")
                                .foregroundStyle(.secondary)
                        }
                        if draft.keyboardIncluded {
                            row("Keyboard") { devicePicker(selection: $draft.keyboard, options: keyboardOptions, empty: "No keyboard detected") }
                        }
                        Toggle(isAddingToExistingSetup ? "Switch keyboard to the new Mac" : "Switch keyboard", isOn: $draft.keyboardIncluded).toggleStyle(.switch)
                        if draft.keyboardIncluded && !isAddingToExistingSetup {
                            slotRow(draft.localName, selection: $draft.keyboardSlots[0])
                        }
                        if draft.keyboardIncluded {
                            slotRow(draft.otherName, selection: $draft.keyboardSlots[1], reserved: isAddingToExistingSetup ? reservedSlots(for: draft.keyboard, mouse: false) : [])
                            if isAddingToExistingSetup && reservedSlots(for: draft.keyboard, mouse: false).count == 3 {
                                Text("All three keyboard buttons are assigned. Turn off keyboard switching for this Mac to continue.")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Divider()
                        if draft.mouseIncluded {
                            row("Mouse") { devicePicker(selection: $draft.mouse, options: mouseOptions, empty: "No mouse detected") }
                        }
                        Toggle(isAddingToExistingSetup ? "Switch mouse to the new Mac separately" : "Switch mouse separately", isOn: $draft.mouseIncluded).toggleStyle(.switch)
                            .disabled(!draft.keyboardIncluded || mouseOptions.isEmpty)
                        if draft.mouseIncluded && !isAddingToExistingSetup {
                            slotRow(draft.localName, selection: $draft.mouseSlots[0])
                        }
                        if draft.mouseIncluded {
                            slotRow(draft.otherName, selection: $draft.mouseSlots[1], reserved: isAddingToExistingSetup ? reservedSlots(for: draft.mouse, mouse: true) : [])
                            if isAddingToExistingSetup && reservedSlots(for: draft.mouse, mouse: true).count == 3 {
                                Text("All three mouse buttons are assigned. Turn off separate mouse switching for this Mac to continue.")
                                    .foregroundStyle(.secondary)
                            }
                        } else if draft.keyboardIncluded {
                            Text("When separate mouse switching is off, the mouse follows the keyboard if Logitech Easy-Switch links them.")
                                .foregroundStyle(.secondary)
                        }
                    default:
                        Text("All computers will appear in the OpenSwitch menu on each Mac.")
                        ScrollView(.horizontal) { reviewTable }
                        if !saveStatus.isEmpty { Text(saveStatus).accessibilityLabel(saveStatus) }
                        if let onRetry { Button("Retry saving", action: onRetry).disabled(isSaving) }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            if step != 4, let onRetry {
                HStack {
                    Text(saveStatus).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button("Retry saving", action: onRetry).disabled(isSaving)
                }
            }
            if let requirement { Text(requirement).foregroundStyle(.secondary) }
            HStack {
                Button("Cancel", action: onCancel).disabled(isSaving)
                Spacer()
                if step > 0 { Button("Back") { step -= 1 }.disabled(isSaving) }
                Button(step == 4 ? (isSaving ? "Saving…" : "Save setup") : "Continue") {
                    if step == 4 { onSave() } else { step += 1 }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(requirement != nil || isSaving)
            }
        }
        .appTextSize(model.settings.openSwitchTextSize)
        .padding(24)
        .frame(minWidth: 620, minHeight: 500)
        .sheet(isPresented: $editingName) {
            VStack(alignment: .leading, spacing: 20) {
                Text("Computer name").font(.title2.weight(.semibold))
                TextField("Computer name", text: $pendingName)
                    .textFieldStyle(.roundedBorder)
                    .focused($nameFieldFocused)
                HStack {
                    Spacer()
                    Button("Cancel") { editingName = false }.keyboardShortcut(.cancelAction)
                    Button("Save") {
                        draft.localName = pendingName.trimmingCharacters(in: .whitespacesAndNewlines)
                        editingName = false
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(pendingName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .appTextSize(model.settings.openSwitchTextSize)
            .padding(24)
            .frame(width: 400)
            .onAppear { nameFieldFocused = true }
        }
        .onChange(of: draft.keyboardIncluded) { _, included in
            if !included { draft.mouseIncluded = false }
        }
    }

    private var reviewTable: some View {
        VStack(spacing: 0) {
            HStack {
                reviewHeader("Computer", width: 150)
                reviewHeader("Monitor input", width: 150)
                reviewHeader("Keyboard", width: 120)
                reviewHeader("Mouse", width: 120)
                reviewHeader("Shortcut", width: 110)
            }
            .background(.quaternary.opacity(0.6))
            ForEach(Array(reviewComputers.enumerated()), id: \.element.id) { index, computer in
                if index > 0 { Divider() }
                HStack {
                    reviewValue(computer.name, width: 150, emphasized: true)
                    reviewValue(computer.input, width: 150)
                    reviewValue(computer.keyboard, width: 120)
                    reviewValue(computer.mouse, width: 120)
                    reviewValue(computer.shortcut, width: 110)
                }
                .background(index.isMultiple(of: 2) ? Color.primary.opacity(0.035) : Color.clear)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .background(.quaternary.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.separator, lineWidth: 0.5))
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    private func reviewHeader(_ value: String, width: CGFloat) -> some View {
        Text(value)
            .fontWeight(.semibold)
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: width, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
    }

    private func reviewValue(_ value: String, width: CGFloat, emphasized: Bool = false) -> some View {
        Text(value)
            .fontWeight(emphasized ? .semibold : .regular)
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: width, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
    }

    private func row<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 24) { Text(title); Spacer(); content().frame(maxWidth: 280, alignment: .trailing) }
            .padding(14).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }
    private func inputPicker(_ selection: Binding<String>) -> some View {
        Picker("Monitor input", selection: selection) {
            Text("Choose input").tag("")
            ForEach(inputNames, id: \.self) { Text($0).tag($0) }
        }.labelsHidden()
    }

    @ViewBuilder
    private func devicePicker(selection: Binding<String>, options: [String], empty: String) -> some View {
        if options.count > 1 {
            Picker("", selection: selection) {
                ForEach(options, id: \.self) { Text(LogitechHandoff.friendlyName($0)).tag($0) }
            }
            .labelsHidden()
            .frame(maxWidth: 320, alignment: .trailing)
        } else if let only = options.first {
            Text(LogitechHandoff.friendlyName(only))
        } else {
            Text(empty).foregroundStyle(.secondary)
        }
    }
    private func slotRow(_ computer: String, selection: Binding<Int>, reserved: Set<Int> = []) -> some View {
        row(computer) {
            Picker("Easy-Switch button", selection: selection) {
                Text(reserved.isEmpty ? "Choose button" : "Choose unused button").tag(0)
                ForEach(1...3, id: \.self) { slot in
                    Text("Button \(slot)").tag(slot).disabled(reserved.contains(slot))
                }
            }.labelsHidden()
        }
    }
    private func slotText(_ slot: Int, included: Bool) -> String { included ? "Button \(slot)" : "Skipped" }
}
#endif
