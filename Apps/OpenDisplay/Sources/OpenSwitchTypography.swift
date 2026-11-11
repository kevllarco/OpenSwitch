#if os(macOS)
import SwiftUI
import TopologyCore

private struct OpenSwitchTextSizeKey: EnvironmentKey {
    static let defaultValue = OpenSwitchTextSize.systemDefault
}

private extension EnvironmentValues {
    var openSwitchTextSize: OpenSwitchTextSize {
        get { self[OpenSwitchTextSizeKey.self] }
        set { self[OpenSwitchTextSizeKey.self] = newValue }
    }
}

extension OpenSwitchTextSize {
    var menuWidth: CGFloat {
        switch self {
        case .systemDefault: return 320
        case .regular: return 320
        case .large: return 360
        case .extraLarge: return 400
        case .largest: return 460
        }
    }

    var aboutWindowWidth: CGFloat {
        switch self {
        case .systemDefault: return 340
        case .regular: return 340
        case .large: return 380
        case .extraLarge: return 430
        case .largest: return 500
        }
    }

    var inputSheetWidth: CGFloat {
        switch self {
        case .systemDefault: return 520
        case .regular: return 520
        case .large: return 560
        case .extraLarge: return 620
        case .largest: return 680
        }
    }
}

private struct AppTextSizeModifier: ViewModifier {
    let size: OpenSwitchTextSize

    func body(content: Content) -> some View {
        content
            .environment(\.openSwitchTextSize, size)
            .font(size.appPointSize.map { .system(size: $0) } ?? .body)
    }
}

private struct AppBodyFontModifier: ViewModifier {
    @Environment(\.openSwitchTextSize) private var size

    func body(content: Content) -> some View {
        content.font(size.appPointSize.map { .system(size: $0) } ?? .body)
    }
}

extension View {
    func appTextSize(_ size: OpenSwitchTextSize) -> some View {
        modifier(AppTextSizeModifier(size: size))
    }

    func appBodyFont() -> some View {
        modifier(AppBodyFontModifier())
    }
}
#endif
