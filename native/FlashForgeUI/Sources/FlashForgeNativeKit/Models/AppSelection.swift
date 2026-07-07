import Foundation

public enum AppSelection: Hashable, Identifiable, Sendable {
    case dashboard
    case printer(UUID)

    public var id: String {
        switch self {
        case .dashboard:
            "dashboard"
        case .printer(let id):
            "printer-\(id.uuidString)"
        }
    }
}
