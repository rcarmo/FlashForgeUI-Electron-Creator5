import SwiftUI

public struct SidebarView: View {
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
        List(selection: $model.selection) {
            Section {
                Label("Overview", systemImage: "gauge.with.dots.needle.bottom.50percent")
                    .tag(AppSelection.dashboard)
            }

            Section("Printers") {
                ForEach(model.printers) { printer in
                    PrinterSidebarRow(printer: printer)
                        .tag(AppSelection.printer(printer.id))
                }
            }
        }
        .navigationTitle("FlashForgeUI")
        .toolbar {
            ToolbarItem {
                Button {
                    onAddPrinter()
                } label: {
                    Label("Add Printer", systemImage: "plus")
                }
                .help("Add printer")
            }

            ToolbarItem {
                Button {
                    Task { await model.discoverPrinters() }
                } label: {
                    Label("Discover", systemImage: "arrow.clockwise")
                }
                .disabled(model.isDiscovering)
                .help("Discover printers")
            }

            ToolbarItem {
                Button {
                    onShowSettings()
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                .help("Settings")
            }
        }
    }
}

private struct PrinterSidebarRow: View {
    let printer: PrinterSnapshot

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(printer.name)
                    .lineLimit(1)
                Text(printer.status.rawValue)
                    .font(.caption)
                    .foregroundStyle(printer.status.isActionable ? .orange : .secondary)
            }
        } icon: {
            Image(systemName: "printer")
        }
    }
}
