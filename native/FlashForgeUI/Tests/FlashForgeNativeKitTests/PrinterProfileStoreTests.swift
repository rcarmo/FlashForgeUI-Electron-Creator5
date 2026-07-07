import FlashForgeNativeKit
import Foundation
import Testing

@Test func filePrinterProfileStoreRoundTripsDocument() throws {
    let directoryURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("FlashForgeNativeTests-\(UUID().uuidString)", isDirectory: true)
    let fileURL = directoryURL.appendingPathComponent("PrinterProfiles.json")
    defer {
        try? FileManager.default.removeItem(at: directoryURL)
    }

    let printerID = UUID()
    let expectedDocument = PrinterProfileDocument(
        profiles: [
            PrinterProfile(
                id: printerID,
                name: "Round Trip Printer",
                model: "Adventurer 5M",
                address: "192.168.1.66",
                serialNumber: "SN-ROUNDTRIP",
                commandPort: 8899,
                eventPort: 8898,
                protocolFormat: .modern,
                checkCode: "112233",
                cameraUserConfig: CameraUserConfig(
                    customCameraEnabled: true,
                    customCameraURL: "http://camera.local:8080/?action=stream"
                ),
                recentUploadFileURLs: [
                    URL(fileURLWithPath: "/tmp/roundtrip.gcode"),
                    URL(fileURLWithPath: "/tmp/toolhead.3mf")
                ]
            )
        ],
        selectedPrinterID: printerID
    )
    let store = FilePrinterProfileStore(fileURL: fileURL)

    try store.saveDocument(expectedDocument)
    let loadedDocument = try store.loadDocument()

    #expect(loadedDocument == expectedDocument)
}

@Test func filePrinterProfileStoreLoadsLegacyProfilesWithoutRecentFiles() throws {
    let directoryURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("FlashForgeNativeTests-\(UUID().uuidString)", isDirectory: true)
    let fileURL = directoryURL.appendingPathComponent("PrinterProfiles.json")
    defer {
        try? FileManager.default.removeItem(at: directoryURL)
    }

    let printerID = UUID()
    let json = """
    {
      "profiles" : [
        {
          "address" : "192.168.1.66",
          "checkCode" : "112233",
          "commandPort" : 8899,
          "eventPort" : 8898,
          "id" : "\(printerID.uuidString)",
          "model" : "Adventurer 5M",
          "name" : "Legacy Printer",
          "protocolFormat" : "modern",
          "serialNumber" : "SN-LEGACY"
        }
      ],
      "selectedPrinterID" : "\(printerID.uuidString)",
      "version" : 1
    }
    """
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    try json.data(using: .utf8)?.write(to: fileURL)

    let store = FilePrinterProfileStore(fileURL: fileURL)
    let loadedDocument = try store.loadDocument()

    #expect(loadedDocument.profiles.first?.recentUploadFileURLs == [])
}
