import XCTest
@testable import DisplayDomain

final class DDCInputTransportTests: XCTestCase {
    func testStandardAndLGUseDifferentCommandChannels() {
        XCTAssertEqual(DDCInputTransport.standard.vcpCode, 0x60)
        XCTAssertEqual(DDCInputTransport.standard.sourceAddress, 0x51)
        XCTAssertEqual(DDCInputTransport.lgAlternate.vcpCode, 0xF4)
        XCTAssertEqual(DDCInputTransport.lgAlternate.sourceAddress, 0x50)
        // USB-C differs even between LG models; keep both common values selectable.
        let values = DDCInputTransport.lgAlternate.inputs.map(\.code)
        XCTAssertTrue(values.contains(0xD1))
        XCTAssertTrue(values.contains(0xD2))
    }

    func testStandardPacketRemainsByteForByteCompatible() {
        XCTAssertEqual(DDCWritePacket.bytes(vcp: 0x60, value: 0x1B),
                       [0x84, 0x03, 0x60, 0x00, 0x1B, 0xC3])
    }

    func testLGPacketIncludesAlternateSourceInChecksum() {
        let packet = DDCWritePacket.bytes(vcp: 0xF4, value: 0xD1, sourceAddress: 0x50)
        XCTAssertEqual(packet, [0x84, 0x03, 0xF4, 0x00, 0xD1, 0x9C])
        XCTAssertEqual(packet.reduce(UInt8(0x6e ^ 0x50), ^), 0)
        // Changing only the IOAVService dataAddress without changing the checksum is invalid.
        XCTAssertNotEqual(packet, DDCWritePacket.bytes(vcp: 0xF4, value: 0xD1))
    }

    func testPacketRetainsBothBytesOfCustomValue() {
        let packet = DDCWritePacket.bytes(vcp: 0x60, value: 0x1234)
        XCTAssertEqual(Array(packet[3...4]), [0x12, 0x34])
        XCTAssertEqual(packet.reduce(UInt8(0x6e ^ 0x51), ^), 0)
    }
    func testDedicatedLGUSBCEntryUses210RatherThanDP2Value209() {
        XCTAssertEqual(DDCInputTransport.lgAlternate.inputName(210), "USB-C (LG alt, 0xD2)")
        XCTAssertEqual(DDCWritePacket.bytes(vcp: 0xF4, value: 210, sourceAddress: 0x50),
                       [0x84, 0x03, 0xF4, 0x00, 0xD2, 0x9F])
    }

}
