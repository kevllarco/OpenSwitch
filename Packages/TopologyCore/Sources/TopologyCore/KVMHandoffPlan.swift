import Foundation

/// An explicit user-configured target. Device slots are independent: matching slot numbers across
/// devices is common but not guaranteed. The monitor input value belongs to the chosen transport.
public struct KVMHandoffDestination: Equatable, Sendable {
    public let monitorID: String
    public let monitorInput: Int
    public let keyboardSlot: Int?
    public let mouseSlot: Int?

    public init(monitorID: String, monitorInput: Int, keyboardSlot: Int?, mouseSlot: Int?) {
        self.monitorID = monitorID
        self.monitorInput = monitorInput
        self.keyboardSlot = keyboardSlot
        self.mouseSlot = mouseSlot
    }
}

public enum KVMPeripheralMode: String, Codable, Hashable, Sendable, CaseIterable {
    case independent
    case keyboardLinked
    case monitorOnly
}

public enum KVMHandoffStep: Equatable, Sendable {
    case monitor(id: String, input: Int)
    case mouse(slot: Int)
    case keyboard(slot: Int)
}

public enum KVMHandoffPlanError: Error, Equatable {
    case missingMonitor
    case invalidInput
    case missingMouseSlot
    case missingKeyboardSlot
    case invalidSlot
}

/// Plans only. Execution must report each operation independently: a sent HID or DDC command
/// is not proof of physical handoff. No retries or guessed destinations are authorized here.
public enum KVMHandoffPlan {
    public static func steps(to destination: KVMHandoffDestination,
                             mode: KVMPeripheralMode) throws -> [KVMHandoffStep] {
        guard !destination.monitorID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw KVMHandoffPlanError.missingMonitor
        }
        guard (0...0xFFFF).contains(destination.monitorInput) else {
            throw KVMHandoffPlanError.invalidInput
        }
        var steps: [KVMHandoffStep] = [.monitor(id: destination.monitorID, input: destination.monitorInput)]
        if mode == .monitorOnly { return steps }
        if mode == .independent {
            guard let mouse = destination.mouseSlot else { throw KVMHandoffPlanError.missingMouseSlot }
            guard (1...3).contains(mouse) else { throw KVMHandoffPlanError.invalidSlot }
            steps.append(.mouse(slot: mouse))
        }
        guard let keyboard = destination.keyboardSlot else { throw KVMHandoffPlanError.missingKeyboardSlot }
        guard (1...3).contains(keyboard) else { throw KVMHandoffPlanError.invalidSlot }
        steps.append(.keyboard(slot: keyboard))
        return steps
    }
}

/// Optional per-shortcut settings; absent on older monitor-only bindings.
public struct KVMPeripheralConfiguration: Hashable, Codable, Sendable {
    public var mode: KVMPeripheralMode
    public var mouseName: String
    public var keyboardName: String
    public var mouseSlot: Int
    public var keyboardSlot: Int

    public init(mode: KVMPeripheralMode, mouseName: String, keyboardName: String,
                mouseSlot: Int, keyboardSlot: Int) {
        self.mode = mode
        self.mouseName = mouseName
        self.keyboardName = keyboardName
        self.mouseSlot = mouseSlot
        self.keyboardSlot = keyboardSlot
    }
}
