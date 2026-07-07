import Foundation

public enum DiscoveryProtocolFormat: String, Codable, Sendable {
    case modern
    case legacy
}

public enum DiscoveryPrinterModel: String, Sendable {
    case ad5x = "AD5X"
    case adventurer5M = "Adventurer 5M"
    case adventurer5MPro = "Adventurer 5M Pro"
    case adventurer4 = "Adventurer 4"
    case adventurer3 = "Adventurer 3"
    case unknown = "Unknown"
}

public enum DiscoveryPrinterStatus: Int, Sendable {
    case ready = 0
    case busy = 1
    case error = 2
    case unknown = 3
}

public struct DiscoveryRemoteInfo: Sendable {
    public var address: String

    public init(address: String) {
        self.address = address
    }
}

public struct DiscoveredPrinterResponse: Identifiable, Hashable, Sendable {
    public var id: String { "\(ipAddress):\(commandPort)" }
    public var model: DiscoveryPrinterModel
    public var protocolFormat: DiscoveryProtocolFormat
    public var name: String
    public var ipAddress: String
    public var commandPort: Int
    public var serialNumber: String?
    public var eventPort: Int?
    public var vendorId: Int?
    public var productId: Int?
    public var productType: Int?
    public var statusCode: Int?
    public var status: DiscoveryPrinterStatus

    public func snapshot() -> PrinterSnapshot {
        PrinterSnapshot(
            name: name.isEmpty ? "Unknown Printer" : name,
            model: model.rawValue,
            address: ipAddress,
            serialNumber: serialNumber,
            commandPort: commandPort,
            eventPort: eventPort,
            protocolFormat: protocolFormat,
            status: status.snapshotStatus,
            nozzleTemperature: TemperatureReading(current: 0),
            bedTemperature: TemperatureReading(current: 0),
            cameraState: .unavailable
        )
    }
}

extension DiscoveryPrinterStatus {
    var snapshotStatus: PrinterStatus {
        switch self {
        case .ready:
            .ready
        case .busy:
            .busy
        case .error:
            .needsAttention
        case .unknown:
            .offline
        }
    }
}
