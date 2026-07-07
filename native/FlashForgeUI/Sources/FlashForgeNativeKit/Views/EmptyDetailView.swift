import SwiftUI

public struct EmptyDetailView: View {
    private let message: String

    public init(message: String) {
        self.message = message
    }

    public var body: some View {
        ContentUnavailableView {
            Label("Nothing Selected", systemImage: "printer")
        } description: {
            Text(message)
        }
    }
}
