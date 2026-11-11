#if os(macOS)
import AppKit
import DisplayDomain
import OpenDisplayDesignSystem
import SwiftUI
import TopologyCore

/// Compact destination-first menu for switching computers.
struct MenuBarView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SwitchMenuHeader()
            revertBanner
            if model.settings.hotkeyShortcuts.inputSwitchBindings.isEmpty {
                SwitchMenuRow(name: "Setup", icon: "plus.circle") { showSettings() }
            } else {
                ForEach(model.settings.hotkeyShortcuts.inputSwitchBindings) { entry in
                    SwitchMenuRow(name: destinationLabel(entry), icon: "desktopcomputer",
                                  shortcut: HotkeyDigitChords.label(for: entry.binding),
                                  isActive: model.activeInputSwitchBindingID == entry.id) {
                        NotificationCenter.default.post(name: .openDisplayDismissMenu, object: nil)
                        Task { await model.switchInputByHotkey(entry) }
                    }
                }
            }
            if model.devicesSplit {
                SwitchMenuRow(name: "Keyboard and mouse split", icon: "exclamationmark.triangle") {
                    showSettings()
                }
            }
            if model.inputHandoffStatus?.hasPrefix("Input switch failed:") == true {
                SwitchMenuRow(name: "Switch failed — open Settings", icon: "exclamationmark.triangle") {
                    showSettings()
                }
            }
            Divider()
            SwitchMenuRow(name: "Settings…", icon: "gearshape") { showSettings() }
            SwitchMenuRow(name: "Quit", icon: "power") { NSApp.terminate(nil) }
        }
        .padding(10)
        .frame(width: model.settings.openSwitchTextSize.menuWidth)
        .appBodyFont()
        .appTextSize(model.settings.openSwitchTextSize)
        .task { await model.refreshActiveKVMState() }
    }

    private func destinationLabel(_ entry: InputSwitchBinding) -> String {
        let name = entry.destinationName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let localName = Host.current().localizedName ?? ProcessInfo.processInfo.hostName
        return !name.isEmpty && name.localizedCaseInsensitiveCompare(localName) == .orderedSame
            ? "\(name) (This Mac)" : entry.destinationLabel
    }

    /// "Keep these settings?" countdown for an arrangement-altering change (Issue 6), shown right below
    /// the icon inside this pop-out — which (via the AppKit status item) now opens on the screen the
    /// user clicked. The change also auto-reverts on its own if nothing is clicked.
    @ViewBuilder
    private var revertBanner: some View {
        if let pending = model.pendingRevert {
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
                .padding(.horizontal, 2)
            }
            .padding(.bottom, 4)
        }
    }

    private func showSettings() {
        NotificationCenter.default.post(name: .openDisplayShowSettings, object: nil)
    }
}

#endif
