import DisplayDomain
import XCTest
@testable import TopologyCore

final class KeyboardShortcutRegistryTests: XCTestCase {
    private let r = KeyBinding(keyCode: 0x0F, modifiers: KeyBinding.controlOptionCommand)
    private let up = KeyBinding(keyCode: 0x7E, modifiers: KeyBinding.controlOptionCommand)   // arrow up
    private let digit1 = KeyBinding(keyCode: 0x12, modifiers: KeyBinding.controlOptionCommand)
    private let digit2 = KeyBinding(keyCode: 0x13, modifiers: KeyBinding.controlOptionCommand)
    private let deskMonitor = DisplayRecordID(rawValue: "disp_desk")
    private let laptopMonitor = DisplayRecordID(rawValue: "disp_laptop")

    func testDefaultsBindReconnectAllToCtrlOptCmdR() {
        let defaults = KeyboardShortcutRegistry.defaults
        XCTAssertEqual(defaults.binding(for: .reconnectAll), r)
        XCTAssertNil(defaults.binding(for: .brightnessUp))   // unbound by default
        XCTAssertNil(defaults.binding(for: .faceLight))      // unbound by default, same as brightnessUp
    }

    func testFaceLightHasABehaviorNamingLabel() {
        XCTAssertEqual(HotkeyAction.faceLight.label, "Toggle FaceLight")
    }

    func testControlOptionCommandMaskMatchesCarbon() {
        // cmd 0x100 | option 0x800 | control 0x1000 = 0x1900
        XCTAssertEqual(KeyBinding.controlOptionCommand, 0x1900)
    }

    func testSetAndClearBinding() {
        var reg = KeyboardShortcutRegistry()
        reg.setBinding(up, for: .brightnessUp)
        XCTAssertEqual(reg.binding(for: .brightnessUp), up)
        reg.setBinding(nil, for: .brightnessUp)
        XCTAssertNil(reg.binding(for: .brightnessUp))
    }

    func testReverseLookupByCombo() {
        var reg = KeyboardShortcutRegistry()
        reg.setBinding(r, for: .reconnectAll)
        XCTAssertEqual(reg.action(for: r), .reconnectAll)
        XCTAssertNil(reg.action(for: up))
    }

    func testConflictDetection() {
        var reg = KeyboardShortcutRegistry()
        reg.setBinding(r, for: .reconnectAll)
        XCTAssertTrue(reg.conflicts(r, excluding: nil))                 // r is taken
        XCTAssertFalse(reg.conflicts(r, excluding: .reconnectAll))      // ...but by reconnectAll itself
        XCTAssertFalse(reg.conflicts(up))                              // up is free
        reg.setBinding(r, for: .brightnessUp)                          // same combo, two actions
        XCTAssertEqual(reg.conflictingBindings()[r]?.sorted { $0.rawValue < $1.rawValue },
                       [.brightnessUp, .reconnectAll])
    }

    func testMergeOverDefaultsKeepsOverridesAndFillsGaps() {
        var reg = KeyboardShortcutRegistry()
        reg.setBinding(up, for: .reconnectAll)    // override the default reconnect chord
        let merged = reg.mergedWithDefaults()
        XCTAssertEqual(merged.binding(for: .reconnectAll), up)        // override wins
        XCTAssertNil(merged.binding(for: .brightnessUp))             // still unbound (no default)
    }

    func testCodableRoundTripsIncludingUnknownKeyTolerance() throws {
        var reg = KeyboardShortcutRegistry()
        reg.setBinding(r, for: .reconnectAll)
        reg.setBinding(up, for: .brightnessUp)
        let data = try JSONEncoder().encode(reg)
        XCTAssertEqual(try JSONDecoder().decode(KeyboardShortcutRegistry.self, from: data), reg)
        // A future action key the current build doesn't know is ignored on decode (object form).
        let withUnknown = #"{"reconnectAll":{"keyCode":15,"modifiers":6400},"futureAction":{"keyCode":1,"modifiers":0}}"#
        let decoded = try JSONDecoder().decode(KeyboardShortcutRegistry.self, from: Data(withUnknown.utf8))
        XCTAssertEqual(decoded.binding(for: .reconnectAll), r)
        XCTAssertEqual(decoded.bindings.count, 1)  // futureAction dropped
        XCTAssertTrue(decoded.inputSwitchBindings.isEmpty)  // legacy shape never had these
    }

    func testAddAndRemoveInputSwitchBinding() {
        var reg = KeyboardShortcutRegistry()
        let entry = InputSwitchBinding(id: "hdmi2", displayID: deskMonitor, inputCode: 0x12, binding: digit1)
        reg.addInputSwitchBinding(entry)
        XCTAssertEqual(reg.inputSwitchBindings, [entry])

        // Adding again with the same id replaces rather than duplicating.
        let replacement = InputSwitchBinding(id: "hdmi2", displayID: deskMonitor, inputCode: 0x0F, binding: digit1)
        reg.addInputSwitchBinding(replacement)
        XCTAssertEqual(reg.inputSwitchBindings, [replacement])

        reg.removeInputSwitchBinding(id: "hdmi2")
        XCTAssertTrue(reg.inputSwitchBindings.isEmpty)
    }

    func testInputSwitchBindingConflictsWithFixedActionAndOtherInputSwitchBinding() {
        var reg = KeyboardShortcutRegistry()
        reg.setBinding(r, for: .reconnectAll)
        XCTAssertTrue(reg.inputSwitchBindingConflicts(r, excludingInputSwitchID: nil))    // clashes with reconnectAll
        XCTAssertFalse(reg.inputSwitchBindingConflicts(digit1, excludingInputSwitchID: nil))

        let hdmi2 = InputSwitchBinding(id: "hdmi2", displayID: deskMonitor, inputCode: 0x12, binding: digit1)
        reg.addInputSwitchBinding(hdmi2)
        XCTAssertTrue(reg.inputSwitchBindingConflicts(digit1, excludingInputSwitchID: nil))
        XCTAssertFalse(reg.inputSwitchBindingConflicts(digit1, excludingInputSwitchID: "hdmi2"))  // editing itself
        XCTAssertFalse(reg.inputSwitchBindingConflicts(digit2, excludingInputSwitchID: nil))       // free combo
    }

    func testInputSwitchBindingCodableRoundTrip() throws {
        var reg = KeyboardShortcutRegistry()
        reg.setBinding(r, for: .reconnectAll)
        reg.addInputSwitchBinding(InputSwitchBinding(id: "hdmi2", displayID: deskMonitor, inputCode: 0x12, binding: digit1))
        reg.addInputSwitchBinding(InputSwitchBinding(id: "dp1", displayID: laptopMonitor, inputCode: 0x0F, binding: digit2))
        let data = try JSONEncoder().encode(reg)
        let decoded = try JSONDecoder().decode(KeyboardShortcutRegistry.self, from: data)
        XCTAssertEqual(decoded, reg)
        XCTAssertEqual(decoded.inputSwitchBindings.count, 2)
    }

    func testMergedWithDefaultsCarriesInputSwitchBindingsThrough() {
        var reg = KeyboardShortcutRegistry()
        let entry = InputSwitchBinding(id: "hdmi2", displayID: deskMonitor, inputCode: 0x12, binding: digit1)
        reg.addInputSwitchBinding(entry)
        XCTAssertEqual(reg.mergedWithDefaults().inputSwitchBindings, [entry])
    }
    func testExistingUSBCHotkeyDecodesWithStandardTransport() throws {
        let json = #"{"bindings":{"reconnectAll":{"keyCode":15,"modifiers":6400}},"inputSwitchBindings":[{"id":"usb-c","displayID":{"rawValue":"cg:test"},"inputCode":27,"binding":{"keyCode":19,"modifiers":6400}}]}"#
        let decoded = try JSONDecoder().decode(KeyboardShortcutRegistry.self, from: Data(json.utf8))
        let entry = try XCTUnwrap(decoded.inputSwitchBindings.first)
        XCTAssertEqual(entry.binding, digit2)
        XCTAssertEqual(entry.inputCode, 0x1B)
        XCTAssertNil(entry.transport)
        XCTAssertEqual(entry.effectiveTransport, .standard)
        XCTAssertEqual(try JSONDecoder().decode(KeyboardShortcutRegistry.self,
                                              from: JSONEncoder().encode(decoded)), decoded)
    }

    func testLGAlternateTransportSurvivesSaveAndDefaultsMerge() throws {
        let entry = InputSwitchBinding(id: "lg-usbc", displayID: deskMonitor,
                                       inputCode: 0xD1, binding: digit2, transport: .lgAlternate)
        let registry = KeyboardShortcutRegistry(inputSwitchBindings: [entry]).mergedWithDefaults()
        let decoded = try JSONDecoder().decode(KeyboardShortcutRegistry.self,
                                              from: JSONEncoder().encode(registry))
        XCTAssertEqual(decoded.inputSwitchBindings, [entry])
        XCTAssertEqual(decoded.inputSwitchBindings.first?.effectiveTransport.sourceAddress, 0x50)
        XCTAssertEqual(decoded.inputSwitchBindings.first?.effectiveTransport.vcpCode, 0xF4)
    }

    func testPeripheralSettingsRoundTripAndLegacyDefaultsToMonitorOnly() throws {
        let oldJSON = #"{"id":"old","displayID":{"rawValue":"cg:test"},"inputCode":27,"binding":{"keyCode":19,"modifiers":6400}}"#
        let old = try JSONDecoder().decode(InputSwitchBinding.self, from: Data(oldJSON.utf8))
        XCTAssertNil(old.peripherals)
        let options = KVMPeripheralConfiguration(mode: .independent, mouseName: "mouse",
                                                 keyboardName: "keyboard", mouseSlot: 2, keyboardSlot: 3)
        let entry = InputSwitchBinding(displayID: deskMonitor, inputCode: 0xD2, binding: digit2,
                                       transport: .lgAlternate, peripherals: options)
        XCTAssertEqual(try JSONDecoder().decode(InputSwitchBinding.self, from: JSONEncoder().encode(entry)), entry)
    }

    func testDestinationNameRoundTripAndLegacyLabel() throws {
        let legacy = InputSwitchBinding(displayID: deskMonitor, inputCode: 0xD2,
                                       binding: digit2, transport: .lgAlternate)
        XCTAssertEqual(legacy.destinationLabel, "USB-C (LG alt, 0xD2)")
        var named = legacy
        named.destinationName = "  MacBook  "
        XCTAssertEqual(named.destinationLabel, "MacBook")
        let decoded = try JSONDecoder().decode(InputSwitchBinding.self, from: JSONEncoder().encode(named))
        XCTAssertEqual(decoded.destinationName, "  MacBook  ")
        XCTAssertEqual(decoded.destinationLabel, "MacBook")
        named.destinationName = "  "
        XCTAssertEqual(named.destinationLabel, legacy.destinationLabel)
    }

    func testEditingDestinationKeepsMenuOrder() {
        let first = InputSwitchBinding(id: "first", displayID: deskMonitor, inputCode: 0x11, binding: digit1)
        let second = InputSwitchBinding(id: "second", displayID: deskMonitor, inputCode: 0x12, binding: digit2)
        var registry = KeyboardShortcutRegistry(inputSwitchBindings: [first, second])
        var edited = first
        edited.destinationName = "Mac mini"
        registry.addInputSwitchBinding(edited)
        XCTAssertEqual(registry.inputSwitchBindings, [edited, second])
    }

    func testAvailabilityPeerIsOptionalAndRoundTrips() throws {
        let data = Data(#"{"id":"old","displayID":{"rawValue":"cg:test"},"inputCode":27,"binding":{"keyCode":19,"modifiers":6400}}"#.utf8)
        var entry = try JSONDecoder().decode(InputSwitchBinding.self, from: data)
        XCTAssertNil(entry.availabilityPeerID)
        entry.availabilityPeerID = "8BCE99FE-AF53-4E8F-BF73-F846DF1E1F79"
        let decoded = try JSONDecoder().decode(InputSwitchBinding.self, from: JSONEncoder().encode(entry))
        XCTAssertEqual(decoded.availabilityPeerID, entry.availabilityPeerID)
    }

}
