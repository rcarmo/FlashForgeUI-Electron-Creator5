import SwiftUI

public struct DetailView: View {
    @Bindable private var model: AppModel
    private let onAddPrinter: () -> Void
    private let onShowSettings: () -> Void

    public init(
        model: AppModel,
        onAddPrinter: @escaping () -> Void = {},
        onShowSettings: @escaping () -> Void = {}
    ) {
        self.model = model
        self.onAddPrinter = onAddPrinter
        self.onShowSettings = onShowSettings
    }

    public var body: some View {
        Group {
            switch model.selection {
            case .dashboard, .none:
                DashboardView(model: model, onAddPrinter: onAddPrinter)
            case .printer:
                if let printer = model.selectedPrinter {
                    PrinterDetailView(model: model, printer: printer, onShowSettings: onShowSettings)
                } else {
                    EmptyDetailView(message: "Select a printer.")
                }
            }
        }
    }
}
