import DisplayDomain
import Foundation

/// Portable setup data. Display record IDs are deliberately resolved on each Mac.
public struct SharedComputerSetup: Codable, Hashable, Sendable {
    public static let currentVersion = 1
    public var version: Int
    public var id: UUID
    public var revision: UInt64
    public var monitorName: String
    public var monitorIdentity: MonitorIdentity?
    public var computers: [Computer]

    public init(version: Int = currentVersion, id: UUID = UUID(), revision: UInt64,
                monitorName: String, monitorIdentity: MonitorIdentity? = nil, computers: [Computer]) {
        self.version = version; self.id = id; self.revision = revision
        self.monitorName = monitorName; self.monitorIdentity = monitorIdentity; self.computers = computers
    }

    public struct MonitorIdentity: Codable, Hashable, Sendable {
        public var vendorID: Int
        public var serialNumber: String
        public init(vendorID: Int, serialNumber: String) {
            self.vendorID = vendorID; self.serialNumber = serialNumber
        }

        /// Product IDs can differ across inputs on the same physical monitor.
        public func matches(_ record: DisplayRecord) -> Bool {
            record.displayClass == .external && record.fingerprint.vendorID == vendorID
                && record.fingerprint.serialNumber == serialNumber
        }

        public func uniqueMatch(in records: [DisplayRecordID: DisplayRecord]) -> DisplayRecordID? {
            let matchedIDs = records.filter { self.matches($0.value) }.map(\.key)
            return matchedIDs.count == 1 ? matchedIDs.first : nil
        }
    }

    public struct Computer: Codable, Hashable, Sendable {
        public var peerID: UUID
        public var name: String
        public var inputCode: Int
        public var transport: DDCInputTransport
        public var keyboard: DeviceSlot?
        public var mouse: DeviceSlot?
        public var shortcut: KeyBinding

        public init(peerID: UUID, name: String, inputCode: Int, transport: DDCInputTransport,
                    keyboard: DeviceSlot?, mouse: DeviceSlot?, shortcut: KeyBinding) {
            self.peerID = peerID; self.name = name; self.inputCode = inputCode
            self.transport = transport; self.keyboard = keyboard; self.mouse = mouse; self.shortcut = shortcut
        }
    }

    public struct DeviceSlot: Codable, Hashable, Sendable {
        public var name: String
        public var slot: Int

        public init(name: String, slot: Int) { self.name = name; self.slot = slot }
    }

    public enum ValidationError: Error, Equatable {
        case unsupportedVersion, invalidRevision, invalidMonitor, invalidComputers
        case duplicateComputer, invalidName, invalidInput, invalidDevice, duplicateShortcut, missingLocalComputer
    }

    public func validate() throws {
        guard version == Self.currentVersion else { throw ValidationError.unsupportedVersion }
        guard revision > 0 else { throw ValidationError.invalidRevision }
        guard !monitorName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              monitorName.count <= 128 else { throw ValidationError.invalidMonitor }
        if let identity = monitorIdentity {
            guard identity.vendorID > 0,
                  !identity.serialNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  identity.serialNumber.count <= 128 else { throw ValidationError.invalidMonitor }
        }
        guard (2...9).contains(computers.count) else { throw ValidationError.invalidComputers }
        guard Set(computers.map(\.peerID)).count == computers.count else { throw ValidationError.duplicateComputer }
        guard Set(computers.map(\.shortcut)).count == computers.count else { throw ValidationError.duplicateShortcut }
        for computer in computers {
            guard !computer.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  computer.name.count <= 128 else { throw ValidationError.invalidName }
            guard (0...0xffff).contains(computer.inputCode) else { throw ValidationError.invalidInput }
            for device in [computer.keyboard, computer.mouse].compactMap({ $0 }) {
                guard !device.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      device.name.count <= 128, (1...3).contains(device.slot) else {
                    throw ValidationError.invalidDevice
                }
            }
        }
    }

    /// Resolve only after the caller has identified this Mac's local monitor record.
    public func bindings(localID: UUID, displayID: DisplayRecordID) throws -> [InputSwitchBinding] {
        try validate()
        guard computers.contains(where: { $0.peerID == localID }) else { throw ValidationError.missingLocalComputer }
        return try computers.map { computer in
            guard computer.mouse == nil || computer.keyboard != nil else { throw ValidationError.invalidDevice }
            let peripherals: KVMPeripheralConfiguration?
            if let keyboard = computer.keyboard {
                peripherals = KVMPeripheralConfiguration(
                    mode: computer.mouse == nil ? .keyboardLinked : .independent,
                    mouseName: computer.mouse?.name ?? "", keyboardName: keyboard.name,
                    mouseSlot: computer.mouse?.slot ?? 0, keyboardSlot: keyboard.slot)
            } else {
                peripherals = nil
            }
            return InputSwitchBinding(
                id: "\(id.uuidString):\(computer.peerID.uuidString)", displayID: displayID,
                inputCode: computer.inputCode, binding: computer.shortcut,
                transport: computer.transport == .standard ? nil : computer.transport,
                peripherals: peripherals, destinationName: computer.name,
                availabilityPeerID: computer.peerID == localID ? nil : computer.peerID.uuidString)
        }
    }
}
