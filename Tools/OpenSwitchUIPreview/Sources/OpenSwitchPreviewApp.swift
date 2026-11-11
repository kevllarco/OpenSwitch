import SwiftUI

/// UI-only development app. It never creates AppModel or communicates with hardware.
@main
struct OpenSwitchPreviewApp: App {
    var body: some Scene {
        WindowGroup("OpenSwitch UI Preview") {
            SwitchMenuPreview()
                .padding(24)
        }
        .windowResizability(.contentSize)
    }
}
