import Foundation

public struct PrinterInfo: Equatable, Sendable {
    public var typeName: String
    public var name: String
    public var firmwareVersion: String
    public var serialNumber: String
    public var dimensions: String
    public var macAddress: String
    public var toolCount: String

    public init(
        typeName: String,
        name: String = "",
        firmwareVersion: String,
        serialNumber: String = "",
        dimensions: String = "",
        macAddress: String = "",
        toolCount: String = ""
    ) {
        self.typeName = typeName
        self.name = name
        self.firmwareVersion = firmwareVersion
        self.serialNumber = serialNumber
        self.dimensions = dimensions
        self.macAddress = macAddress
        self.toolCount = toolCount
    }

    public var displayName: String {
        name.isEmpty ? "Printer" : name
    }
}
