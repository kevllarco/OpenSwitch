import SwiftUI

/// A hardware-free preview: buttons only update the sample state and never initiate a switch.
struct SwitchMenuPreview: View {
    @State private var selection = "Choose a computer"
    @State private var activeComputer = "Mac mini"

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SwitchMenuHeader()
            SwitchMenuRow(name: "Mac mini", icon: "desktopcomputer", shortcut: "⌃⌥⌘1",
                          isActive: activeComputer == "Mac mini") {
                selection = "Mac mini selected"
                activeComputer = "Mac mini"
            }
            SwitchMenuRow(name: "MacBook Air", icon: "desktopcomputer", shortcut: "⌃⌥⌘2",
                          isActive: activeComputer == "MacBook Air") {
                selection = "MacBook selected"
                activeComputer = "MacBook Air"
            }
            Divider()
            SwitchMenuRow(name: "Settings…", icon: "gearshape") { selection = "Settings selected" }
            SwitchMenuRow(name: "Quit", icon: "power") { selection = "Quit selected" }
            Text(selection).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 8)
        }
        .padding(10)
        .frame(width: 280)
    }
}

#if !OPENSWITCH_STANDALONE
#Preview("OpenSwitch menu — safe sample") {
    SwitchMenuPreview()
}
#endif
