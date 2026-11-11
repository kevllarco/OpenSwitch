#if os(macOS)
import AppKit
import CoreGraphicsProvider
import DisplayDomain
import OpenDisplayDesignSystem
import SwiftUI
import TopologyCore

/// Settings for computer switching, appearance, troubleshooting, and app information.
struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var section: SettingsSection? = .computers
    @State private var searchText = ""

    private var visibleSections: [SettingsSection] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return SettingsSection.allCases }
        return SettingsSection.allCases.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.searchTerms.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $section) {
                ForEach(visibleSections) { item in
                    let pointSize = model.settings.openSwitchTextSize.appPointSize ?? 13
                    HStack(spacing: 8) {
                        Image(systemName: item.icon)
                            .font(.system(size: max(16, pointSize)))
                        Text(item.title)
                            .font(.system(size: pointSize, weight: .regular))
                            .lineLimit(1)
                    }
                    .padding(.vertical, max(3, pointSize * 0.25))
                    .tag(item)
                }
                if visibleSections.isEmpty {
                    Text("No settings found")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                }
            }
            .listStyle(.sidebar)
            .searchable(text: $searchText, placement: .sidebar, prompt: "Search settings")
            .searchSuggestions {
                ForEach(SettingsSearchTarget.matches(searchText), id: \.title) { target in
                    Button {
                        section = target.section
                        searchText = ""
                    } label: {
                        Label(target.title, systemImage: target.icon)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 320)
        } detail: {
            switch section ?? .computers {
            case .computers: ComputersSection()
            case .displays: DisplaysSection()
            case .appearance: AppearanceSection()
            case .troubleshooting: TroubleshootingSection()
            case .about: AboutSection()
            }
        }
        .frame(minWidth: 800, idealWidth: 860, minHeight: 560, idealHeight: 620)
        .appBodyFont()
        .appTextSize(model.settings.openSwitchTextSize)
        .navigationSplitViewStyle(.balanced)
    }
}

private enum SettingsSection: String, CaseIterable, Identifiable, Hashable {
    case computers, displays, appearance, troubleshooting, about
    var id: String { rawValue }
    var title: String {
        switch self {
        case .computers: return "Computers"
        case .displays: return "Displays"
        case .appearance: return "Appearance"
        case .troubleshooting: return "Troubleshooting"
        case .about: return "About"
        }
    }
    var searchTerms: String {
        switch self {
        case .computers: "Keyboard mouse shortcut nearby Mac pairing computer switch"
        case .displays: "Brightness contrast volume sharpness red green blue gain resolution refresh Retina colour color temperature mode profile input source power dimming name monitor"
        case .appearance: "Startup launch at login Text size font menu bar label HUD heads up display position style"
        case .troubleshooting: "Status diagnostics export reconnect recovery"
        case .about: "Version updates software update license"
        }
    }
    var icon: String {
        switch self {
        case .computers: return "desktopcomputer"
        case .displays: return "display"
        case .appearance: return "paintbrush"
        case .troubleshooting: return "wrench.and.screwdriver"
        case .about: return "info.circle"
        }
    }
}

private struct SettingsSearchTarget {
    let title: String
    let icon: String
    let section: SettingsSection

    static func matches(_ query: String) -> [Self] {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return [] }
        return all.filter { $0.title.localizedCaseInsensitiveContains(value) }
    }

    private static let all: [Self] = [
        .init(title: "Computers", icon: "desktopcomputer", section: .computers),
        .init(title: "Keyboard and mouse", icon: "keyboard", section: .computers),
        .init(title: "Shortcut", icon: "command", section: .computers),
        .init(title: "Startup", icon: "power", section: .appearance),
        .init(title: "Brightness", icon: "sun.max", section: .displays),
        .init(title: "Contrast", icon: "circle.lefthalf.filled", section: .displays),
        .init(title: "Volume", icon: "speaker.wave.2", section: .displays),
        .init(title: "Resolution", icon: "rectangle.dashed", section: .displays),
        .init(title: "Refresh rate", icon: "arrow.triangle.2.circlepath", section: .displays),
        .init(title: "Colour temperature", icon: "thermometer.sun", section: .displays),
        .init(title: "Colour mode and profile", icon: "paintpalette", section: .displays),
        .init(title: "Input source", icon: "arrow.left.arrow.right", section: .displays),
        .init(title: "Power", icon: "power", section: .displays),
        .init(title: "Software dimming", icon: "sun.min", section: .displays),
        .init(title: "Display name", icon: "textformat", section: .displays),
        .init(title: "Text size", icon: "textformat.size", section: .appearance),
        .init(title: "Menu bar", icon: "menubar.rectangle", section: .appearance),
        .init(title: "Switching HUD", icon: "rectangle.inset.filled", section: .appearance),
        .init(title: "Diagnostics", icon: "stethoscope", section: .troubleshooting),
        .init(title: "App updates", icon: "arrow.down.circle", section: .about),
    ]
}

private struct AppearanceSection: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section("Text size") {
                Picker("App text size", selection: Binding(
                    get: { model.settings.openSwitchTextSize },
                    set: { model.setOpenSwitchTextSize($0) }
                )) {
                    ForEach(OpenSwitchTextSize.allCases, id: \.self) { size in
                        Text(size.title).tag(size)
                    }
                }
            }
            Section("Startup") {
                LaunchAtLoginToggle()
            }
            Section("Menu bar") {
                Picker("Show active computer", selection: Binding(
                    get: { model.settings.menuBarComputerLabel },
                    set: { model.setMenuBarComputerLabel($0) }
                )) {
                    ForEach(MenuBarComputerLabel.allCases, id: \.self) { option in
                        Text(option.title).tag(option)
                    }
                }
            }
            Section("Switching HUD") {
                Toggle("Show when switching", isOn: Binding(
                    get: { model.settings.osdEnabled }, set: { model.setOSDEnabled($0) }))
                if model.settings.osdEnabled {
                    Picker("Style", selection: Binding(
                        get: { model.settings.osdStyle }, set: { model.setOSDStyle($0) })) {
                        Text("Native").tag(OSDStyle.native)
                        Text("Minimal").tag(OSDStyle.minimal)
                        Text("Classic").tag(OSDStyle.classicTahoe)
                    }
                    Picker("Position", selection: Binding(
                        get: { model.settings.osdPosition }, set: { model.setOSDPosition($0) })) {
                        Text("Bottom").tag(OSDPosition.bottomCenter)
                        Text("Center").tag(OSDPosition.center)
                        Text("Top").tag(OSDPosition.topCenter)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct DisplaysSection: View {
    @EnvironmentObject private var model: AppModel

    private var selected: DisplayObservation? {
        model.displays.first { $0.recordID == model.selectedDisplayID }
            ?? model.displays.first { $0.displayClass != .builtIn }
            ?? model.displays.first
    }

    var body: some View {
        VStack(spacing: 0) {
            if model.displays.isEmpty {
                ContentUnavailableView("No displays detected", systemImage: "display.trianglebadge.exclamationmark")
            } else {
                if model.displays.count > 1 {
                    Picker("Display", selection: Binding(
                        get: { selected?.recordID ?? model.displays.first?.recordID },
                        set: { model.selectedDisplayID = $0 })) {
                        ForEach(model.displays, id: \.recordID) { display in
                            Text(model.displayName(for: display)).tag(Optional(display.recordID))
                        }
                    }
                    .padding(.horizontal, 20).padding(.top, 14)
                }
                if let display = selected { DisplayDetailView(display: display) }
            }
        }
    }
}

private struct ComputersSection: View {
    var body: some View {
        Form {
            Section("Computers") {
                InputHotkeySection()
            }
        }
        .formStyle(.grouped)
    }
}

/// Recovery remains available for displays previously managed by an older build.
private struct TroubleshootingSection: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section("Switching status") {
                if let status = model.inputHandoffStatus {
                    Text(status)
                } else if let status = model.deviceActivityStatus {
                    Text(status)
                } else {
                    Text("No switch activity yet.").foregroundStyle(.secondary)
                }
            }
            if !model.managedOffline.isEmpty {
                Section("Display recovery") {
                    Button("Reconnect managed displays") {
                        Task { await model.reconnectAll() }
                    }
                    .disabled(model.busy)
                }
            }
            Section("Diagnostics") {
                DiagnosticsExportSection()
            }
        }
        .formStyle(.grouped)
    }
}

private struct DiagnosticsExportSection: View {
    @EnvironmentObject private var model: AppModel
    @State private var exporting = false
    @State private var showContents = false
    @State private var result: String?

    var body: some View {
        VStack(alignment: .leading, spacing: ODSpacing.sm) {
            Text("Collect display and system information to help investigate a problem. The file is saved to your Desktop and is not sent automatically.")
                .appBodyFont().foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            DisclosureGroup("What’s included", isExpanded: $showContents) {
                VStack(alignment: .leading, spacing: ODSpacing.sm) {
                    ForEach(DiagnosticsBundle.contents, id: \.self) { item in
                        Text("\u{2022} " + item).appBodyFont().foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, ODSpacing.sm)
            }
            HStack(spacing: ODSpacing.sm) {
                Button {
                    exporting = true
                    result = nil
                    Task {
                        let url = await model.exportDiagnostics()
                        exporting = false
                        if let url {
                            result = "Saved \(url.lastPathComponent) to your Desktop."
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        } else {
                            result = "Couldn\u{2019}t write the diagnostics file."
                        }
                    }
                } label: {
                    Label(exporting ? "Collecting\u{2026}" : "Export Diagnostics\u{2026}",
                          systemImage: "square.and.arrow.up")
                }
                .disabled(exporting)
                if exporting { ProgressView().controlSize(.small) }
            }
            if let result { Text(result).appBodyFont().foregroundStyle(.secondary) }
        }
    }
}

private struct AboutSection: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ODSpacing.md) {
                ODCard {
                    AppIdentityRow()
                    ODDivider()
                    if SoftwareUpdater.updatesEnabled {
                        UpdateCheckRow()
                        ODDivider()
                        ODRow("Check for updates automatically") {
                            Toggle("Check for updates automatically", isOn: Binding(
                                get: { model.settings.updateCheckEnabled },
                                set: { model.setUpdateCheckEnabled($0) }))
                                .labelsHidden().toggleStyle(.switch)
                        }
                        ODDivider()
                        ODRow("Install updates automatically") {
                            Toggle("Install updates automatically", isOn: Binding(
                                get: { model.settings.automaticUpdateDownloadEnabled },
                                set: { model.setAutomaticUpdateDownloadEnabled($0) }))
                                .labelsHidden().toggleStyle(.switch)
                                .disabled(!model.settings.updateCheckEnabled)
                        }
                    } else {
                        ODRow("Updates", secondary: "Not configured for this build") { EmptyView() }
                    }
                    ForEach(AboutView.projectLinks) { link in
                        ODDivider()
                        ProjectLinkRow(link: link)
                    }
                }
            }
            .padding(ODSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}

/// App icon, name, and running version/build — the same bundle-info source `AboutView` reads.
private struct AppIdentityRow: View {
    var body: some View {
        ODRow("OpenSwitch", secondary: "Development build \(AboutView.build)") {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().frame(width: 28, height: 28)
                .accessibilityHidden(true)
        } trailing: {
            EmptyView()
        }
        .accessibilityElement(children: .combine)
    }
}

/// The check-for-updates affordance, reusing the same `UpdateCheckStatusView` the About window shows.
private struct UpdateCheckRow: View {
    var body: some View {
        ODRow("Updates") {
            EmptyView()
        } trailing: {
            UpdateCheckStatusView()
        }
    }
}

/// One project link (GitHub, release notes, issues, license) shown as a Settings row.
private struct ProjectLinkRow: View {
    let link: AboutView.AboutLink

    var body: some View {
        ODRow(link.title, action: { NSWorkspace.shared.open(link.url) }) {
            ODGlyphTile(link.systemImage)
        } trailing: {
            Image(systemName: "arrow.up.right").foregroundStyle(.secondary)
        }
        .accessibilityHint("Opens in your browser")
    }
}


#endif
