import SwiftUI

public struct SidebarView: View {
    @State private var printerSearchText = ""
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
                if filteredPrinters.isEmpty {
                    Text(printerEmptyMessage)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(filteredPrinters) { printer in
                        PrinterSidebarRow(printer: printer)
                            .tag(AppSelection.printer(printer.id))
                    }
                }
            }
        }
        .navigationTitle("FlashForgeUI")
        .searchable(text: $printerSearchText, prompt: "Search Printers")
        .toolbar {
            ToolbarItem {
                Button {
                    onAddPrinter()
                } label: {
                    Label("Add Printer", systemImage: "plus")
                }
                .disabled(!model.canChangeManualPrinterProfile)
                .help("Add printer")
            }

            ToolbarItem {
                Button {
                    Task { await model.discoverPrinters() }
                } label: {
                    Label("Discover", systemImage: "arrow.clockwise")
                }
                .disabled(!model.canDiscoverPrinters)
                .help("Discover printers")
            }

            ToolbarItem {
                #if os(macOS)
                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                }
                .help("Settings")
                #else
                Button {
                    onShowSettings()
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                .help("Settings")
                #endif
            }
        }
    }

    private var filteredPrinters: [PrinterSnapshot] {
        model.printers(matching: printerSearchText)
    }

    private var printerEmptyMessage: String {
        printerSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "No printers"
            : "No matching printers"
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
