#if os(macOS)
import AppKit
import Combine
import SwiftUI
import TopologyCore

/// Menu-bar-first entry point (PRD UX-001). `LSUIElement` keeps it out of the Dock. The menu bar AND
/// the Settings window are both AppKit-managed by `AppDelegate`: SwiftUI's `MenuBarExtra` mis-anchors
/// its pop-out across multiple displays, and a menu-bar app can't reliably surface SwiftUI's `Settings`
/// scene through the responder chain — so the delegate hosts `SettingsView` in its own `NSWindow` and
/// owns the shared `AppModel`. The placeholder scene below only satisfies `App`'s scene requirement;
/// if it is ever surfaced anyway, its content redirects to the delegate's window.
@main
struct OpenDisplayApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        Self.enforceSingleInstance()
    }

    var body: some Scene {
        Settings { SettingsSceneRedirect() }
    }

    /// Refuses to run alongside another OpenDisplay instance — any copy: a Debug build, the
    /// installed release, a second bundle on disk. Two instances fight over everything this app
    /// manages exactly once per system: the per-display gamma slot, the DDC/I2C bus, the settings
    /// file, the Carbon hotkeys, and the menu-bar item. LaunchServices only prevents re-launching
    /// the *same* bundle, so distinct copies need this runtime guard. The oldest instance (lowest
    /// pid) wins; a newcomer exits here in `App.init`, before the delegate — and therefore
    /// `AppModel` and all its side effects — exists. Deterministic under a simultaneous
    /// multi-launch: every instance that can see an older sibling bows out.
    private static func enforceSingleInstance() {
        #if DEBUG
        // Escape hatch for cross-process test harnesses that intentionally run two copies.
        if ProcessInfo.processInfo.environment["OPENDISPLAY_ALLOW_MULTIPLE"] != nil { return }
        #endif
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let mine = ProcessInfo.processInfo.processIdentifier
        let hasOlderSibling = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .contains { !$0.isTerminated && $0.processIdentifier != mine && $0.processIdentifier < mine }
        guard hasOlderSibling else { return }
        // Don't vanish without a trace: have the instance that's already running open its Settings
        // window, so launching a second copy still puts something on screen.
        DistributedNotificationCenter.default().postNotificationName(
            .openDisplayShowSettingsFromSibling, object: bundleID, userInfo: nil,
            deliverImmediately: true)
        exit(0)
    }
}

/// Content for the placeholder `Settings` scene. Registering the scene gives the app the standard
/// ⌘, "Settings…" behavior, but its SwiftUI-owned window is NOT the real settings UI — that lives in
/// the AppKit window `AppDelegate` owns (see `showSettings`). The delegate intercepts ⌘, before it
/// reaches this scene; this view is the backstop for any other path that surfaces the scene's window
/// (e.g. a `showSettingsWindow:` action): the moment it lands in a window, close that window and open
/// the real one.
private struct SettingsSceneRedirect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { Redirector() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class Redirector: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            // Async so we're not closing the window out from under AppKit mid-setup.
            DispatchQueue.main.async { [weak window] in
                window?.close()
                NotificationCenter.default.post(name: .openDisplayShowSettings, object: nil)
            }
        }
    }
}

/// A key-capable panel keeps keyboard access while retaining a menu-bar-only app.
private final class MenuPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Owns the menu-bar status item, its panel, and the shared model.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var statusItem: NSStatusItem?
    private var menuPanel: NSPanel?
    private var menuLocalMonitor: Any?
    private var menuGlobalMonitor: Any?
    private var settingsWindow: NSWindow?
    private var aboutWindow: NSWindow?
    private var settingsKeyMonitor: Any?
    private var statusPresentationObservation: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Close the pop-out when an action that re-lays-out the displays is picked (e.g. Set as Main):
        // otherwise the open pop-out, anchored to the status item, gets displaced to a random spot when
        // set-main relocates the menu bar to the new main display.
        NotificationCenter.default.addObserver(
            self, selector: #selector(dismissPopover), name: .openDisplayDismissMenu, object: nil)
        // The menu's gear / "Displays & arrangement…" rows ask the delegate to open Settings (we own
        // that window, not SwiftUI) so it reliably appears on the screen the user is looking at.
        NotificationCenter.default.addObserver(
            self, selector: #selector(showSettings), name: .openDisplayShowSettings, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(showAbout), name: .openDisplayShowAbout, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handlePairingRequest(_:)), name: .openSwitchPairingRequestReceived, object: nil)

        // ⌘, is registered by the placeholder SwiftUI `Settings` scene, whose window is not the real
        // settings UI. Intercept the shortcut before the scene sees it and open OUR Settings window —
        // the same one the menu's gear opens. (`SettingsSceneRedirect` backstops non-keyboard paths.)
        settingsKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                  event.charactersIgnoringModifiers == "," else { return event }
            self?.showSettings()
            return nil
        }

        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(showSettings), name: .openDisplayShowSettingsFromSibling,
            object: Bundle.main.bundleIdentifier, suspensionBehavior: .deliverImmediately)

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.imagePosition = .imageLeading
        item.button?.action = #selector(togglePopover(_:))
        item.button?.target = self
        statusItem = item
        statusPresentationObservation = model.$activeInputSwitchBindingID
            .combineLatest(model.$settings, model.$deviceActivityStatus)
            .sink { [weak self] _, _, _ in
                DispatchQueue.main.async {
                    self?.updateStatusItem()
                }
            }
        updateStatusItem()
    }

    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }
        button.image = NSImage(systemSymbolName: "display", accessibilityDescription: "OpenSwitch")
        let active = model.settings.hotkeyShortcuts.inputSwitchBindings.first {
            $0.id == model.activeInputSwitchBindingID
        }
        switch model.settings.menuBarComputerLabel {
        case .iconOnly:
            button.title = ""
            button.toolTip = active.map { "OpenSwitch — keyboard and mouse: \($0.destinationLabel)" }
                ?? "OpenSwitch — waiting for keyboard and mouse activity"
        case .computerNumber:
            let number = active.flatMap { entry in
                (1...9).first { HotkeyDigitChords.binding(forDigit: $0).keyCode == entry.binding.keyCode }
            }.map(String.init) ?? "?"
            button.title = " \(number)"
            button.toolTip = active.map { "OpenSwitch — keyboard and mouse: \($0.destinationLabel)" }
                ?? "OpenSwitch — waiting for keyboard and mouse activity"
        case .computerName:
            button.title = " \(active?.destinationLabel ?? "?")"
            button.toolTip = active.map { "OpenSwitch — keyboard and mouse: \($0.destinationLabel)" }
                ?? "OpenSwitch — waiting for keyboard and mouse activity"
        }
        if let status = model.deviceActivityStatus { button.toolTip = "OpenSwitch — " + status }
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem?.button else { return }
        if menuPanel?.isVisible == true { dismissPopover(); return }
        guard let buttonWindow = button.window, let screen = buttonWindow.screen else { return }
        let hosting = NSHostingController(rootView: MenuBarView().environmentObject(model))
        let view = hosting.view
        let size = view.fittingSize
        guard size.width > 0, size.height > 0 else { return }
        let panel = MenuPanel(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.borderless, .nonactivatingPanel],
                              backing: .buffered, defer: false)
        panel.contentViewController = hosting
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        view.layer?.cornerRadius = 10
        view.layer?.masksToBounds = true
        let anchor = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let visible = screen.visibleFrame
        let x = min(max(anchor.minX, visible.minX), max(visible.minX, visible.maxX - size.width))
        panel.setFrameOrigin(NSPoint(x: x, y: anchor.minY - size.height - 2))
        menuPanel = panel
        panel.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { panel.makeFirstResponder(nil) }
        menuLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self, weak panel, weak buttonWindow] event in
            let consume = MainActor.assumeIsolated {
                if event.type == .keyDown && event.keyCode == 53 { self?.dismissPopover(); return true }
                if event.type != .keyDown && event.window !== panel && event.window !== buttonWindow {
                    self?.dismissPopover()
                }
                return false
            }
            return consume ? nil : event
        }
        menuGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.dismissPopover() }
        }
    }

    @objc private func dismissPopover() {
        menuPanel?.orderOut(nil)
        menuPanel = nil
        if let monitor = menuLocalMonitor { NSEvent.removeMonitor(monitor); menuLocalMonitor = nil }
        if let monitor = menuGlobalMonitor { NSEvent.removeMonitor(monitor); menuGlobalMonitor = nil }
    }

    /// Opening the app while it is already running (Finder, Spotlight, Launchpad) opens Settings.
    /// The menu-bar icon is the app's only standing UI, and macOS can hide it without telling
    /// anyone — behind the notch when the bar is full, or switched off under System Settings →
    /// Menu Bar — which otherwise leaves a running app with nothing to click (issue #44).
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        showSettings()
        return false
    }

    /// Opens (or re-focuses) the Settings window on the screen the user is looking at. Hosting it in our
    /// own `NSWindow` — rather than SwiftUI's `Settings` scene — is the only reliable way to surface and
    /// position it from a menu-bar (LSUIElement) app, especially with "Displays have separate Spaces".
    @objc private func showSettings() {
        dismissPopover()
        let window: NSWindow
        if let existing = settingsWindow {
            window = existing
        } else {
            let hosting = NSHostingController(rootView: SettingsView().environmentObject(model))
            let created = NSWindow(contentViewController: hosting)
            created.title = ""
            created.identifier = NSUserInterfaceItemIdentifier("OpenSwitch.Settings")
            created.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            created.styleMask.insert(.fullSizeContentView)
            created.titlebarAppearsTransparent = true
            created.toolbarStyle = .unifiedCompact
            created.isReleasedWhenClosed = false
            created.contentMinSize = NSSize(width: 800, height: 560)
            created.setContentSize(NSSize(width: 860, height: 620))
            for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                created.standardWindowButton(button)?.isHidden = false
            }
            settingsWindow = created
            window = created
        }
        if let screen = NSScreen.screens.first(where: {
            NSMouseInRect(NSEvent.mouseLocation, $0.frame, false)
        }) ?? NSScreen.main {
            let visible = screen.visibleFrame
            let size = window.frame.size
            window.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2,
                                          y: visible.midY - size.height / 2))
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func resizeAboutWindow(for textSize: OpenSwitchTextSize) {
        guard let window = aboutWindow else { return }
        let height = max(window.contentView?.frame.height ?? 0, 420)
        window.setContentSize(NSSize(width: textSize.aboutWindowWidth, height: height))
    }

    @objc private func handlePairingRequest(_ notification: Notification) {
        guard let requestID = notification.userInfo?["requestID"] as? String,
              let computerName = notification.userInfo?["computerName"] as? String else { return }
        let alert = NSAlert()
        alert.messageText = "Allow \(computerName) to connect?"
        alert.informativeText = "OpenSwitch will securely pair with this Mac so it can check availability and share basic keyboard and mouse status. Keystrokes and mouse actions are never shared."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Allow")
        alert.addButton(withTitle: "Don’t Allow")
        NSApp.activate(ignoringOtherApps: true)
        let request = IncomingOpenSwitchPairing(id: requestID, computerName: computerName)
        if alert.runModal() == .alertFirstButtonReturn {
            model.peerPairing.accept(request)
        } else {
            model.peerPairing.decline(request)
        }
    }

    /// Opens (or re-focuses) the custom About window (`AboutView`) — same ownership story as
    /// Settings: an AppKit window the delegate places on the screen the user is looking at.
    @objc private func showAbout() {
        dismissPopover()
        let window: NSWindow
        if let existing = aboutWindow {
            window = existing
        } else {
            let hosting = NSHostingController(rootView: AboutView().environmentObject(model))
            let created = NSWindow(contentViewController: hosting)
            created.title = "About OpenSwitch"
            created.styleMask = [.titled, .closable]
            created.isReleasedWhenClosed = false
            created.setContentSize(NSSize(width: model.settings.openSwitchTextSize.aboutWindowWidth, height: 420))
            aboutWindow = created
            window = created
        }
        resizeAboutWindow(for: model.settings.openSwitchTextSize)
        if let screen = NSScreen.screens.first(where: {
            NSMouseInRect(NSEvent.mouseLocation, $0.frame, false)
        }) ?? NSScreen.main {
            let visible = screen.visibleFrame
            let size = window.frame.size
            window.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2,
                                          y: visible.midY - size.height / 2))
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// Returns the Mac to a clean default on quit. Reconnecting a display the app turned off is async
    /// (CoreGraphics reconfiguration), so when there's something to undo we defer termination until the
    /// revert completes; otherwise quit immediately. Gamma and the keep-awake assertion are also
    /// restored synchronously by `AppModel`'s `willTerminate` backstop.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard model.needsQuitReversion else { return .terminateNow }
        Task {
            await model.teardownForQuit()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            Task { await OpenDisplayAutomation.handleURL(url) }
        }
    }
}

extension Notification.Name {
    /// Posted by a menu action that re-lays-out the displays (e.g. Set as Main) so the app delegate
    /// closes the pop-out before the menu bar relocates and displaces it.
    static let openDisplayDismissMenu = Notification.Name("OpenDisplayDismissMenu")
    /// Posted by the menu's gear / "Displays & arrangement…" rows to ask the delegate to open the
    /// Settings window (AppKit-owned, so it lands on the screen the user clicked from).
    static let openDisplayShowSettings = Notification.Name("OpenDisplayShowSettings")
    /// Posted across processes by a second copy of the app as it bows out to the one already
    /// running (see `enforceSingleInstance`), asking that one to show its Settings window.
    static let openDisplayShowSettingsFromSibling = Notification.Name("dev.opendisplay.app.showSettings")
    /// Posted by the menu's "About OpenDisplay" item; the delegate owns the About window.
    static let openDisplayShowAbout = Notification.Name("OpenDisplayShowAbout")
    /// Posted when a nearby OpenSwitch Mac asks to establish a trusted peer connection.
    static let openSwitchPairingRequestReceived = Notification.Name("OpenSwitchPairingRequestReceived")
}
#endif
