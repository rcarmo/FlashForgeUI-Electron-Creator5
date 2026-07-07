import Foundation

public protocol PrinterService {
    func discoverPrinters() async throws -> [PrinterSnapshot]
}

public struct PreviewPrinterService: PrinterService {
    public init() {}

    public func discoverPrinters() async throws -> [PrinterSnapshot] {
        [
            PrinterSnapshot(
                name: "Creator 5 Studio",
                model: "FlashForge Creator 5",
                address: "192.168.1.42",
                serialNumber: "SN-CREATOR5",
                commandPort: 8899,
                eventPort: 8898,
                protocolFormat: .modern,
                status: .printing,
                nozzleTemperature: TemperatureReading(current: 218, target: 220),
                bedTemperature: TemperatureReading(current: 59, target: 60),
                activeJob: PrintJobSnapshot(
                    fileName: "camera-bracket.3mf",
                    progress: 0.42,
                    timeRemaining: 7_620
                ),
                material: MaterialSnapshot(name: "PLA Matte", colorHex: "#3A7AFE", remainingGrams: 438),
                cameraState: .available
            ),
            PrinterSnapshot(
                name: "Workshop AD5X",
                model: "FlashForge AD5X",
                address: "192.168.1.77",
                serialNumber: "SN-AD5X",
                commandPort: 8899,
                eventPort: 8898,
                protocolFormat: .modern,
                status: .ready,
                nozzleTemperature: TemperatureReading(current: 29),
                bedTemperature: TemperatureReading(current: 25),
                material: MaterialSnapshot(name: "PETG", colorHex: "#E65728", remainingGrams: 712),
                cameraState: .available
            )
        ]
    }
}
