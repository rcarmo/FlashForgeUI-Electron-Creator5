import Foundation
import FlashForgeNativeKit
import Testing

@Test func parsesModernDiscoveryResponse() {
    var data = Data(repeating: 0, count: 276)
    data.writeUTF8("AD5X", at: 0x00, length: 128)
    data.writeUInt16(8899, at: 0x84)
    data.writeUInt16(0x2B71, at: 0x86)
    data.writeUInt16(0x0038, at: 0x88)
    data.writeUInt16(0, at: 0x8A)
    data.writeUInt16(0x5A02, at: 0x8C)
    data.writeUInt16(8898, at: 0x8E)
    data.writeUTF8("SN-CREATOR5", at: 0x92, length: 128)

    let parser = DiscoveryResponseParser()
    let printer = parser.parse(data: data, remoteInfo: DiscoveryRemoteInfo(address: "192.168.1.77"))

    #expect(printer?.protocolFormat == .modern)
    #expect(printer?.model == .ad5x)
    #expect(printer?.name == "AD5X")
    #expect(printer?.ipAddress == "192.168.1.77")
    #expect(printer?.commandPort == 8899)
    #expect(printer?.eventPort == 8898)
    #expect(printer?.serialNumber == "SN-CREATOR5")
    #expect(printer?.status == .ready)
}

@Test func parsesLegacyDiscoveryResponse() {
    var data = Data(repeating: 0, count: 140)
    data.writeUTF8("Adventurer 4 Pro", at: 0x00, length: 128)
    data.writeUInt16(8899, at: 0x84)
    data.writeUInt16(0x2B71, at: 0x86)
    data.writeUInt16(0x001E, at: 0x88)
    data.writeUInt16(1, at: 0x8A)

    let parser = DiscoveryResponseParser()
    let printer = parser.parse(data: data, remoteInfo: DiscoveryRemoteInfo(address: "192.168.1.82"))

    #expect(printer?.protocolFormat == .legacy)
    #expect(printer?.model == .adventurer4)
    #expect(printer?.name == "Adventurer 4 Pro")
    #expect(printer?.commandPort == 8899)
    #expect(printer?.eventPort == nil)
    #expect(printer?.status == .busy)
}

@Test func ignoresInvalidDiscoveryResponse() {
    let parser = DiscoveryResponseParser()
    let printer = parser.parse(data: Data(repeating: 0, count: 64), remoteInfo: DiscoveryRemoteInfo(address: "127.0.0.1"))

    #expect(printer == nil)
}

private extension Data {
    mutating func writeUTF8(_ value: String, at offset: Int, length: Int) {
        let bytes = Array(value.utf8.prefix(length))
        replaceSubrange(offset..<(offset + bytes.count), with: bytes)
    }

    mutating func writeUInt16(_ value: Int, at offset: Int) {
        self[offset] = UInt8((value >> 8) & 0xFF)
        self[offset + 1] = UInt8(value & 0xFF)
    }
}
