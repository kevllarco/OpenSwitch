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

/// The setup surface is independent of hardware and network operations. The host supplies
/// discovery, an approved connection and a durable save operation; previews use sample data.
struct ComputerSetupWizard: View {
    @EnvironmentObject private var model: AppModel
    @Binding var draft: ComputerSetupDraft
    let nearbyMacs: [SetupNearbyMac]
    let connectedPeerID: UUID?
    let connectionStatus: String
    let inputNames: [String]
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

    private let titles = ["Your first computer", "Choose your second computer", "Connect your monitor", "Set up your devices", "Review your setup"]

    private var requirement: String? {
        switch step {
        case 0: return draft.localName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Enter a name for this Mac." : nil
        case 1: return connectedPeerID == nil ? "Choose the other Mac and accept its connection request." : nil
        case 2:
            if draft.monitor.isEmpty { return "Select the shared monitor." }
            if draft.localInput.isEmpty { return "Choose the monitor input for \(draft.localName)." }
            if draft.otherInput.isEmpty { return "Choose the monitor input for \(draft.otherName)." }
            if draft.localInput == draft.otherInput { return "Choose a different monitor input for each Mac." }
            return nil
        case 3:
            if draft.keyboardIncluded {
                if draft.keyboard.isEmpty { return "Choose a keyboard or skip keyboard switching." }
                for i in 0...1 where draft.keyboardSlots[i] == 0 { return "Choose the keyboard button for \(i == 0 ? draft.localName : draft.otherName)." }
                if draft.keyboardSlots[0] == draft.keyboardSlots[1] { return "Choose a different keyboard button for each Mac." }
            }
            if draft.mouseIncluded {
                if draft.mouse.isEmpty { return "Choose a mouse or skip mouse switching." }
                for i in 0...1 where draft.mouseSlots[i] == 0 { return "Choose the mouse button for \(i == 0 ? draft.localName : draft.otherName)." }
                if draft.mouseSlots[0] == draft.mouseSlots[1] { return "Choose a different mouse button for each Mac." }
            }
            return nil
        default: return nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Step \(step + 1) of \(titles.count)").foregroundStyle(.secondary)
            Text(titles[step]).font(.title.weight(.semibold))
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch step {
                    case 0:
                        Text("This is the Mac you’re using now. It will be added to your computer list.")
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
                        row(draft.localName) { inputPicker($draft.localInput) }
                        row(draft.otherName) { inputPicker($draft.otherInput) }
                    case 3:
                        Text("Choose each device and the Easy-Switch button that selects each Mac.")
                        if draft.keyboardIncluded {
                            row("Keyboard") { devicePicker(selection: $draft.keyboard, options: keyboardOptions, empty: "No keyboard detected") }
                        }
                        Toggle("Switch keyboard", isOn: $draft.keyboardIncluded).toggleStyle(.switch)
                        if draft.keyboardIncluded {
                            slotRow(draft.localName, selection: $draft.keyboardSlots[0])
                            slotRow(draft.otherName, selection: $draft.keyboardSlots[1])
                        }
                        Divider()
                        if draft.mouseIncluded {
                            row("Mouse") { devicePicker(selection: $draft.mouse, options: mouseOptions, empty: "No mouse detected") }
                        }
                        Toggle("Switch mouse separately", isOn: $draft.mouseIncluded).toggleStyle(.switch)
                            .disabled(!draft.keyboardIncluded || mouseOptions.isEmpty)
                        if draft.mouseIncluded {
                            slotRow(draft.localName, selection: $draft.mouseSlots[0])
                            slotRow(draft.otherName, selection: $draft.mouseSlots[1])
                        } else if draft.keyboardIncluded {
                            Text("When separate mouse switching is off, the mouse follows the keyboard if Logitech Easy-Switch links them.")
                                .foregroundStyle(.secondary)
                        }
                    default:
                        Text("Both computers will appear in the OpenSwitch menu on each Mac.")
                        reviewTable
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
        Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
            GridRow {
                reviewCell("Setting", emphasized: true)
                reviewCell(draft.localName, emphasized: true)
                reviewCell(draft.otherName, emphasized: true)
            }
            .background(.quaternary.opacity(0.6))
            Divider().gridCellColumns(3)
            reviewTableRow("Monitor input", draft.localInput, draft.otherInput)
            Divider().gridCellColumns(3)
            reviewTableRow("Keyboard button", slotText(draft.keyboardSlots[0], included: draft.keyboardIncluded), slotText(draft.keyboardSlots[1], included: draft.keyboardIncluded))
                .background(.quaternary.opacity(0.2))
            Divider().gridCellColumns(3)
            reviewTableRow("Mouse button", slotText(draft.mouseSlots[0], included: draft.mouseIncluded), slotText(draft.mouseSlots[1], included: draft.mouseIncluded))
            Divider().gridCellColumns(3)
            reviewTableRow("Shortcut", draft.shortcuts[0], draft.shortcuts[1])
                .background(.quaternary.opacity(0.2))
        }
        .frame(maxWidth: .infinity)
        .background(.quaternary.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.separator, lineWidth: 0.5))
    }

    private func reviewTableRow(_ label: String, _ local: String, _ other: String) -> some View {
        GridRow {
            reviewCell(label)
            reviewCell(local)
            reviewCell(other)
        }
        .accessibilityElement(children: .combine)
    }

    private func reviewCell(_ value: String, emphasized: Bool = false) -> some View {
        Text(value)
            .fontWeight(emphasized ? .semibold : .regular)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
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
    private func slotRow(_ computer: String, selection: Binding<Int>) -> some View {
        row(computer) {
            Picker("Easy-Switch button", selection: selection) {
                Text("Choose button").tag(0)
                ForEach(1...3, id: \.self) { Text("Button \($0)").tag($0) }
            }.labelsHidden()
        }
    }
    private func slotText(_ slot: Int, included: Bool) -> String { included ? "Button \(slot)" : "Skipped" }
}
#endif
