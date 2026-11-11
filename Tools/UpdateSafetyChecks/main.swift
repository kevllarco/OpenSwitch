import AppKit
import Foundation
import TopologyCore

extension Notification.Name {
    static let openDisplayDismissMenu = Notification.Name("OpenDisplayDismissMenu")
}

@main struct UpdateSafetyChecks {
    @MainActor static func main() {
        precondition(!SoftwareUpdater.updatesEnabled, "OpenSwitch must not use an upstream update feed")
        let enabledPreferences = AutomaticUpdateBehavior(checksForUpdates: true, downloadsAndInstalls: true)
        let updater = SoftwareUpdater(behavior: enabledPreferences)
        func assertSparkleNotCreated() {
            let storage = Mirror(reflecting: updater).children.first { $0.label?.contains("updaterController") == true }
            guard let storage else { fatalError("Unable to inspect updater storage") }
            let value = Mirror(reflecting: storage.value)
            precondition(value.displayStyle == .optional && value.children.isEmpty,
                         "Sparkle must not start while updates are disabled")
        }
        assertSparkleNotCreated()
        updater.apply(enabledPreferences)
        updater.checkForUpdates()
        assertSparkleNotCreated()
        precondition(updater.phase == .idle)
        print("Updates disabled: startup, automatic settings, and manual checks do not create a Sparkle updater.")
    }
}
