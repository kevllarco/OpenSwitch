#if os(macOS)
import AppKit
import OpenDisplayDesignSystem
import SwiftUI
import TopologyCore

/// Custom About window, replacing `orderFrontStandardAboutPanel`. The standard panel only shows
/// the icon + version; this one adds what people actually come for — the running version (selectable
/// for bug reports), an update check, and links to the project. Accessibility: semantic fonts (respect
/// the user's text-size setting), real `Link` controls (focusable, VoiceOver-labelled), and the
/// decorative icon hidden from assistive tech.
struct AboutView: View {
    @EnvironmentObject private var model: AppModel

    private static let repo = "https://github.com/aquitaine/OpenDisplay"
    static let releasesURL = URL(string: "https://github.com/kevllarco/OpenSwitch/releases")!

    /// A single project link shown both in this window and in Settings → About, so the two surfaces
    /// can never drift apart on titles, icons, or destinations.
    struct AboutLink: Identifiable {
        let title: String
        let systemImage: String
        let url: URL
        var id: String { title }
    }

    /// The project links AboutView offers, reused verbatim by the Settings → About card.
    static let projectLinks: [AboutLink] = [
        AboutLink(title: "Original OpenDisplay project", systemImage: "globe", url: URL(string: repo)!),
        AboutLink(title: "License (GPL-3.0)", systemImage: "checkmark.seal",
                  url: URL(string: "\(repo)/blob/main/LICENSE")!),
    ]

    /// The running build's marketing version ("0.5.1"), reused by the Settings → About card.
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }
    /// The running build number, reused by the Settings → About card.
    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
    }

    var body: some View {
        VStack(spacing: ODSpacing.sm) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().frame(width: 64, height: 64)
                .accessibilityHidden(true)
            Text("OpenSwitch")
                .font(.title2.weight(.semibold))
            Text("Switch computers and your connected devices.")
                .appBodyFont().foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text("Version \(Self.version) (build \(Self.build))")
                .font(.body.monospacedDigit())
                .textSelection(.enabled)
                .accessibilityLabel("Version \(Self.version), build \(Self.build)")
                .padding(.top, 2)
            UpdateCheckStatusView()
            if !SoftwareUpdater.updatesEnabled {
                Text("Automatic in-app updates are not configured for this build.")
                    .appBodyFont().foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider().padding(.vertical, ODSpacing.xs)

            VStack(alignment: .leading, spacing: ODSpacing.sm) {
                ForEach(Self.projectLinks) { link in
                    aboutLink(link)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, ODSpacing.lg)

            Text("Based on OpenDisplay · © 2026 OpenDisplay contributors")
                .appBodyFont().foregroundStyle(.secondary)
                .padding(.top, ODSpacing.xs)
        }
        .padding(.vertical, ODSpacing.xl)
        .padding(.horizontal, ODSpacing.xl)
        .frame(width: model.settings.openSwitchTextSize.aboutWindowWidth)
        .appBodyFont()
        .appTextSize(model.settings.openSwitchTextSize)
    }

    private func aboutLink(_ link: AboutLink) -> some View {
        Link(destination: link.url) {
            Label {
                Text(link.title).appBodyFont()
            } icon: {
                Image(systemName: link.systemImage).frame(width: 18)
            }
        }
        .foregroundStyle(ODColor.accent)
        .accessibilityHint("Opens in your browser")
    }
}

/// Mirrors the menu's update row: work in flight shows a spinner, everything else is a button that
/// hands over to Sparkle (check → download → verify → install → relaunch). Shared by the About window
/// and the Settings → About card, and it reads the same `SoftwareUpdatePolicy` presentation the menu
/// row does, so all three surfaces say the same thing about the same phase.
struct UpdateCheckStatusView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if !SoftwareUpdater.updatesEnabled {
            Button {
                NSWorkspace.shared.open(AboutView.releasesURL)
            } label: {
                Label("View releases", systemImage: "arrow.down.circle")
            }
            .controlSize(.regular)
            .appBodyFont()
            .accessibilityHint("Opens the OpenSwitch release downloads page")
        } else {
            let presentation = SoftwareUpdatePolicy.presentation(for: model.updatePhase)
            if presentation.showsProgress {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(presentation.combinedTitle).appBodyFont().foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            } else {
                Button {
                    model.checkForUpdates()
                } label: {
                    Label(presentation.combinedTitle, systemImage: presentation.systemImage)
                }
                .controlSize(.regular)
                .appBodyFont()
                .accessibilityHint("Checks for a new version, then downloads and installs it")
            }
        }
    }
}
#endif
