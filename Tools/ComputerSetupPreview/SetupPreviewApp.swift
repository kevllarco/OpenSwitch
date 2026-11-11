import AppKit
import SwiftUI

@main
struct SetupPreviewApp: App {
    var body: some Scene {
        WindowGroup("OpenSwitch Setup Preview — Sample Data") {
            SetupPreviewSession()
                .onAppear { NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true) }
        }.defaultSize(width: 700, height: 580)
    }
}

struct SetupPreviewSession: View {
    @State private var draft = ComputerSetupDraft(localName: "Mac mini", otherName: "MacBook Air",
        monitor: "LG Ultrawide", keyboard: "MX Mechanical", mouse: "MX Master 3S")
    @State private var connected: UUID?
    @State private var approval = false
    @State private var saveStatus = ""
    private let peer = SetupNearbyMac(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, name: "MacBook Air")

    var body: some View {
        ComputerSetupWizard(draft: $draft, nearbyMacs: [peer], connectedPeerID: connected,
            connectionStatus: connected == nil ? "Preview: connection approval is simulated." : "Preview: approval accepted.",
            inputNames: ["HDMI 1", "HDMI 2", "DisplayPort", "USB-C", "HDMI 1 (LG)", "HDMI 2 (LG)", "DisplayPort 1 (LG)", "DP2 / USB-C (LG, 0xD1)", "USB-C (LG alt, 0xD2)"],
            keyboardOptions: ["MX Mechanical"], mouseOptions: ["MX Master 3S"], saveStatus: saveStatus,
            isSaving: false, onConnect: { _ in approval = true },
            onSave: { saveStatus = "Preview complete. No settings were saved and no hardware was switched." },
            onCancel: { NSApp.terminate(nil) })
        .alert("Preview: request on MacBook Air", isPresented: $approval) {
            Button("Accept") { connected = peer.id }
            Button("Decline", role: .cancel) {}
        } message: { Text("In the real app, this approval appears on the other Mac.") }
    }
}
