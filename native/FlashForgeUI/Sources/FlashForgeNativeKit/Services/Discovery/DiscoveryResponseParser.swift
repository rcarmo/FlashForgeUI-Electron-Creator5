import Foundation

public struct DiscoveryResponseParser: Sendable {
    private let modernProtocolSize = 276
    private let legacyProtocolSize = 140
    private let legacyAdventurer3ProductId = 0x0008
    private let legacyAdventurer4LiteProductId = 0x0016
    private let legacyAdventurer4ProProductId = 0x001E

    public init() {}

    public func parse(data: Data, remoteInfo: DiscoveryRemoteInfo) -> DiscoveredPrinterResponse? {
        guard !data.isEmpty else {
            return nil
        }

        if data.count >= modernProtocolSize {
            return parseModernProtocol(data: data, remoteInfo: remoteInfo)
        }

        if data.count >= legacyProtocolSize {
            return parseLegacyProtocol(data: data, remoteInfo: remoteInfo)
        }

        return nil
    }

    public func parseModernProtocol(data: Data, remoteInfo: DiscoveryRemoteInfo) -> DiscoveredPrinterResponse? {
        guard data.count >= modernProtocolSize else {
            return nil
        }

        let name = data.utf8String(in: 0x00..<0x84)
        let commandPort = data.uint16(at: 0x84)
        let vendorId = data.uint16(at: 0x86)
        let productId = data.uint16(at: 0x88)
        let statusCode = data.uint16(at: 0x8A)
        let productType = data.uint16(at: 0x8C)
        let eventPort = data.uint16(at: 0x8E)
        let serialNumber = data.utf8String(in: 0x92..<(0x92 + 128))

        return DiscoveredPrinterResponse(
            model: detectModernModel(name: name, productType: productType),
            protocolFormat: .modern,
            name: name,
            ipAddress: remoteInfo.address,
            commandPort: commandPort,
            serialNumber: serialNumber.isEmpty ? nil : serialNumber,
            eventPort: eventPort,
            vendorId: vendorId,
            productId: productId,
            productType: productType,
            statusCode: statusCode,
            status: mapStatusCode(statusCode)
        )
    }

    public func parseLegacyProtocol(data: Data, remoteInfo: DiscoveryRemoteInfo) -> DiscoveredPrinterResponse? {
        guard data.count >= legacyProtocolSize else {
            return nil
        }

        let name = data.utf8String(in: 0x00..<0x80)
        let commandPort = data.uint16(at: 0x84)
        let vendorId = data.uint16(at: 0x86)
        let productId = data.uint16(at: 0x88)
        let statusCode = data.uint16(at: 0x8A)

        return DiscoveredPrinterResponse(
            model: detectLegacyModel(name: name, productId: productId),
            protocolFormat: .legacy,
            name: name,
            ipAddress: remoteInfo.address,
            commandPort: commandPort,
            vendorId: vendorId,
            productId: productId,
            statusCode: statusCode,
            status: mapStatusCode(statusCode)
        )
    }

    public func detectModernModel(name: String, productType: Int) -> DiscoveryPrinterModel {
        let upperName = name.uppercased()

        if upperName == "AD5X" {
            return .ad5x
        }

        if productType == 0x5A02 {
            return upperName.contains("PRO") ? .adventurer5MPro : .adventurer5M
        }

        if upperName.contains("ADVENTURER 5M") || upperName.contains("AD5M") {
            return upperName.contains("PRO") ? .adventurer5MPro : .adventurer5M
        }

        return .unknown
    }

    public func detectLegacyModel(name: String, productId: Int?) -> DiscoveryPrinterModel {
        let upperName = name.uppercased()

        if upperName.contains("ADVENTURER 4") || upperName.contains("ADVENTURER4") || upperName.contains("AD4") {
            return .adventurer4
        }

        if upperName.contains("ADVENTURER 3") || upperName.contains("ADVENTURER3") || upperName.contains("AD3") {
            return .adventurer3
        }

        if productId == legacyAdventurer4LiteProductId || productId == legacyAdventurer4ProProductId {
            return .adventurer4
        }

        if productId == legacyAdventurer3ProductId {
            return .adventurer3
        }

        return .unknown
    }

    public func mapStatusCode(_ statusCode: Int) -> DiscoveryPrinterStatus {
        DiscoveryPrinterStatus(rawValue: statusCode) ?? .unknown
    }
}

private extension Data {
    func utf8String(in range: Range<Int>) -> String {
        let bounds = range.clamped(to: 0..<count)
        guard bounds.lowerBound < bounds.upperBound else {
            return ""
        }

        let bytes = self[bounds]
        let nulIndex = bytes.firstIndex(of: 0) ?? bounds.upperBound
        return String(data: self[bounds.lowerBound..<nulIndex], encoding: .utf8) ?? ""
    }

    func uint16(at offset: Int) -> Int {
        guard offset + 1 < count else {
            return 0
        }
        return (Int(self[offset]) << 8) | Int(self[offset + 1])
    }
}
