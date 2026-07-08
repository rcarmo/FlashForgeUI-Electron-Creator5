import SwiftUI

public struct SidebarView: View {
    @State private var printerSearchText = ""
    @State private var showsForgetPrinterConfirmation = false
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
                        PrinterSidebarRow(
                            printer: printer,
                            statusSummary: model.printerStatusSummary(for: printer),
                            needsUserAttention: model.printerNeedsUserAttention(printer)
                        )
                            .tag(AppSelection.printer(printer.id))
                            .contextMenu {
                                Button("Forget Printer...", role: .destructive) {
                                    model.selection = .printer(printer.id)
                                    showsForgetPrinterConfirmation = true
                                }
                            }
                    }
                }
            }
        }
        .navigationTitle("FlashForgeUI")
        .searchable(text: $printerSearchText, prompt: "Search Printers")
        .onDeleteCommand {
            guard model.canRemoveSelectedPrinter else {
                return
            }
            showsForgetPrinterConfirmation = true
        }
        .confirmationDialog(
            model.selectedPrinterRemovalConfirmationTitle,
            isPresented: $showsForgetPrinterConfirmation,
            titleVisibility: .visible
        ) {
            Button("Forget Printer", role: .destructive) {
                model.removeSelectedPrinter()
            }

            Button("Keep Printer", role: .cancel) {}
        } message: {
            Text(model.selectedPrinterRemovalConfirmationMessage)
        }
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
    let statusSummary: String
    let needsUserAttention: Bool

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(printer.name)
                    .lineLimit(1)
                Text(statusSummary)
                    .font(.caption)
                    .foregroundStyle(needsUserAttention ? .orange : .secondary)
                    .lineLimit(2)
            }
        } icon: {
            Image(systemName: "printer")
        }
    }
}
