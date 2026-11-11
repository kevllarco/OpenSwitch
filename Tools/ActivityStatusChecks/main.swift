import Foundation
import Combine

// Compile alongside the app's PeerAvailability.swift and DeviceActivityMonitor.swift.
@main struct ActivityStatusChecks {
    static func main() {
        let id = UUID(), other = UUID()
        let key = Data(repeating: 7, count: 32)
        var request = PeerWire.request(nonce: Data(repeating: 3, count: 32), peerID: id)!
        request[0] = 2
        let sample = DeviceActivitySnapshot(devices: [.init(name: "Configured mouse", connected: true, activityAge: 0.2)])
        let response = PeerWire.statusResponse(to: request, localID: id, key: key, snapshot: sample)!
        precondition(response.count == PeerWire.statusLength)
        precondition(PeerWire.status(response, request: request, expectedID: id, key: key)?.devices.first?.name == "Configured mouse")
        var changed = response; changed[45] ^= 1
        precondition(PeerWire.status(changed, request: request, expectedID: id, key: key) == nil)
        var replay = request; replay[1] ^= 1
        precondition(PeerWire.status(response, request: replay, expectedID: id, key: key) == nil)
        precondition(PeerWire.status(response, request: request, expectedID: other, key: key) == nil)
        precondition(PeerWire.status(response, request: request, expectedID: id, key: Data(repeating: 8, count: 32)) == nil)
        precondition(PeerWire.status(Data(response.prefix(100)), request: request, expectedID: id, key: key) == nil)
        let legacy = PeerWire.request(nonce: Data(repeating: 4, count: 32), peerID: id)!
        let legacyResponse = PeerWire.response(to: legacy, localID: id, key: key)!
        precondition(PeerWire.verify(legacyResponse, request: legacy, expectedID: id, key: key))
        precondition(PeerWire.status(legacyResponse, request: legacy, expectedID: id, key: key) == nil)
        let keyboard = "Keyboard", mouse = "Mouse"
        let names: Set<String> = [keyboard, mouse]
        func snapshot(_ connected: Bool, _ age: TimeInterval? = nil) -> DeviceActivitySnapshot {
            .init(devices: names.sorted().map { .init(name: $0, connected: connected, activityAge: age) })
        }
        var reports = [id: snapshot(true), other: snapshot(false)]
        precondition(Set(DeviceActivityOwnership.owners(names: names, snapshots: reports, allPeersResponded: true).values) == [id])
        precondition(DeviceActivityOwnership.owners(names: names, snapshots: reports, allPeersResponded: false).isEmpty)
        reports[other] = snapshot(true, 0.2)
        precondition(Set(DeviceActivityOwnership.owners(names: names, snapshots: reports, allPeersResponded: true).values) == [other])
        reports[id] = snapshot(true, 0.3)
        precondition(DeviceActivityOwnership.owners(names: names, snapshots: reports, allPeersResponded: true).isEmpty)
        reports = [id: .init(devices: [.init(name: keyboard, connected: true, activityAge: 1), .init(name: mouse, connected: false, activityAge: nil)]),
                   other: .init(devices: [.init(name: keyboard, connected: false, activityAge: nil), .init(name: mouse, connected: true, activityAge: 1)])]
        precondition(Set(DeviceActivityOwnership.owners(names: names, snapshots: reports, allPeersResponded: true).values).count == 2)
        precondition(DeviceActivityOwnership.owners(names: names, snapshots: [id: snapshot(false, 1)], allPeersResponded: true).isEmpty)
        print("Device ownership: connection, missing peer, activity priority, ambiguity, split and sleeping devices passed")
        print("Activity status authentication: valid exchange, tamper, replay, wrong peer/key, truncation and legacy availability passed")
    }
}
