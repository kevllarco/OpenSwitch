#if canImport(CryptoKit)
import CryptoKit
import Foundation

/// Authenticated payload carried inside the paired Macs' encrypted connection.
public enum SharedSetupWire {
    public static let maximumBytes = 16_384
    public struct Message: Codable, Equatable, Sendable {
        public enum Kind: String, Codable, Sendable { case offer, remove, saved, rejected }
        public var kind: Kind
        public var sender: UUID
        public var recipient: UUID
        public var requestID: UUID
        public var setupID: UUID
        public var revision: UInt64
        public var setup: SharedComputerSetup?

        public init(kind: Kind, sender: UUID, recipient: UUID, requestID: UUID,
                    setupID: UUID, revision: UInt64, setup: SharedComputerSetup?) {
            self.kind = kind; self.sender = sender; self.recipient = recipient
            self.requestID = requestID; self.setupID = setupID; self.revision = revision; self.setup = setup
        }
    }
    private struct Envelope: Codable { var payload: Data; var authentication: Data }
    public enum WireError: Error { case invalidKey, tooLarge, invalidMessage, authenticationFailed }

    public static func encode(_ message: Message, key: Data) throws -> Data {
        guard key.count == 32 else { throw WireError.invalidKey }
        try validate(message)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let payload = try encoder.encode(message)
        let tag = Data(HMAC<SHA256>.authenticationCode(for: payload, using: SymmetricKey(data: key)))
        let result = try encoder.encode(Envelope(payload: payload, authentication: tag))
        guard result.count <= maximumBytes else { throw WireError.tooLarge }
        return result
    }

    public static func decode(_ data: Data, key: Data, sender: UUID, recipient: UUID) throws -> Message {
        guard key.count == 32 else { throw WireError.invalidKey }
        guard data.count <= maximumBytes else { throw WireError.tooLarge }
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        guard HMAC<SHA256>.isValidAuthenticationCode(envelope.authentication, authenticating: envelope.payload,
                                                      using: SymmetricKey(data: key)) else { throw WireError.authenticationFailed }
        let message = try JSONDecoder().decode(Message.self, from: envelope.payload)
        guard message.sender == sender, message.recipient == recipient else { throw WireError.invalidMessage }
        try validate(message)
        return message
    }

    private static func validate(_ message: Message) throws {
        guard message.sender != message.recipient, message.revision > 0 else { throw WireError.invalidMessage }
        if message.kind == .offer {
            guard let setup = message.setup, setup.id == message.setupID,
                  setup.revision == message.revision,
                  setup.computers.contains(where: { $0.peerID == message.sender }),
                  setup.computers.contains(where: { $0.peerID == message.recipient }) else { throw WireError.invalidMessage }
            try setup.validate()
        } else if message.setup != nil { throw WireError.invalidMessage }
    }
}
#endif
