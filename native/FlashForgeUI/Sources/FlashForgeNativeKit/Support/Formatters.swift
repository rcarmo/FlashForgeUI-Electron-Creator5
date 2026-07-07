import Foundation

public enum NativeFormatters {
    public static func temperature(_ reading: TemperatureReading) -> String {
        let current = "\(Int(reading.current.rounded())) C"
        guard let target = reading.target else {
            return current
        }
        return "\(current) / \(Int(target.rounded())) C"
    }

    public static func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    public static func itemCount(_ count: Int, singular: String, plural: String) -> String {
        "\(count) \(count == 1 ? singular : plural)"
    }

    public static func list(_ values: [String]) -> String {
        switch values.count {
        case 0:
            return ""
        case 1:
            return values[0]
        case 2:
            return "\(values[0]) and \(values[1])"
        default:
            let leadingValues = values.dropLast().joined(separator: ", ")
            return "\(leadingValues), and \(values[values.count - 1])"
        }
    }

    public static func duration(_ interval: TimeInterval?) -> String {
        guard let interval else {
            return "Unknown"
        }

        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    public static func relativeUpdate(_ date: Date?) -> String {
        guard let date else {
            return "Not updated yet"
        }
        return date.formatted(.relative(presentation: .named))
    }

    public static func jobFileMenuTitle(_ fileURL: URL) -> String {
        let fileName = fileURL.lastPathComponent
        let parentName = fileURL.deletingLastPathComponent().lastPathComponent

        guard !parentName.isEmpty else {
            return fileName
        }

        return "\(fileName) - \(parentName)"
    }

    public static func jobFileLocation(_ fileURL: URL) -> String? {
        let parentPath = fileURL.deletingLastPathComponent().path
        return parentPath.isEmpty ? nil : parentPath
    }
}
