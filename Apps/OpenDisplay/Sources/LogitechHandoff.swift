#if os(macOS)
import Foundation

/// Runs the bundled MIT-licensed mxswitch helper without a shell. A successful command means
/// only that the HID write was sent; the device disconnects before it can acknowledge the switch.
enum LogitechHandoff {
    private struct Device: Decodable {
        let product: String
        let hosts: Int?
        let channel: Int?
    }
    struct DeviceChoices: Codable, Equatable, Sendable {
        var keyboards: [String] = []
        var mice: [String] = []
        var currentChannels: [String: Int] = [:]
    }

    /// Keep the exact device identifier internally; use a readable label for known Logitech models.
    static func friendlyName(_ name: String) -> String {
        switch name {
        case "MX MCHNCL M": return "MX Mechanical"
        case "MX Master 3S M": return "MX Master 3S"
        default: return name
        }
    }

    /// IORegistry properties are discoverable without opening the HID devices or changing hosts.
    static func detectedDevices() -> DeviceChoices {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/ioreg")
        process.arguments = ["-a", "-r", "-c", "IOHIDDevice"]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return DeviceChoices() }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let rows = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [[String: Any]]
        else { return DeviceChoices() }
        var result = DeviceChoices()
        for row in rows where (row["VendorID"] as? Int) == 0x046D && (row["PrimaryUsagePage"] as? Int) == 1 {
            guard let name = row["Product"] as? String, !name.isEmpty else { continue }
            switch row["PrimaryUsage"] as? Int {
            case 6: result.keyboards.append(name)
            case 2: result.mice.append(name)
            default: break
            }
        }
        result.keyboards = Array(Set(result.keyboards)).sorted()
        result.mice = Array(Set(result.mice)).sorted()
        if let (status, output) = invoke(["--info", "--all", "--config", "/dev/null", "--json"]),
           status == 0, let devices = try? JSONDecoder().decode([Device].self, from: output) {
            for device in devices {
                if let channel = device.channel, (1...3).contains(channel) {
                    result.currentChannels[device.product] = channel
                }
            }
        }
        return result
    }

    private static func invoke(_ arguments: [String]) -> (Int32, Data)? {
        guard let helper = Bundle.main.url(forResource: "desk-switch-hid", withExtension: nil) else { return nil }
        let process = Process()
        let output = Pipe()
        process.executableURL = helper
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        // A stalled HID transaction must not leave switching permanently busy. Terminating the
        // helper leaves the already-sent operations unverified and is surfaced as a failure.
        let timeout = DispatchWorkItem {
            if process.isRunning { process.terminate() }
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 20, execute: timeout)
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        timeout.cancel()
        return (process.terminationStatus, data)
    }

    /// Resolve a single exact name before any monitor change, rejecting ambiguous substring matches.
    static func validate(name: String, slot: Int) -> Bool {
        guard (1...3).contains(slot),
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let (status, output) = invoke(["--info", "--all", "--name", name, "--config", "/dev/null", "--json"]),
              status == 0, let devices = try? JSONDecoder().decode([Device].self, from: output),
              devices.count == 1, devices[0].product == name,
              let hosts = devices[0].hosts, slot <= hosts else { return false }
        return true
    }

    static func send(name: String, slot: Int) -> Bool {
        guard (1...3).contains(slot),
              let (status, _) = invoke([String(slot), "--name", name, "--config", "/dev/null"]) else { return false }
        return status == 0
    }
}
#endif
