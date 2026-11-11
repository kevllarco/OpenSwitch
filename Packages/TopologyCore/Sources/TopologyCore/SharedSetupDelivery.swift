import Foundation

/// Durable state for a reviewed setup awaiting acknowledgement from its paired Mac.
public struct SharedSetupDelivery: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable { case pending, acknowledged }
    public let setup: SharedComputerSetup
    public let peerID: UUID
    public private(set) var status: Status

    public init(setup: SharedComputerSetup, peerID: UUID) throws {
        try setup.validate()
        guard setup.computers.contains(where: { $0.peerID == peerID }) else {
            throw SharedComputerSetup.ValidationError.missingLocalComputer
        }
        self.setup = setup
        self.peerID = peerID
        self.status = .pending
    }

    /// Ignore stale acknowledgements and acknowledgements from another peer.
    @discardableResult
    public mutating func acknowledge(setupID: UUID, revision: UInt64, from sender: UUID) -> Bool {
        guard setup.id == setupID, setup.revision == revision, sender == peerID else { return false }
        status = .acknowledged
        return true
    }
}

/// The receiving Mac must not replace a newer setup with a delayed retry.
public enum SharedSetupRevisionDecision: Equatable, Sendable {
    case apply, alreadyApplied, rejectOlder, rejectDifferentSetup

    public static func decide(incoming: SharedComputerSetup, applied: SharedComputerSetup?) -> Self {
        guard let applied else { return .apply }
        guard incoming.id == applied.id else { return .rejectDifferentSetup }
        if incoming.revision < applied.revision { return .rejectOlder }
        if incoming.revision == applied.revision {
            return incoming == applied ? .alreadyApplied : .rejectDifferentSetup
        }
        return .apply
    }
}
