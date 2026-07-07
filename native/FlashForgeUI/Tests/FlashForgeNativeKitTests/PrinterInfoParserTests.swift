import FlashForgeNativeKit
import Testing

@Test func parsesM115PrinterInfoReplay() {
    let replay = """
    CMD M115 Received.
    Machine Type: FlashForge Adventurer 5M Pro
    Machine Name: Studio Printer

    Firmware: 3.1.2
    SN: SN-CREATOR5
    X:220 Y:220 Z:220
    Tool Count: 1
    Mac Address: 00:11:22:33:44:55
    ok
    """

    let info = PrinterInfoParser().parse(replay)

    #expect(info?.typeName == "FlashForge Adventurer 5M Pro")
    #expect(info?.name == "Studio Printer")
    #expect(info?.firmwareVersion == "3.1.2")
    #expect(info?.serialNumber == "SN-CREATOR5")
    #expect(info?.dimensions == "X:220 Y:220 Z:220")
    #expect(info?.toolCount == "1")
    #expect(info?.macAddress == "00:11:22:33:44:55")
}

@Test func parsesSerialNumberPrefixVariant() {
    let replay = """
    Machine Type: FlashForge Adventurer 4
    Machine Name: Legacy
    Firmware: 2.3.4
    Serial Number: SN-A4
    ok
    """

    let info = PrinterInfoParser().parse(replay)

    #expect(info?.serialNumber == "SN-A4")
}

@Test func rejectsM115ReplayWithoutMachineTypeOrFirmware() {
    let missingType = PrinterInfoParser().parse("Firmware: 3.1.2\nok")
    let missingFirmware = PrinterInfoParser().parse("Machine Type: FlashForge Adventurer 5M\nok")

    #expect(missingType == nil)
    #expect(missingFirmware == nil)
}
