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
}
