import XCTest
import DisplayDomain
@testable import TopologyCore

final class SharedComputerSetupTests: XCTestCase {
    func testMigrationUpdatesUniquePairedPeerUsingReviewedValues() throws {
        let display = DisplayRecordID(rawValue: "display"), peer = UUID().uuidString
        let shortcut = KeyBinding(keyCode: 0x13, modifiers: KeyBinding.controlOptionCommand)
        let legacy = InputSwitchBinding(id: "old", displayID: display, inputCode: 0x11,
            binding: shortcut, destinationName: "Air", availabilityPeerID: peer)
        var reviewed = legacy
        reviewed.id = "shared"; reviewed.inputCode = 0xd2; reviewed.transport = .lgAlternate
        let registry = KeyboardShortcutRegistry(inputSwitchBindings: [legacy])
        let updated = try SharedSetupMigration.merging([reviewed], into: registry)
        XCTAssertEqual(updated.inputSwitchBindings, [reviewed])
        var duplicate = legacy; duplicate.id = "duplicate"
        XCTAssertThrowsError(try SharedSetupMigration.merging([reviewed], into: .init(inputSwitchBindings: [legacy, duplicate])))
    }
    func testMonitorIdentityMatchesAcrossInputProductIDs() {
        let identity = SharedComputerSetup.MonitorIdentity(vendorID: 7789, serialNumber: "sample-serial")
        let mini = DisplayRecord(id: .init(rawValue: "mini-display"), fingerprint: .init(vendorID: 7789, productID: 30585, serialNumber: "sample-serial"), displayClass: .external)
        let air = DisplayRecord(id: .init(rawValue: "air-display"), fingerprint: .init(vendorID: 7789, productID: 30587, serialNumber: "sample-serial"), displayClass: .external)
        let other = DisplayRecord(id: .init(rawValue: "other-display"), fingerprint: .init(vendorID: 7789, productID: 30585, serialNumber: "different"), displayClass: .external)
        XCTAssertTrue(identity.matches(mini))
        XCTAssertTrue(identity.matches(air))
        XCTAssertFalse(identity.matches(other))
        XCTAssertEqual(identity.uniqueMatch(in: [air.id: air, other.id: other]), air.id)
        XCTAssertNil(identity.uniqueMatch(in: [mini.id: mini, air.id: air]))
        XCTAssertNil(identity.uniqueMatch(in: [other.id: other]))
    }
    func testLGInputsRetainTheirTransportForEachMac() throws {
        let mini = UUID(), air = UUID()
        let choices = DDCInputTransport.allCases.flatMap { mode in mode.inputs.map { (mode, $0.name, $0.code) } }
        let hdmi = try XCTUnwrap(choices.first { $0.1 == "HDMI 1 (LG)" })
        let usbC = try XCTUnwrap(choices.first { $0.1 == "USB-C (LG alt, 0xD2)" })
        let profiles = [
            SharedComputerSetup.Computer(peerID: mini, name: "Mini", inputCode: hdmi.2, transport: hdmi.0,
                keyboard: nil, mouse: nil, shortcut: .init(keyCode: 1, modifiers: 0)),
            SharedComputerSetup.Computer(peerID: air, name: "Air", inputCode: usbC.2, transport: usbC.0,
                keyboard: nil, mouse: nil, shortcut: .init(keyCode: 2, modifiers: 0))
        ]
        let bindings = try SharedComputerSetup(revision: 1, monitorName: "LG", computers: profiles)
            .bindings(localID: mini, displayID: .init(rawValue: "display"))
        XCTAssertEqual(bindings.map(\.inputCode), [0x90, 0xd2])
        XCTAssertEqual(bindings.map(\.effectiveTransport), [.lgAlternate, .lgAlternate])
    }
    func testMigrationPreservesUnrelatedEntriesAndRejectsConflicts() throws {
        let display = DisplayRecordID(rawValue: "display")
        let shortcut = KeyBinding(keyCode: 0x12, modifiers: KeyBinding.controlOptionCommand)
        let legacy = InputSwitchBinding(id: "legacy", displayID: display, inputCode: 0x90,
            binding: shortcut, transport: .lgAlternate, destinationName: "Mini")
        let unrelated = InputSwitchBinding(id: "other", displayID: display, inputCode: 0x91,
            binding: .init(keyCode: 0x13, modifiers: KeyBinding.controlOptionCommand), destinationName: "Other")
        var replacement = legacy
        replacement.id = "shared"
        let original = KeyboardShortcutRegistry(inputSwitchBindings: [legacy, unrelated])
        let migrated = try SharedSetupMigration.merging([replacement], into: original)
        XCTAssertEqual(Set(migrated.inputSwitchBindings.map(\.id)), Set(["shared", "other"]))
        XCTAssertEqual(original.inputSwitchBindings.count, 2)
        var conflicting = replacement
        conflicting.inputCode = 0xd2
        XCTAssertThrowsError(try SharedSetupMigration.merging([conflicting], into: original))
        XCTAssertEqual(original.inputSwitchBindings, [legacy, unrelated])
        let ambiguous = KeyboardShortcutRegistry(inputSwitchBindings: [legacy, InputSwitchBinding(
            id: "duplicate", displayID: display, inputCode: 0x90, binding: shortcut,
            transport: .lgAlternate, destinationName: "Mini")])
        XCTAssertThrowsError(try SharedSetupMigration.merging([replacement], into: ambiguous))
    }
    #if canImport(CryptoKit)
    func testWireAuthenticatesPeersAndPayload() throws {
        let first = UUID(), second = UUID(), key = Data(repeating: 7, count: 32)
        let a = SharedComputerSetup.Computer(peerID: first, name: "Mini", inputCode: 0x90,
            transport: .lgAlternate, keyboard: nil, mouse: nil, shortcut: .init(keyCode: 1, modifiers: 0))
        let b = SharedComputerSetup.Computer(peerID: second, name: "Air", inputCode: 0xd2,
            transport: .lgAlternate, keyboard: nil, mouse: nil, shortcut: .init(keyCode: 2, modifiers: 0))
        let setup = SharedComputerSetup(revision: 1, monitorName: "Display", computers: [a, b])
        let message = SharedSetupWire.Message(kind: .offer, sender: first, recipient: second,
            requestID: UUID(), setupID: setup.id, revision: setup.revision, setup: setup)
        let data = try SharedSetupWire.encode(message, key: key)
        XCTAssertEqual(try SharedSetupWire.decode(data, key: key, sender: first, recipient: second), message)
        XCTAssertThrowsError(try SharedSetupWire.decode(data, key: Data(repeating: 8, count: 32), sender: first, recipient: second))
        XCTAssertThrowsError(try SharedSetupWire.decode(data, key: key, sender: first, recipient: UUID()))
        var tampered = data; tampered[tampered.startIndex] ^= 1
        XCTAssertThrowsError(try SharedSetupWire.decode(tampered, key: key, sender: first, recipient: second))
    }
    #endif
    func testAcknowledgementAndRevisionSafety() throws {
        let first = UUID(), second = UUID()
        let a = SharedComputerSetup.Computer(peerID: first, name: "Mini", inputCode: 0x90,
            transport: .lgAlternate, keyboard: nil, mouse: nil,
            shortcut: .init(keyCode: 0x12, modifiers: KeyBinding.controlOptionCommand))
        let b = SharedComputerSetup.Computer(peerID: second, name: "Air", inputCode: 0xd2,
            transport: .lgAlternate, keyboard: nil, mouse: nil,
            shortcut: .init(keyCode: 0x13, modifiers: KeyBinding.controlOptionCommand))
        let setup = SharedComputerSetup(revision: 2, monitorName: "Display", computers: [a, b])
        var delivery = try SharedSetupDelivery(setup: setup, peerID: second)
        XCTAssertFalse(delivery.acknowledge(setupID: setup.id, revision: 1, from: second))
        XCTAssertFalse(delivery.acknowledge(setupID: setup.id, revision: 2, from: first))
        XCTAssertEqual(delivery.status, .pending)
        XCTAssertTrue(delivery.acknowledge(setupID: setup.id, revision: 2, from: second))
        XCTAssertEqual(delivery.status, .acknowledged)
        var older = setup; older.revision = 1
        XCTAssertEqual(SharedSetupRevisionDecision.decide(incoming: older, applied: setup), .rejectOlder)
        XCTAssertEqual(SharedSetupRevisionDecision.decide(incoming: setup, applied: setup), .alreadyApplied)
        var changed = setup; changed.monitorName = "Another display"
        XCTAssertEqual(SharedSetupRevisionDecision.decide(incoming: changed, applied: setup), .rejectDifferentSetup)
    }

    func testResolvesPerMacAndRejectsDuplicateIDs() throws {
        let first = UUID(), second = UUID()
        let a = SharedComputerSetup.Computer(peerID: first, name: "Mini", inputCode: 0x90,
            transport: .lgAlternate, keyboard: .init(name: "Keyboard", slot: 1), mouse: nil,
            shortcut: .init(keyCode: 0x12, modifiers: KeyBinding.controlOptionCommand))
        var b = SharedComputerSetup.Computer(peerID: second, name: "Air", inputCode: 0xd2,
            transport: .lgAlternate, keyboard: .init(name: "Keyboard", slot: 2), mouse: nil,
            shortcut: .init(keyCode: 0x13, modifiers: KeyBinding.controlOptionCommand))
        let setup = SharedComputerSetup(revision: 1, monitorName: "Display", computers: [a, b])
        let bindings = try setup.bindings(localID: first, displayID: DisplayRecordID(rawValue: "local-display"))
        XCTAssertNil(bindings[0].availabilityPeerID)
        XCTAssertEqual(bindings[1].availabilityPeerID, second.uuidString)
        XCTAssertEqual(bindings[1].peripherals?.keyboardSlot, 2)
        b.peerID = first
        XCTAssertThrowsError(try SharedComputerSetup(revision: 1, monitorName: "Display", computers: [a, b]).validate())
    }
}
