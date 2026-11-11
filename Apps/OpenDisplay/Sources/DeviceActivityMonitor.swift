#if os(macOS)
import Foundation
import IOKit.hid

struct DeviceActivitySnapshot: Codable, Sendable {
    struct Device: Codable, Sendable {
        let name: String
        let connected: Bool
        let activityAge: TimeInterval?
    }
    let devices: [Device]
}

/// Native, nonexclusive HID observation. Stores only device identity and the time of the last
/// activity, never key codes, text, coordinates, or a history of events.
final class DeviceActivityMonitor: @unchecked Sendable {
    private let lock = NSLock()
    private var configured: Set<String> = []
    private var attached: [UInt64: String] = [:]
    private var lastActivity: [String: TimeInterval] = [:]
    private var manager: IOHIDManager?
    var onChange: (@Sendable () -> Void)?
    private var lastNotification: TimeInterval = 0

    func start() {
        guard manager == nil else { return }
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = manager
        let matches: [[String: Int]] = [2, 6].map {
            [kIOHIDVendorIDKey: 0x046D, kIOHIDDeviceUsagePageKey: 1, kIOHIDDeviceUsageKey: $0]
        }
        IOHIDManagerSetDeviceMatchingMultiple(manager, matches as CFArray)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, result, _, device in
            guard result == kIOReturnSuccess, let context else { return }
            Unmanaged<DeviceActivityMonitor>.fromOpaque(context).takeUnretainedValue().connection(device, added: true)
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
            guard let context else { return }
            Unmanaged<DeviceActivityMonitor>.fromOpaque(context).takeUnretainedValue().connection(device, added: false)
        }, context)
        IOHIDManagerRegisterInputValueCallback(manager, { context, result, _, value in
            guard result == kIOReturnSuccess, let context else { return }
            let element = IOHIDValueGetElement(value)
            let page = IOHIDElementGetUsagePage(element)
            let usage = IOHIDElementGetUsage(element)
            // Only real mouse axes/buttons and keyboard presses count. Ignore vendor reports,
            // releases, LEDs and idle reports. No key usage or value is retained or transmitted.
            guard (page == 7 || page == 9 || (page == 1 && [0x30, 0x31, 0x38].contains(usage))),
                  IOHIDValueGetIntegerValue(value) != 0 else { return }
            let device = IOHIDElementGetDevice(element)
            Unmanaged<DeviceActivityMonitor>.fromOpaque(context).takeUnretainedValue().activity(device)
        }, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    func configure(names: Set<String>) {
        lock.withLock {
            configured = Set(names.filter { !$0.isEmpty })
            lastActivity = lastActivity.filter { configured.contains($0.key) }
        }
    }

    func snapshot() -> DeviceActivitySnapshot {
        lock.withLock {
            let now = ProcessInfo.processInfo.systemUptime
            return DeviceActivitySnapshot(devices: configured.sorted().map { name in
                .init(name: name, connected: attached.values.contains(name),
                      activityAge: lastActivity[name].map { max(0, now - $0) })
            })
        }
    }

    private func connection(_ device: IOHIDDevice, added: Bool) {
        var id: UInt64 = 0
        IORegistryEntryGetRegistryEntryID(IOHIDDeviceGetService(device), &id)
        let name = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String
        lock.withLock {
            if added, let name { attached[id] = name } else { attached.removeValue(forKey: id) }
        }
        onChange?()
    }

    private func activity(_ device: IOHIDDevice) {
        guard let name = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String else { return }
        let notify = lock.withLock {
            guard configured.contains(name) else { return false }
            let now = ProcessInfo.processInfo.systemUptime
            lastActivity[name] = now
            guard now - lastNotification >= 0.5 else { return false }
            lastNotification = now
            return true
        }
        if notify { onChange?() }
    }
}
/// Pure evidence selection, shared by the app and the status regression checks.
enum DeviceActivityOwnership {
    static func owners(names: Set<String>, snapshots: [UUID: DeviceActivitySnapshot],
                       allPeersResponded: Bool) -> [String: UUID] {
        var owners: [String: UUID] = [:]
        for name in names {
            let candidates = snapshots.compactMap { id, snapshot -> (UUID, DeviceActivitySnapshot.Device)? in
                guard let device = snapshot.devices.first(where: { $0.name == name }) else { return nil }
                return (id, device)
            }
            let active = candidates.filter { $0.1.connected && ($0.1.activityAge ?? .infinity) <= 30 && ($0.1.activityAge ?? -1) >= 0 }
                .sorted { ($0.1.activityAge ?? .infinity) < ($1.1.activityAge ?? .infinity) }
            if let first = active.first,
               active.count == 1 || (active[1].1.activityAge ?? .infinity) - (first.1.activityAge ?? 0) > 1 {
                owners[name] = first.0
            } else {
                let connected = candidates.filter { $0.1.connected }
                // Ownership from connection alone needs all configured peers to have answered.
                if connected.count == 1, allPeersResponded {
                    owners[name] = connected[0].0
                }
            }
        }
        return owners
    }
}

#endif
