#if os(macOS)
import AppKit
import OpenDisplayDesignSystem
import SwiftUI

struct SwitchMenuHeader: View {
    var body: some View {
        HStack {
            Text("OpenSwitch").font(.headline)
            Spacer()
        }.padding(.horizontal, 6).padding(.vertical, 4)
    }
}

/// A compact clickable destination with visible hover feedback and a native accessibility label.
struct SwitchMenuRow: View {
    let name: String
    let icon: String
    var shortcut: String? = nil
    var isActive: Bool = false
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .frame(width: 22)
                    .foregroundStyle(hovered && isEnabled
                        ? Color(nsColor: .selectedMenuItemTextColor)
                        : (isActive ? Color.accentColor : Color.primary))
                HStack(spacing: 5) {
                    Text(name).lineLimit(1)
                    if isActive {
                        Image(systemName: "checkmark")
                            .font(.body.weight(.semibold))
                            .accessibilityLabel("Computer receiving keyboard and mouse")
                    }
                }
                .foregroundStyle(hovered && isEnabled
                    ? Color(nsColor: .selectedMenuItemTextColor)
                    : (isActive ? Color.accentColor : Color.primary))
                Spacer()
                if let shortcut {
                    Text(shortcut).appBodyFont()
                        .foregroundStyle(hovered && isEnabled
                            ? Color(nsColor: .selectedMenuItemTextColor) : Color.secondary)
                }
            }
            .foregroundStyle(hovered && isEnabled
                ? Color(nsColor: .selectedMenuItemTextColor) : Color.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8).padding(.vertical, 7).contentShape(Rectangle())
            .background {
                if hovered && isEnabled {
                    SystemSelectionMaterial()
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .allowsHitTesting(false)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

/// AppKit resolves selection material from the active appearance and system accent settings.
private struct SystemSelectionMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .selection
        view.blendingMode = .withinWindow
        view.state = .active
        view.isEmphasized = true
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

#endif
