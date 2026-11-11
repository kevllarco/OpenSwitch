import Foundation
import Network
import Security
import TopologyCore
import DisplayDomain

enum PeerAvailabilityService {
    static func secureParameters(key: Data) -> NWParameters {
        let tls = NWProtocolTLS.Options()
        let psk = key.withUnsafeBytes { DispatchData(bytes: $0) }
        let identity = Data("desk-switch-v1".utf8).withUnsafeBytes { DispatchData(bytes: $0) }
        sec_protocol_options_add_pre_shared_key(tls.securityProtocolOptions, psk as __DispatchData, identity as __DispatchData)
        sec_protocol_options_append_tls_ciphersuite(tls.securityProtocolOptions, tls_ciphersuite_t(rawValue: 0xD001)!)
        sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)
        sec_protocol_options_set_max_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)
        return NWParameters(tls: tls, tcp: NWProtocolTCP.Options())
    }
}
@main struct Check {
    static func main() async {
        let a = UUID(), b = UUID(), key = Data(repeating: 7, count: 32)
        let sender = SharedSetupTransport(), receiver = SharedSetupTransport()
        let profiles = [a,b].enumerated().map { i, id in SharedComputerSetup.Computer(peerID: id, name: "Mac \(i)", inputCode: 0x90+i, transport: .lgAlternate, keyboard: nil, mouse: nil, shortcut: .init(keyCode: UInt32(i+1), modifiers: 0)) }
        let setup = SharedComputerSetup(revision: 1, monitorName: "Sample", computers: profiles)
        receiver.setReceiver { _ in true }
        sender.configure(localID: a, peerID: b, key: key)
        receiver.configure(localID: b, peerID: a, key: key)
        let received = await sender.send(setup)
        print("acknowledged=\(received)")
        receiver.setReceiver { _ in false }
        let rejected = await sender.send(setup)
        print("rejected=\(!rejected)")
        receiver.configure(localID: b, peerID: nil, key: nil)
        let unavailable = await sender.send(setup)
        print("unavailable=\(!unavailable)")
        exit(received && !rejected && !unavailable ? 0 : 1)
    }
}
