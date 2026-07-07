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
                )
            )
        ],
        selectedPrinterID: printerID
    )
    let store = FilePrinterProfileStore(fileURL: fileURL)

    try store.saveDocument(expectedDocument)
    let loadedDocument = try store.loadDocument()

    #expect(loadedDocument == expectedDocument)
}
