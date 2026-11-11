#if os(macOS)
import Foundation
import Network
import TopologyCore

/// Setup transfer uses the same paired TLS credentials as availability checks.
final class SharedSetupTransport: @unchecked Sendable {
    static let serviceType = "_openswitch-cfg._tcp"
    private let queue = DispatchQueue(label: "dev.openswitch.setup-transfer")
    private var listener: NWListener?
    private var connections: [UUID: NWConnection] = [:]
    private var identity: (local: UUID, peer: UUID, key: Data)?
    private var apply: (@Sendable (SharedComputerSetup) async -> Bool)?
    private var remove: (@Sendable (UUID, UInt64) async -> Bool)?

    func setReceiver(_ receiver: @escaping @Sendable (SharedComputerSetup) async -> Bool) {
        queue.async { self.apply = receiver }
    }

    func setRemovalReceiver(_ receiver: @escaping @Sendable (UUID, UInt64) async -> Bool) {
        queue.async { self.remove = receiver }
    }

    func configure(localID: UUID, peerID: UUID?, key: Data?) {
        queue.async { [self] in
            listener?.cancel(); listener = nil
            connections.values.forEach { $0.cancel() }; connections.removeAll()
            identity = nil
            guard let peerID, let key, key.count == 32, localID != peerID else {
                NSLog("OpenSwitch setup listener inactive: paired identity or key unavailable")
                UserDefaults.standard.set("inactive", forKey: "openSwitchSetupListenerDiagnostic")
                return
            }
            identity = (localID, peerID, key)
            guard let server = try? NWListener(using: PeerAvailabilityService.secureParameters(key: key)) else {
                NSLog("OpenSwitch setup listener could not be created")
                UserDefaults.standard.set("creation failed", forKey: "openSwitchSetupListenerDiagnostic")
                return
            }
            server.service = NWListener.Service(name: localID.uuidString, type: Self.serviceType)
            server.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    UserDefaults.standard.set("ready", forKey: "openSwitchSetupListenerDiagnostic")
                    NSLog("OpenSwitch setup listener ready")
                case let .failed(error):
                    UserDefaults.standard.set("failed: \(error.localizedDescription)", forKey: "openSwitchSetupListenerDiagnostic")
                    NSLog("OpenSwitch setup listener failed: %@", error.localizedDescription)
                case let .waiting(error):
                    UserDefaults.standard.set("waiting: \(error.localizedDescription)", forKey: "openSwitchSetupListenerDiagnostic")
                    NSLog("OpenSwitch setup listener waiting: %@", error.localizedDescription)
                default: break
                }
            }
            server.newConnectionHandler = { [weak self] connection in
                guard let self, self.connections.count < 8 else { connection.cancel(); return }
                let token = UUID()
                self.connections[token] = connection
                connection.stateUpdateHandler = { [weak self] state in
                    switch state {
                    case .cancelled, .failed: self?.connections.removeValue(forKey: token)
                    default: break
                    }
                }
                connection.start(queue: self.queue)
                self.queue.asyncAfter(deadline: .now() + 15) { connection.cancel() }
                Self.receive(on: connection) { [weak self] data in
                    guard let self, let current = self.identity,
                          current.local == localID, current.peer == peerID, current.key == key,
                          let data, let message = try? SharedSetupWire.decode(data, key: key, sender: peerID, recipient: localID),
                          message.kind == .offer || message.kind == .remove else {
                        connection.cancel(); return
                    }
                    Task {
                        let saved: Bool
                        if message.kind == .offer, let setup = message.setup, let apply = self.apply {
                            saved = await apply(setup)
                        } else if message.kind == .remove, self.remove != nil {
                            saved = await self.remove?(message.setupID, message.revision) ?? false
                        } else {
                            saved = false
                        }
                        self.queue.async {
                            guard let current = self.identity, current.key == key,
                                  current.peer == peerID, current.local == localID else { connection.cancel(); return }
                            let reply = SharedSetupWire.Message(kind: saved ? .saved : .rejected,
                                sender: localID, recipient: peerID, requestID: message.requestID,
                                setupID: message.setupID, revision: message.revision, setup: nil)
                            guard let encoded = try? SharedSetupWire.encode(reply, key: key) else { connection.cancel(); return }
                            Self.send(encoded, on: connection) { _ in connection.cancel() }
                        }
                    }
                }
            }
            listener = server
            server.start(queue: queue)
        }
    }

    func send(_ setup: SharedComputerSetup) async -> Bool {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                guard let identity else { continuation.resume(returning: false); return }
                let message = SharedSetupWire.Message(kind: .offer, sender: identity.local,
                    recipient: identity.peer, requestID: UUID(), setupID: setup.id,
                    revision: setup.revision, setup: setup)
                guard let data = try? SharedSetupWire.encode(message, key: identity.key) else {
                    continuation.resume(returning: false); return
                }
                let exchange = SharedSetupExchange(queue: queue, message: message, data: data,
                    key: identity.key, continuation: continuation)
                exchange.start()
            }
        }
    }

    func sendRemoval(setupID: UUID, revision: UInt64) async -> Bool {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                guard let identity, revision > 0 else { continuation.resume(returning: false); return }
                let message = SharedSetupWire.Message(kind: .remove, sender: identity.local,
                    recipient: identity.peer, requestID: UUID(), setupID: setupID,
                    revision: revision, setup: nil)
                guard let data = try? SharedSetupWire.encode(message, key: identity.key) else {
                    continuation.resume(returning: false); return
                }
                let exchange = SharedSetupExchange(queue: queue, message: message, data: data,
                    key: identity.key, continuation: continuation)
                exchange.start()
            }
        }
    }

    fileprivate static func send(_ data: Data, on connection: NWConnection,
                                 completion: @escaping @Sendable (Bool) -> Void) {
        guard !data.isEmpty, data.count <= SharedSetupWire.maximumBytes else { completion(false); return }
        var size = UInt32(data.count).bigEndian
        let frame = withUnsafeBytes(of: &size) { Data($0) } + data
        connection.send(content: frame, completion: .contentProcessed { completion($0 == nil) })
    }

    fileprivate static func receive(on connection: NWConnection,
                                    completion: @escaping @Sendable (Data?) -> Void) {
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { header, _, _, error in
            guard error == nil, let header, header.count == 4 else { completion(nil); return }
            let count = header.reduce(0) { ($0 << 8) | Int($1) }
            guard count > 0, count <= SharedSetupWire.maximumBytes else { completion(nil); return }
            connection.receive(minimumIncompleteLength: count, maximumLength: count) { data, _, _, error in
                completion(error == nil && data?.count == count ? data : nil)
            }
        }
    }
}

private final class SharedSetupExchange: @unchecked Sendable {
    let queue: DispatchQueue
    let message: SharedSetupWire.Message
    let data: Data
    let key: Data
    var continuation: CheckedContinuation<Bool, Never>?
    var browser: NWBrowser?
    var connection: NWConnection?

    init(queue: DispatchQueue, message: SharedSetupWire.Message, data: Data, key: Data,
         continuation: CheckedContinuation<Bool, Never>) {
        self.queue = queue; self.message = message; self.data = data; self.key = key
        self.continuation = continuation
    }

    func start() {
        let browser = NWBrowser(for: .bonjour(type: SharedSetupTransport.serviceType, domain: nil), using: .tcp)
        self.browser = browser
        browser.stateUpdateHandler = { [self] state in if case .failed = state { finish(false) } }
        browser.browseResultsChangedHandler = { [self] results, _ in
            guard connection == nil, continuation != nil else { return }
            for result in results {
                guard case let .service(name, _, _, _) = result.endpoint,
                      name == message.recipient.uuidString else { continue }
                let channel = NWConnection(to: result.endpoint, using: PeerAvailabilityService.secureParameters(key: key))
                connection = channel
                channel.stateUpdateHandler = { [self] state in
                    switch state {
                    case .ready:
                        SharedSetupTransport.send(data, on: channel) { [self] sent in
                            guard sent else { finish(false); return }
                            SharedSetupTransport.receive(on: channel) { [self] reply in
                                guard let reply,
                                      let ack = try? SharedSetupWire.decode(reply, key: key,
                                          sender: message.recipient, recipient: message.sender),
                                      ack.requestID == message.requestID, ack.setupID == message.setupID,
                                      ack.revision == message.revision else { finish(false); return }
                                finish(ack.kind == .saved)
                            }
                        }
                    case .failed: finish(false)
                    default: break
                    }
                }
                channel.start(queue: queue)
                break
            }
        }
        queue.asyncAfter(deadline: .now() + 15) { [self] in finish(false) }
        browser.start(queue: queue)
    }

    private func finish(_ saved: Bool) {
        guard let continuation else { return }
        self.continuation = nil
        browser?.cancel(); browser = nil
        connection?.cancel(); connection = nil
        continuation.resume(returning: saved)
    }
}
#endif
