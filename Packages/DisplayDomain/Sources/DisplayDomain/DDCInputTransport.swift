/// Input selection is not portable across monitors. LG's alternate channel is explicit opt-in:
/// https://github.com/rockowitz/ddcutil/wiki/Switching-input-source-on-LG-monitors
public enum DDCInputTransport: String, Codable, Hashable, Sendable, CaseIterable {
    case standard
    case lgAlternate

    public var sourceAddress: UInt8 { self == .standard ? 0x51 : 0x50 }
    public var vcpCode: UInt8 { self == .standard ? 0x60 : 0xF4 }
    public var label: String { self == .standard ? "Standard DDC" : "LG alternate" }

    public var inputs: [(name: String, code: Int)] {
        switch self {
        case .standard:
            return [("HDMI 1", 0x11), ("HDMI 2", 0x12), ("DisplayPort 1", 0x0F),
                    ("DisplayPort 2", 0x10), ("USB-C", 0x1B), ("DVI", 0x03), ("VGA", 0x01)]
        case .lgAlternate:
            return [("HDMI 1 (LG)", 0x90), ("HDMI 2 (LG)", 0x91), ("DisplayPort 1 (LG)", 0xD0),
                    ("DP2 / USB-C (LG, 0xD1)", 0xD1), ("USB-C (LG alt, 0xD2)", 0xD2),
                    ("Model-specific input (LG, 0xC0)", 0xC0), ("Model-specific input (LG, 0xE0)", 0xE0)]
        }
    }

    public func inputName(_ code: Int) -> String {
        inputs.first { $0.code == code }?.name ?? "Code \(code)"
    }
}

/// Set-VCP payload for IOAVServiceWriteI2C, whose dataAddress argument sends the source byte.
/// The checksum includes that byte even though the payload does not contain it.
public enum DDCWritePacket {
    public static func bytes(vcp: UInt8, value: Int, sourceAddress: UInt8 = 0x51) -> [UInt8] {
        let high = UInt8((value >> 8) & 0xff)
        let low = UInt8(value & 0xff)
        let checksum: UInt8 = 0x6e ^ sourceAddress ^ 0x84 ^ 0x03 ^ vcp ^ high ^ low
        return [0x84, 0x03, vcp, high, low, checksum]
    }
}
