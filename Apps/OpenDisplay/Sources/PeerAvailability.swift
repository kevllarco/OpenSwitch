#if os(macOS)
import Foundation
import Combine
import Network
import Security
import CryptoKit

/// Authenticated availability and configured-device activity summaries. No input contents or
/// destination commands cross the network; activity is reduced to elapsed seconds.
enum PeerWire {
    static let length = 69 // version + 32-byte nonce + 36-byte canonical UUID

    static let statusLength = 4096

    static func statusResponse(to request: Data, localID: UUID, key: Data,
                               snapshot: DeviceActivitySnapshot) -> Data? {
        guard request.count == length, request.first == 2, key.count == 32,
              String(data: request.suffix(36), encoding: .utf8) == localID.uuidString,
              let json = try? JSONEncoder().encode(snapshot), json.count <= statusLength - 71 else { return nil }
        var body = Data([2]) + Data(localID.uuidString.utf8)
        body.append(UInt8(json.count >> 8)); body.append(UInt8(json.count & 255))
        body.append(json)
        body.append(Data(repeating: 0, count: statusLength - 32 - body.count))
        return body + Data(HMAC<SHA256>.authenticationCode(for: request + body, using: SymmetricKey(data: key)))
    }

    static func status(_ response: Data, request: Data, expectedID: UUID, key: Data) -> DeviceActivitySnapshot? {
        guard response.count == statusLength, request.count == length, request.first == 2,
              response.first == 2, key.count == 32,
              String(data: request.suffix(36), encoding: .utf8) == expectedID.uuidString,
              String(data: response[1..<37], encoding: .utf8) == expectedID.uuidString,
              HMAC<SHA256>.isValidAuthenticationCode(response.suffix(32),
                authenticating: request + response.prefix(statusLength - 32), using: SymmetricKey(data: key)) else { return nil }
        let size = Int(response[37]) << 8 | Int(response[38])
        guard size > 0, size <= statusLength - 71 else { return nil }
        return try? JSONDecoder().decode(DeviceActivitySnapshot.self, from: response[39..<(39 + size)])
    }

    static func randomBytes(count: Int) -> Data? {
        var bytes = [UInt8](repeating: 0, count: count)
        guard SecRandomCopyBytes(kSecRandomDefault, count, &bytes) == errSecSuccess else { return nil }
        return Data(bytes)
    }

    static func parseCode(_ text: String) -> Data? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count == 64, value.allSatisfy({ $0.isASCII && $0.isHexDigit }) else { return nil }
        var result = Data()
        var index = value.startIndex
        while index < value.endIndex {
            let next = value.index(index, offsetBy: 2)
            guard let byte = UInt8(value[index..<next], radix: 16) else { return nil }
            result.append(byte)
            index = next
        }
        return result.count == 32 ? result : nil
    }

    static func code(_ data: Data) -> String { data.map { String(format: "%02X", $0) }.joined() }

    static func request(nonce: Data, peerID: UUID) -> Data? {
        guard nonce.count == 32 else { return nil }
        return Data([1]) + nonce + Data(peerID.uuidString.utf8)
    }

    static func response(to request: Data, localID: UUID, key: Data) -> Data? {
        guard request.count == length, request.first == 1, key.count == 32,
              String(data: request.suffix(36), encoding: .utf8) == localID.uuidString else { return nil }
        let tag = HMAC<SHA256>.authenticationCode(for: request, using: SymmetricKey(data: key))
        return Data([1]) + Data(localID.uuidString.utf8) + Data(tag)
    }

    static func verify(_ response: Data, request: Data, expectedID: UUID, key: Data) -> Bool {
        guard response.count == length, response.first == 1, key.count == 32,
              String(data: response[1..<37], encoding: .utf8) == expectedID.uuidString,
              request.count == length, request.first == 1,
              String(data: request.suffix(36), encoding: .utf8) == expectedID.uuidString else { return false }
        return HMAC<SHA256>.isValidAuthenticationCode(response.suffix(32), authenticating: request,
                                                        using: SymmetricKey(data: key))
    }
}

/// Bundle-specific Keychain item; the shared code is never stored in settings.json or exported.
enum PeerKeychain {
    private static var service: String { (Bundle.main.bundleIdentifier ?? "DeskSwitch") + ".peer-key" }
    private static let account = "local-network-pairing"
    private static func query(account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }
    enum LoadResult: Sendable {
        case found(Data)
        case missing
        case unavailable
    }

    static func load() -> LoadResult {
        load(account: account, helperArgument: nil)
    }
    static func load(peerID: UUID) -> LoadResult {
        load(account: peerID.uuidString, helperArgument: peerID.uuidString)
    }
    private static func load(account: String, helperArgument: String?) -> LoadResult {
        #if PUBLIC_API_ONLY
        var q = query(account: account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return .missing }
        guard status == errSecSuccess, let data = result as? Data, data.count == 32 else { return .unavailable }
        return .found(data)
        #else
        guard let helper = Bundle.main.url(forResource: "desk-switch-keychain", withExtension: nil) else { return .unavailable }
        let process = Process()
        let output = Pipe()
        process.executableURL = helper
        if let helperArgument { process.arguments = [helperArgument] }
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return .unavailable }
        // A dismissed or unattended Keychain prompt must not leave an orphan helper indefinitely.
        let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 120, execute: timeout)
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        timeout.cancel()
        NSLog("OpenSwitch pairing key helper exited with status %d", process.terminationStatus)
        if process.terminationStatus == 3 { return .missing }
        guard process.terminationStatus == 0, data.count == 32 else { return .unavailable }
        return .found(data)
        #endif
    }
    static func save(_ data: Data) -> Bool {
        save(data, account: account)
    }
    static func save(_ data: Data, peerID: UUID) -> Bool {
        save(data, account: peerID.uuidString)
    }
    private static func save(_ data: Data, account: String) -> Bool {
        guard data.count == 32 else { return false }
        let q = query(account: account)
        let status = SecItemUpdate(q as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }
        var add = q
        add[kSecValueData as String] = data
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }
    static func remove() -> Bool {
        remove(account: account)
    }
    static func remove(peerID: UUID) -> Bool { remove(account: peerID.uuidString) }
    private static func remove(account: String) -> Bool {
        let status = SecItemDelete(query(account: account) as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}

/// One serial queue owns listener, browsing state and all connection callbacks.
final class PeerAvailabilityService: @unchecked Sendable {
    static let serviceType = "_deskswitch._tcp"

    /// TLS 1.2 ECDHE-PSK with AES-GCM (RFC 8442); the random shared code authenticates
    /// both endpoints and ephemeral key exchange provides forward secrecy. TLS 1.3 external
    /// PSK did not interoperate in the local Network.framework tests, so fail closed on this suite.
    static func secureParameters(key: Data) -> NWParameters {
        let tls = NWProtocolTLS.Options()
        let psk = key.withUnsafeBytes { DispatchData(bytes: $0) }
        let identity = Data("desk-switch-v1".utf8).withUnsafeBytes { DispatchData(bytes: $0) }
        sec_protocol_options_add_pre_shared_key(tls.securityProtocolOptions, psk as __DispatchData, identity as __DispatchData)
        // TLS_ECDHE_PSK_WITH_AES_128_GCM_SHA256, RFC 8442.
        sec_protocol_options_append_tls_ciphersuite(tls.securityProtocolOptions, tls_ciphersuite_t(rawValue: 0xD001)!)
        sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)
        sec_protocol_options_set_max_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)
        return NWParameters(tls: tls, tcp: NWProtocolTCP.Options())
    }
    private let queue = DispatchQueue(label: "dev.deskswitch.peer-availability")
    private var listeners: [UUID: NWListener] = [:]
    private var localID: UUID?
    private var keys: [UUID: Data] = [:]
    private var inbound: [UUID: NWConnection] = [:]
    private var activityProvider: (@Sendable () -> DeviceActivitySnapshot)?

    func setActivityProvider(_ provider: @escaping @Sendable () -> DeviceActivitySnapshot) {
        queue.async { self.activityProvider = provider }
    }

    func configure(localID: UUID, keys: [UUID: Data]) {
        queue.async { [self] in
            listeners.values.forEach { $0.cancel() }; listeners.removeAll()
            inbound.values.forEach { $0.cancel() }; inbound.removeAll()
            self.localID = localID
            self.keys = keys.filter { $0.key != localID && $0.value.count == 32 }
            guard !self.keys.isEmpty else { return }
            for (peerID, key) in self.keys {
                do {
                    let newListener = try NWListener(using: Self.secureParameters(key: key), on: .any)
                    newListener.service = NWListener.Service(name: peerID.uuidString, type: Self.serviceType)
                    newListener.newConnectionHandler = { [weak self] connection in
                        guard let self, self.localID == localID, self.keys[peerID] == key,
                              self.inbound.count < 16 else { connection.cancel(); return }
                        let id = UUID()
                        self.inbound[id] = connection
                        connection.stateUpdateHandler = { [weak self] state in
                            switch state {
                            case .cancelled, .failed: self?.inbound.removeValue(forKey: id)
                            default: break
                            }
                        }
                        self.respond(connection, localID: localID, key: key)
                    }
                    listeners[peerID] = newListener
                    newListener.start(queue: queue)
                } catch {
                    NSLog("OpenSwitch could not start peer listener for %@", peerID.uuidString)
                }
            }
        }
    }

    private func respond(_ connection: NWConnection, localID: UUID, key: Data) {
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + 3) { connection.cancel() }
        connection.receive(minimumIncompleteLength: PeerWire.length, maximumLength: PeerWire.length) {
            data, _, _, _ in
            guard let data else { connection.cancel(); return }
            let reply = data.first == 2
                ? PeerWire.statusResponse(to: data, localID: localID, key: key,
                    snapshot: self.activityProvider?() ?? DeviceActivitySnapshot(devices: []))
                : PeerWire.response(to: data, localID: localID, key: key)
            guard let response = reply else {
                connection.cancel(); return
            }
            connection.send(content: response, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }

    func check(expectedID: UUID, timeout: TimeInterval = 5) async -> Bool {
        await query(expectedID: expectedID, version: 1, timeout: timeout) != nil
    }

    func activity(expectedID: UUID) async -> DeviceActivitySnapshot? {
        guard let result = await query(expectedID: expectedID, version: 2, timeout: 2) else { return nil }
        return try? JSONDecoder().decode(DeviceActivitySnapshot.self, from: result)
    }

    private func query(expectedID: UUID, version: UInt8, timeout: TimeInterval) async -> Data? {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                guard let key = keys[expectedID], let localID, expectedID != localID,
                      let nonce = PeerWire.randomBytes(count: 32),
                      var request = PeerWire.request(nonce: nonce, peerID: expectedID) else {
                    continuation.resume(returning: nil); return
                }
                request[0] = version
                let check = PeerCheck(queue: queue, expectedID: expectedID, key: key,
                                      request: request, continuation: continuation)
                check.start(timeout: timeout)
            }
        }
    }
}

/// Retained by its browser callbacks until completion; all mutations happen on `queue`.
private final class PeerCheck: @unchecked Sendable {
    private let queue: DispatchQueue
    private let expectedID: UUID
    private let key: Data
    private let request: Data
    private var continuation: CheckedContinuation<Data?, Never>?
    private var browser: NWBrowser?
    private var connections: [NWConnection] = []
    private var seen: Set<NWEndpoint> = []

    init(queue: DispatchQueue, expectedID: UUID, key: Data, request: Data,
         continuation: CheckedContinuation<Data?, Never>) {
        self.queue = queue; self.expectedID = expectedID; self.key = key
        self.request = request; self.continuation = continuation
    }
    func start(timeout: TimeInterval) {
        let browser = NWBrowser(for: .bonjour(type: PeerAvailabilityService.serviceType, domain: nil), using: .tcp)
        self.browser = browser
        browser.stateUpdateHandler = { [self] state in
            if case .failed = state { finish(nil) }
        }
        browser.browseResultsChangedHandler = { [self] results, _ in
            for result in results where seen.insert(result.endpoint).inserted {
                // Limit untrusted network discovery from creating unbounded connections.
                guard connections.count < 32 else { break }
                connect(result.endpoint)
            }
        }
        queue.asyncAfter(deadline: .now() + timeout) { [self] in finish(nil) }
        browser.start(queue: queue)
    }
    private func connect(_ endpoint: NWEndpoint) {
        let connection = NWConnection(to: endpoint, using: PeerAvailabilityService.secureParameters(key: key))
        connections.append(connection)
        connection.stateUpdateHandler = { [self] state in
            if case .ready = state {
                connection.send(content: request, completion: .contentProcessed { [self] error in
                    guard error == nil else { connection.cancel(); return }
                    connection.receive(minimumIncompleteLength: request.first == 2 ? PeerWire.statusLength : PeerWire.length,
                                       maximumLength: request.first == 2 ? PeerWire.statusLength : PeerWire.length) {
                        [self] data, _, _, _ in
                        if let data, request.first == 2,
                           let snapshot = PeerWire.status(data, request: request, expectedID: expectedID, key: key),
                           let json = try? JSONEncoder().encode(snapshot) {
                            finish(json)
                        } else if let data, PeerWire.verify(data, request: request, expectedID: expectedID, key: key) {
                            finish(Data())
                        } else { connection.cancel() }
                    }
                })
            }
        }
        connection.start(queue: queue)
    }
    private func finish(_ result: Data?) {
        guard let continuation else { return }
        self.continuation = nil
        browser?.cancel(); browser = nil
        connections.forEach { $0.cancel() }; connections.removeAll()
        continuation.resume(returning: result)
    }
}
#endif

#if os(macOS)
/// Coordinates the optional peer service for this app installation.
@MainActor
final class PeerPairing: ObservableObject {
    struct TrustedPeer: Codable, Identifiable, Sendable {
        var id: UUID
        var name: String
        var devices: LogitechHandoff.DeviceChoices?
    }
    let localID: UUID
    let service = PeerAvailabilityService()
    let setupTransport = SharedSetupTransport()
    @Published private(set) var hasCode = false
    @Published private(set) var isLoadingCode = false
    @Published private(set) var accessError = false
    @Published private(set) var nearbyComputers: [NearbyOpenSwitchMac] = []
    @Published private(set) var trustedPeers: [TrustedPeer] = []
    @Published private(set) var pendingRequest: IncomingOpenSwitchPairing?
    @Published private(set) var pairedPeerID: UUID?
    @Published private(set) var pairedPeerName: String?
    @Published private(set) var pairedPeerDevices: LogitechHandoff.DeviceChoices?
    @Published private(set) var pairingStatus: String?
    @Published private(set) var isConnecting = false
    private let defaults: UserDefaults
    private var peerKeys: [UUID: Data] = [:]
    private let discoveryService: BonjourPairingService
    private var keyRevision = 0

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let key = "deskSwitchAvailabilityPeerID"
        if let saved = defaults.string(forKey: key), let uuid = UUID(uuidString: saved) {
            localID = uuid
        } else {
            let uuid = UUID()
            defaults.set(uuid.uuidString, forKey: key)
            localID = uuid
        }
        let savedPeerID = defaults.string(forKey: "openSwitchPairedPeerID").flatMap(UUID.init(uuidString:))
        let savedPeerName = defaults.string(forKey: "openSwitchPairedPeerName")
        let savedDevices = defaults.data(forKey: "openSwitchPairedPeerDevices")
            .flatMap { try? JSONDecoder().decode(LogitechHandoff.DeviceChoices.self, from: $0) }
        pairedPeerID = savedPeerID
        pairedPeerName = savedPeerName
        pairedPeerDevices = savedDevices
        let savedPeers = defaults.data(forKey: "openSwitchTrustedPeers")
            .flatMap { try? JSONDecoder().decode([TrustedPeer].self, from: $0) } ?? []
        trustedPeers = savedPeers.isEmpty
            ? (savedPeerID.flatMap { id in savedPeerName.map { TrustedPeer(id: id, name: $0, devices: savedDevices) } }.map { [$0] } ?? [])
            : savedPeers
        let computerName = Host.current().localizedName ?? ProcessInfo.processInfo.hostName
        discoveryService = BonjourPairingService(localID: localID, localName: computerName)
        discoveryService.onNearbyChanged = { [weak self] computers in
            Task { @MainActor [weak self] in
                self?.nearbyComputers = computers
            }
        }
        discoveryService.onIncomingRequest = { [weak self] request in
            Task { @MainActor [weak self] in self?.receive(request) }
        }
        discoveryService.onPairingStatus = { [weak self] status in
            Task { @MainActor [weak self] in
                self?.pairingStatus = status
                self?.isConnecting = status?.hasPrefix("Waiting for ") == true
                    || status == "Securing the connection…"
            }
        }
        discoveryService.onPaired = { [weak self] peerID, name, key, devices in
            guard PeerKeychain.save(key, peerID: peerID) else {
                Task { @MainActor [weak self] in self?.pairingStatus = "Couldn’t save the secure connection in Keychain." }
                return false
            }
            Task { @MainActor [weak self] in
                self?.finishPairing(peerID: peerID, name: name, key: key, devices: devices)
            }
            return true
        }
        discoveryService.startListening()
        loadSavedPeers()
    }

    func discoverNearbyComputers() {
        pairingStatus = "Searching for nearby OpenSwitch Macs…"
        discoveryService.discover()
    }

    func connect(to computer: NearbyOpenSwitchMac) {
        pairingStatus = "Requesting approval from \(computer.name)…"
        isConnecting = true
        discoveryService.connect(to: computer.id)
    }

    func accept(_ request: IncomingOpenSwitchPairing) {
        pendingRequest = nil
        pairingStatus = "Securing the connection…"
        isConnecting = true
        discoveryService.accept(requestID: request.id)
    }

    func decline(_ request: IncomingOpenSwitchPairing) {
        pendingRequest = nil
        discoveryService.reject(requestID: request.id)
        pairingStatus = "Connection request declined."
        isConnecting = false
    }

    private func receive(_ request: IncomingOpenSwitchPairing) {
        pendingRequest = request
        NotificationCenter.default.post(name: .openSwitchPairingRequestReceived, object: self,
                                        userInfo: ["requestID": request.id, "computerName": request.computerName])
    }

    private func finishPairing(peerID: UUID, name: String, key: Data,
                               devices: LogitechHandoff.DeviceChoices?) {
        peerKeys[peerID] = key
        if let index = trustedPeers.firstIndex(where: { $0.id == peerID }) {
            trustedPeers[index] = TrustedPeer(id: peerID, name: name, devices: devices)
        } else {
            trustedPeers.append(TrustedPeer(id: peerID, name: name, devices: devices))
        }
        trustedPeers.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        persistTrustedPeers()
        defaults.set(peerID.uuidString, forKey: "openSwitchPairedPeerID")
        defaults.set(name, forKey: "openSwitchPairedPeerName")
        pairedPeerID = peerID
        pairedPeerName = name
        pairedPeerDevices = devices
        if let devices, let data = try? JSONEncoder().encode(devices) {
            defaults.set(data, forKey: "openSwitchPairedPeerDevices")
        } else {
            defaults.removeObject(forKey: "openSwitchPairedPeerDevices")
        }
        hasCode = true
        accessError = false
        configurePeerServices()
        pairingStatus = "Paired with \(name)."
    }

    private func loadSavedPeers() {
        guard !isLoadingCode else { return }
        isLoadingCode = true
        accessError = false
        keyRevision += 1
        let revision = keyRevision
        let peers = trustedPeers
        Task { [weak self] in
            var loaded: [UUID: Data] = [:]
            var hadFailure = false
            for peer in peers {
                switch await Task.detached(priority: .utility, operation: { PeerKeychain.load(peerID: peer.id) }).value {
                case .found(let key): loaded[peer.id] = key
                case .missing, .unavailable: hadFailure = true
                }
            }
            guard let self, self.keyRevision == revision else { return }
            self.isLoadingCode = false
            self.peerKeys = loaded
            self.hasCode = !loaded.isEmpty
            self.accessError = hadFailure && !peers.isEmpty
            self.defaults.set(hadFailure ? "unavailable" : (loaded.isEmpty ? "missing" : "available"),
                              forKey: "openSwitchKeyAccessDiagnostic")
            // Migrate the former single-peer Keychain item without exposing its secret.
            if loaded.isEmpty, peers.count == 1, let legacy = self.pairedPeerID,
               case .found(let key) = await Task.detached(priority: .utility, operation: { PeerKeychain.load() }).value,
               PeerKeychain.save(key, peerID: legacy) {
                self.peerKeys[legacy] = key
                _ = PeerKeychain.remove()
                self.hasCode = true
                self.persistTrustedPeers()
            }
            self.configurePeerServices()
        }
    }

    private func persistTrustedPeers() {
        if let data = try? JSONEncoder().encode(trustedPeers) {
            defaults.set(data, forKey: "openSwitchTrustedPeers")
        }
    }

    private func configurePeerServices() {
        service.configure(localID: localID, keys: peerKeys)
        setupTransport.configure(localID: localID, keys: peerKeys)
    }

    var trustedPeerIDs: Set<UUID> { Set(peerKeys.keys) }

    func save(code: String) -> Bool {
        guard let data = PeerWire.parseCode(code) else { return false }
        if let pairedPeerID {
            guard PeerKeychain.save(data, peerID: pairedPeerID) else { return false }
            peerKeys[pairedPeerID] = data
        } else if !PeerKeychain.save(data) { return false }
        keyRevision += 1
        isLoadingCode = false
        accessError = false
        hasCode = true
        configurePeerServices()
        return true
    }

    func forget() -> Bool { forget(peerID: pairedPeerID) }

    func forget(peerID: UUID?) -> Bool {
        if let peerID {
            guard PeerKeychain.remove(peerID: peerID) else { return false }
            peerKeys.removeValue(forKey: peerID)
            trustedPeers.removeAll { $0.id == peerID }
        } else {
            guard PeerKeychain.remove() else { return false }
        }
        keyRevision += 1
        isLoadingCode = false
        accessError = false
        pairedPeerID = trustedPeers.last?.id
        pairedPeerName = trustedPeers.last?.name
        pairedPeerDevices = trustedPeers.last?.devices
        if let pairedPeerID { defaults.set(pairedPeerID.uuidString, forKey: "openSwitchPairedPeerID") }
        else { defaults.removeObject(forKey: "openSwitchPairedPeerID") }
        if let pairedPeerName { defaults.set(pairedPeerName, forKey: "openSwitchPairedPeerName") }
        else { defaults.removeObject(forKey: "openSwitchPairedPeerName") }
        if let pairedPeerDevices, let data = try? JSONEncoder().encode(pairedPeerDevices) {
            defaults.set(data, forKey: "openSwitchPairedPeerDevices")
        } else { defaults.removeObject(forKey: "openSwitchPairedPeerDevices") }
        persistTrustedPeers()
        hasCode = !peerKeys.isEmpty
        configurePeerServices()
        pairingStatus = "Pairing removed."
        return true
    }
}
#endif
