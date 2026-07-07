import Foundation

public struct PrinterInfoParser: Sendable {
    public init() {}

    public func parse(_ replay: String) -> PrinterInfo? {
        guard !replay.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        var typeName = ""
        var name = ""
        var firmwareVersion = ""
        var serialNumber = ""
        var dimensions = ""
        var macAddress = ""
        var toolCount = ""

        let lines = replay
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != "ok" }

        for line in lines {
            if line.hasPrefix("Machine Type:") {
                typeName = value(after: "Machine Type:", in: line)
            } else if line.hasPrefix("Machine Name:") {
                name = value(after: "Machine Name:", in: line)
            } else if line.hasPrefix("Firmware:") {
                firmwareVersion = value(after: "Firmware:", in: line)
            } else if line.hasPrefix("SN:") {
                serialNumber = value(after: "SN:", in: line)
            } else if line.hasPrefix("Serial Number:") {
                serialNumber = value(after: "Serial Number:", in: line)
            } else if line.hasPrefix("Tool Count:") {
                toolCount = value(after: "Tool Count:", in: line)
            } else if line.hasPrefix("Tool count:") {
                toolCount = value(after: "Tool count:", in: line)
            } else if line.hasPrefix("Mac Address:") {
                macAddress = value(after: "Mac Address:", in: line)
            } else if line.range(of: #"X:\s*\d+\s+Y:\s*\d+\s+Z:\s*\d+"#, options: .regularExpression) != nil {
                dimensions = line
            }
        }

        guard !typeName.isEmpty, !firmwareVersion.isEmpty else {
            return nil
        }

        return PrinterInfo(
            typeName: typeName,
            name: name,
            firmwareVersion: firmwareVersion,
            serialNumber: serialNumber,
            dimensions: dimensions,
            macAddress: macAddress,
            toolCount: toolCount
        )
    }

    private func value(after prefix: String, in line: String) -> String {
        String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
