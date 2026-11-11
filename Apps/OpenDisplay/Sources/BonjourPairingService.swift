#if os(macOS)
import CryptoKit
import Foundation
import Network

struct NearbyOpenSwitchMac: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let peerID: UUID?
    let supportsDeviceInventory: Bool
}

struct IncomingOpenSwitchPairing: Identifiable, Sendable {
    let id: String
    let computerName: String
}

/// Bonjour discovery and the one-time, user-approved ECDH handshake. The resulting random key is
/// kept in Keychain on both Macs and continues to authenticate the existing availability service.
final class BonjourPairingService: @unchecked Sendable {
    static let serviceType = "_openswitch-pair._tcp"

    private struct Packet: Codable, Sendable {
        var kind: String
        var requestID: String
        var peerID: String
        var peerName: String?
        var publicKey: Data?
        var nonce: Data?
        var proof: Data?
        var accepted: Bool?
        var supportsDeviceInventory: Bool?
        var deviceInventory: Data?
    }

    private final class PendingRequest: @unchecked Sendable {
        let connection: NWConnection
        let requestID: String
        let peerID: UUID
        let peerName: String
        let peerPublicKey: Data
        let nonce: Data
        let peerSupportsDeviceInventory: Bool
        var localKey: Curve25519.KeyAgreement.PrivateKey?
        var sessionKey: Data?

        init(connection: NWConnection, requestID: String, peerID: UUID, peerName: String,
             peerPublicKey: Data, nonce: Data, peerSupportsDeviceInventory: Bool) {
            self.connection = connection
            self.requestID = requestID
            self.peerID = peerID
            self.peerName = peerName
            self.peerPublicKey = peerPublicKey
            self.nonce = nonce
            self.peerSupportsDeviceInventory = peerSupportsDeviceInventory
        }
    }

    private final class OutgoingRequest: @unchecked Sendable {
        let connection: NWConnection
        let requestID: String
        let expectedPeerID: UUID?
        let peerSupportsDeviceInventory: Bool
        let localKey: Curve25519.KeyAgreement.PrivateKey
        let nonce: Data
        var sessionKey: Data?

        init(connection: NWConnection, requestID: String, expectedPeerID: UUID?, peerSupportsDeviceInventory: Bool,
             localKey: Curve25519.KeyAgreement.PrivateKey, nonce: Data) {
            self.connection = connection
            self.requestID = requestID
            self.expectedPeerID = expectedPeerID
            self.peerSupportsDeviceInventory = peerSupportsDeviceInventory
            self.localKey = localKey
            self.nonce = nonce
        }
    }

    private let queue = DispatchQueue(label: "dev.openswitch.bonjour-pairing")
    private let localID: UUID
    private let localName: String
    private var listener: NWListener?
    private var browser: NWBrowser?
    private var endpoints: [String: NWEndpoint] = [:]
    private var names: [String: String] = [:]
    private var advertisedIDs: [String: UUID] = [:]
    private var advertisedInventorySupport: [String: Bool] = [:]
    private var pending: [String: PendingRequest] = [:]
    private var outgoing: [String: OutgoingRequest] = [:]

    var onNearbyChanged: (@Sendable ([NearbyOpenSwitchMac]) -> Void)?
    var onIncomingRequest: (@Sendable (IncomingOpenSwitchPairing) -> Void)?
    var onPairingStatus: (@Sendable (String?) -> Void)?
    var onPaired: (@Sendable (UUID, String, Data, LogitechHandoff.DeviceChoices?) -> Bool)?

    init(localID: UUID, localName: String) {
        self.localID = localID
        self.localName = String(localName.prefix(48))
    }

    func startListening() {
        queue.async { [self] in
            guard listener == nil else { return }
            do {
                let newListener = try NWListener(using: .tcp)
                let txt = NWTXTRecord(["name": localName, "id": localID.uuidString,
                                       "inventory": "1"])
                newListener.service = NWListener.Service(name: localName, type: Self.serviceType,
                                                         domain: nil, txtRecord: txt)
                newListener.newConnectionHandler = { [weak self] in self?.receivePairingRequest($0) }
                newListener.stateUpdateHandler = { [weak self] state in
                    if case let .failed(error) = state {
                        self?.onPairingStatus?("Local discovery is unavailable: \(error.localizedDescription)")
                    }
                }
                listener = newListener
                newListener.start(queue: queue)
            } catch {
                onPairingStatus?("Local discovery is unavailable: \(error.localizedDescription)")
            }
        }
    }

    func discover() {
        queue.async { [self] in
            browser?.cancel()
            endpoints.removeAll()
            names.removeAll()
            advertisedIDs.removeAll()
            advertisedInventorySupport.removeAll()
            let newBrowser = NWBrowser(for: .bonjourWithTXTRecord(type: Self.serviceType, domain: nil), using: .tcp)
            newBrowser.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    self?.onPairingStatus?("Searching the local network…")
                case let .waiting(error):
                    self?.onPairingStatus?("Waiting for Local Network access: \(error.localizedDescription)")
                case let .failed(error):
                    self?.onPairingStatus?("Couldn’t find nearby Macs: \(error.localizedDescription)")
                default:
                    break
                }
            }
            newBrowser.browseResultsChangedHandler = { [weak self] results, _ in
                guard let self else { return }
                var nearby: [NearbyOpenSwitchMac] = []
                for result in results {
                    let record: NWTXTRecord? = if case let .bonjour(value) = result.metadata { value } else { nil }
                    let serviceName: String
                    if case let .service(name, _, _, _) = result.endpoint { serviceName = name }
                    else { serviceName = record?["name"] ?? "Nearby Mac" }
                    guard serviceName.localizedCaseInsensitiveCompare(self.localName) != .orderedSame else { continue }
                    let displayName = serviceName.trimmingCharacters(in: .whitespacesAndNewlines)
                    let key = String(describing: result.endpoint)
                    let peerID = record?["id"].flatMap(UUID.init(uuidString:))
                    let supportsInventory = record?["inventory"] == "1"
                    self.endpoints[key] = result.endpoint
                    self.names[key] = displayName
                    self.advertisedIDs[key] = peerID
                    self.advertisedInventorySupport[key] = supportsInventory
                    nearby.append(NearbyOpenSwitchMac(id: key, name: displayName, peerID: peerID,
                                                      supportsDeviceInventory: supportsInventory))
                }
                self.onNearbyChanged?(nearby.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
                if nearby.isEmpty {
                    self.onPairingStatus?(results.isEmpty
                        ? "No nearby OpenSwitch Macs found."
                        : "No other OpenSwitch Mac is available to pair right now.")
                } else {
                    self.onPairingStatus?("Found \(nearby.count) nearby Mac\(nearby.count == 1 ? "" : "s").")
                }
            }
            browser = newBrowser
            newBrowser.start(queue: queue)
        }
    }

    func connect(to computerID: String) {
        queue.async { [self] in
            guard let endpoint = endpoints[computerID],
                  let nonce = Self.randomBytes(count: 32) else {
                onPairingStatus?("That Mac is no longer available. Refresh the nearby list.")
                return
            }
            let expectedID = advertisedIDs[computerID]
            let localKey = Curve25519.KeyAgreement.PrivateKey()
            let requestID = UUID().uuidString
            let connection = NWConnection(to: endpoint, using: .tcp)
            let attempt = OutgoingRequest(connection: connection, requestID: requestID,
                                          expectedPeerID: expectedID,
                                          peerSupportsDeviceInventory: advertisedInventorySupport[computerID] ?? false,
                                          localKey: localKey, nonce: nonce)
            outgoing[requestID] = attempt
            connection.stateUpdateHandler = { [weak self, weak attempt] state in
                guard let self, let attempt else { return }
                switch state {
                case .ready:
                    let packet = Packet(kind: "request", requestID: requestID,
                                        peerID: self.localID.uuidString, peerName: self.localName,
                                        publicKey: localKey.publicKey.rawRepresentation, nonce: nonce,
                                        supportsDeviceInventory: true)
                    self.send(packet, over: connection) { error in
                        if error != nil { self.failOutgoing(requestID, "Couldn’t contact \(self.peerName(for: computerID)).") }
                        else { self.receiveOutgoingResponse(attempt) }
                    }
                    self.onPairingStatus?("Waiting for \(self.peerName(for: computerID)) to accept…")
                case let .failed(error):
                    self.failOutgoing(requestID, "Couldn’t connect to that Mac: \(error.localizedDescription)")
                default: break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + 90) { [weak self] in
                guard self?.outgoing[requestID] != nil else { return }
                self?.failOutgoing(requestID, "The connection request expired.")
            }
        }
    }

    func accept(requestID: String) {
        queue.async { [self] in
            guard let request = pending[requestID] else { return }
            let localKey = Curve25519.KeyAgreement.PrivateKey()
            guard let sessionKey = Self.deriveKey(localKey: localKey, peerPublicKey: request.peerPublicKey,
                                                  nonce: request.nonce, firstID: request.peerID, secondID: localID) else {
                rejectOnQueue(requestID)
                onPairingStatus?("Couldn’t securely establish the connection.")
                return
            }
            request.localKey = localKey
            request.sessionKey = sessionKey
            let packet = Packet(kind: "decision", requestID: requestID, peerID: localID.uuidString,
                                peerName: localName, publicKey: localKey.publicKey.rawRepresentation,
                                proof: Self.proof(key: sessionKey, requestID: requestID,
                                                  initiator: request.peerID, responder: localID, stage: "accepted"),
                                accepted: true)
            send(packet, over: request.connection) { [weak self, weak request] error in
                guard let self, let request, error == nil else {
                    self?.pending.removeValue(forKey: requestID)
                    request?.connection.cancel()
                    self?.onPairingStatus?("The connection request ended before it could be secured.")
                    return
                }
                self.receiveIncomingConfirmation(request)
            }
        }
    }

    func reject(requestID: String) {
        queue.async { [self] in rejectOnQueue(requestID) }
    }

    private func receivePairingRequest(_ connection: NWConnection) {
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + 120) { connection.cancel() }
        receivePacket(over: connection) { [weak self] packet in
            guard let self, let packet, packet.kind == "request",
                  let peerID = UUID(uuidString: packet.peerID), peerID != self.localID,
                  let name = packet.peerName, !name.isEmpty, name.count <= 64,
                  let publicKey = packet.publicKey, publicKey.count == 32,
                  let nonce = packet.nonce, nonce.count == 32,
                  UUID(uuidString: packet.requestID) != nil,
                  self.pending.count < 8 else {
                connection.cancel()
                return
            }
            let request = PendingRequest(connection: connection, requestID: packet.requestID,
                                          peerID: peerID, peerName: name, peerPublicKey: publicKey, nonce: nonce,
                                          peerSupportsDeviceInventory: packet.supportsDeviceInventory == true)
            self.pending[packet.requestID] = request
            self.onIncomingRequest?(IncomingOpenSwitchPairing(id: packet.requestID, computerName: name))
            self.queue.asyncAfter(deadline: .now() + 120) { [weak self, weak request] in
                guard let self, let request, self.pending[packet.requestID] === request else { return }
                self.pending.removeValue(forKey: packet.requestID)
                request.connection.cancel()
            }
        }
    }

    private func rejectOnQueue(_ requestID: String) {
        guard let request = pending.removeValue(forKey: requestID) else { return }
        let packet = Packet(kind: "decision", requestID: requestID, peerID: localID.uuidString,
                            peerName: localName, accepted: false)
        send(packet, over: request.connection) { _ in request.connection.cancel() }
    }

    private func receiveIncomingConfirmation(_ request: PendingRequest) {
        receivePacket(over: request.connection) { [weak self, weak request] packet in
            guard let self, let request else { return }
            guard self.pending[request.requestID] === request,
                  let key = request.sessionKey, let packet, packet.kind == "confirm",
                  packet.requestID == request.requestID,
                  UUID(uuidString: packet.peerID) == request.peerID,
                  let suppliedProof = packet.proof,
                  HMAC<SHA256>.isValidAuthenticationCode(suppliedProof,
                    authenticating: Self.proofMessage(requestID: request.requestID,
                                                      initiator: request.peerID, responder: self.localID, stage: "confirm",
                                                      deviceInventory: packet.deviceInventory),
                    using: SymmetricKey(data: key)) else {
                self.onPairingStatus?("The connection confirmation was invalid.")
                self.pending.removeValue(forKey: request.requestID)
                request.connection.cancel()
                return
            }
            let remoteDevices = packet.deviceInventory.flatMap { Self.openInventory($0, key: key) }
            let encryptedLocalDevices = request.peerSupportsDeviceInventory
                ? Self.sealInventory(LogitechHandoff.detectedDevices(), key: key) : nil
            let complete = Packet(kind: "complete", requestID: request.requestID,
                                  peerID: self.localID.uuidString,
                                  proof: Self.proof(key: key, requestID: request.requestID,
                                                    initiator: request.peerID, responder: self.localID, stage: "complete",
                                                    deviceInventory: encryptedLocalDevices),
                                  deviceInventory: encryptedLocalDevices)
            self.send(complete, over: request.connection) { [weak self, weak request] error in
                guard let self, let request else { return }
                guard error == nil else {
                    self.pending.removeValue(forKey: request.requestID)
                    request.connection.cancel()
                    return
                }
                guard self.onPaired?(request.peerID, request.peerName, key, remoteDevices) == true else {
                    self.pending.removeValue(forKey: request.requestID)
                    request.connection.cancel()
                    return
                }
                self.pending.removeValue(forKey: request.requestID)
                request.connection.cancel()
                self.onPairingStatus?("Paired with \(request.peerName).")
            }
        }
    }

    private func receiveOutgoingResponse(_ attempt: OutgoingRequest) {
        receivePacket(over: attempt.connection) { [weak self, weak attempt] packet in
            guard let self, let attempt, self.outgoing[attempt.requestID] === attempt,
                  let packet, packet.kind == "decision", packet.requestID == attempt.requestID,
                  let remoteID = UUID(uuidString: packet.peerID),
                  attempt.expectedPeerID == nil || remoteID == attempt.expectedPeerID else {
                self?.failOutgoing(attempt?.requestID ?? "", "The nearby Mac returned an invalid response.")
                return
            }
            guard packet.accepted == true else {
                self.failOutgoing(attempt.requestID, "The connection request was declined.")
                return
            }
            guard let publicKey = packet.publicKey, publicKey.count == 32,
                  let remoteName = packet.peerName, !remoteName.isEmpty,
                  let key = Self.deriveKey(localKey: attempt.localKey, peerPublicKey: publicKey,
                                           nonce: attempt.nonce, firstID: self.localID, secondID: remoteID),
                  let suppliedProof = packet.proof,
                  HMAC<SHA256>.isValidAuthenticationCode(suppliedProof,
                    authenticating: Self.proofMessage(requestID: attempt.requestID,
                                                      initiator: self.localID, responder: remoteID, stage: "accepted"),
                    using: SymmetricKey(data: key)) else {
                self.failOutgoing(attempt.requestID, "Couldn’t verify the accepted connection.")
                return
            }
            attempt.sessionKey = key
            let encryptedLocalDevices = attempt.peerSupportsDeviceInventory
                ? Self.sealInventory(LogitechHandoff.detectedDevices(), key: key) : nil
            let confirm = Packet(kind: "confirm", requestID: attempt.requestID,
                                 peerID: self.localID.uuidString,
                                 proof: Self.proof(key: key, requestID: attempt.requestID,
                                                   initiator: self.localID, responder: remoteID, stage: "confirm",
                                                   deviceInventory: encryptedLocalDevices),
                                 deviceInventory: encryptedLocalDevices)
            self.send(confirm, over: attempt.connection) { [weak self, weak attempt] error in
                guard let self, let attempt, error == nil else {
                    self?.failOutgoing(attempt?.requestID ?? "", "The accepted connection could not be confirmed.")
                    return
                }
                self.receiveOutgoingComplete(attempt, remoteID: remoteID, remoteName: remoteName)
            }
        }
    }

    private func receiveOutgoingComplete(_ attempt: OutgoingRequest, remoteID: UUID, remoteName: String) {
        receivePacket(over: attempt.connection) { [weak self, weak attempt] packet in
            guard let self, let attempt, self.outgoing[attempt.requestID] === attempt,
                  let key = attempt.sessionKey, let packet, packet.kind == "complete",
                  packet.requestID == attempt.requestID,
                  UUID(uuidString: packet.peerID) == remoteID,
                  let suppliedProof = packet.proof,
                  HMAC<SHA256>.isValidAuthenticationCode(suppliedProof,
                    authenticating: Self.proofMessage(requestID: attempt.requestID,
                                                      initiator: self.localID, responder: remoteID, stage: "complete",
                                                      deviceInventory: packet.deviceInventory),
                    using: SymmetricKey(data: key)) else {
                self?.failOutgoing(attempt?.requestID ?? "", "The paired Mac could not be verified.")
                return
            }
            let remoteDevices = packet.deviceInventory.flatMap { Self.openInventory($0, key: key) }
            guard self.onPaired?(remoteID, remoteName, key, remoteDevices) == true else {
                self.failOutgoing(attempt.requestID, "Couldn’t save the secure connection in Keychain.")
                return
            }
            self.outgoing.removeValue(forKey: attempt.requestID)
            attempt.connection.cancel()
            self.onPairingStatus?("Paired with \(remoteName).")
        }
    }

    private func failOutgoing(_ requestID: String, _ message: String) {
        guard let attempt = outgoing.removeValue(forKey: requestID) else { return }
        attempt.connection.cancel()
        onPairingStatus?(message)
    }

    private func peerName(for id: String) -> String {
        names[id.uppercased()] ?? "that Mac"
    }

    private func send(_ packet: Packet, over connection: NWConnection,
                      completion: @escaping @Sendable (NWError?) -> Void) {
        guard let body = try? JSONEncoder().encode(packet), !body.isEmpty, body.count <= 4096 else {
            completion(.posix(.EMSGSIZE))
            return
        }
        var size = UInt32(body.count).bigEndian
        let framed = withUnsafeBytes(of: &size) { Data($0) } + body
        connection.send(content: framed, completion: .contentProcessed { completion($0) })
    }

    private func receivePacket(over connection: NWConnection,
                               completion: @escaping @Sendable (Packet?) -> Void) {
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { header, _, _, error in
            guard error == nil, let header, header.count == 4 else {
                completion(nil); return
            }
            let size = header.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            guard size > 0, size <= 4096 else { completion(nil); return }
            connection.receive(minimumIncompleteLength: Int(size), maximumLength: Int(size)) { body, _, _, error in
                guard error == nil, let body, body.count == Int(size),
                      let packet = try? JSONDecoder().decode(Packet.self, from: body) else {
                    completion(nil); return
                }
                completion(packet)
            }
        }
    }

    private static func deriveKey(localKey: Curve25519.KeyAgreement.PrivateKey,
                                  peerPublicKey: Data, nonce: Data,
                                  firstID: UUID, secondID: UUID) -> Data? {
        guard nonce.count == 32,
              let publicKey = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: peerPublicKey),
              let secret = try? localKey.sharedSecretFromKeyAgreement(with: publicKey) else { return nil }
        let ids = [firstID.uuidString, secondID.uuidString].sorted().joined(separator: ":")
        let derived = secret.hkdfDerivedSymmetricKey(using: SHA256.self, salt: nonce,
            sharedInfo: Data(("OpenSwitch peer v1:" + ids).utf8), outputByteCount: 32)
        return derived.withUnsafeBytes { Data($0) }
    }

    private static func proof(key: Data, requestID: String, initiator: UUID,
                              responder: UUID, stage: String, deviceInventory: Data? = nil) -> Data {
        let message = proofMessage(requestID: requestID, initiator: initiator, responder: responder,
                                   stage: stage, deviceInventory: deviceInventory)
        return Data(HMAC<SHA256>.authenticationCode(for: message, using: SymmetricKey(data: key)))
    }

    private static func proofMessage(requestID: String, initiator: UUID,
                                     responder: UUID, stage: String, deviceInventory: Data? = nil) -> Data {
        var fields = ["OpenSwitch pair v1", requestID, initiator.uuidString, responder.uuidString, stage]
        if let deviceInventory {
            fields.append(SHA256.hash(data: deviceInventory).map { String(format: "%02x", $0) }.joined())
        }
        return Data(fields.joined(separator: ":").utf8)
    }

    private static func sealInventory(_ inventory: LogitechHandoff.DeviceChoices, key: Data) -> Data? {
        guard key.count == 32, let data = try? JSONEncoder().encode(inventory), data.count <= 2048,
              let sealed = try? ChaChaPoly.seal(data, using: SymmetricKey(data: key)) else { return nil }
        return sealed.combined
    }

    private static func openInventory(_ encrypted: Data, key: Data) -> LogitechHandoff.DeviceChoices? {
        guard key.count == 32, let box = try? ChaChaPoly.SealedBox(combined: encrypted),
              let data = try? ChaChaPoly.open(box, using: SymmetricKey(data: key)), data.count <= 2048 else { return nil }
        return try? JSONDecoder().decode(LogitechHandoff.DeviceChoices.self, from: data)
    }

    private static func randomBytes(count: Int) -> Data? {
        var bytes = [UInt8](repeating: 0, count: count)
        guard SecRandomCopyBytes(kSecRandomDefault, count, &bytes) == errSecSuccess else { return nil }
        return Data(bytes)
    }
}
#endif
