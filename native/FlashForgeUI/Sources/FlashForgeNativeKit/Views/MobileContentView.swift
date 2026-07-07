import SwiftUI

public struct MobileContentView: View {
    @AppStorage("discoverOnLaunch") private var discoverOnLaunch = true
    @State private var activeSheet: MobileSheet?
    @State private var overviewPath: [MobileRoute] = []
    @State private var printersPath: [MobileRoute] = []
    @State private var selectedTab = MobileAppTab.overview
    @Bindable private var model: AppModel

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack(path: $overviewPath) {
                DashboardView(model: model, onAddPrinter: showAddPrinterSheet) { printer in
                    showPrinter(printer, in: .overview)
                }
                .navigationDestination(for: MobileRoute.self) { route in
                    destination(for: route)
                }
            }
            .tabItem {
                Label("Overview", systemImage: "gauge.with.dots.needle.bottom.50percent")
            }
            .tag(MobileAppTab.overview)

            NavigationStack(path: $printersPath) {
                MobilePrinterListView(model: model, onAddPrinter: showAddPrinterSheet) { printer in
                    showPrinter(printer, in: .printers)
                }
                .navigationDestination(for: MobileRoute.self) { route in
                    destination(for: route)
                }
            }
            .tabItem {
                Label("Printers", systemImage: "printer")
            }
            .tag(MobileAppTab.printers)

            NavigationStack {
                SettingsView(model: model)
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
            .tag(MobileAppTab.settings)
        }
        .task {
            await model.start(discoverOnLaunch: discoverOnLaunch)
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .addPrinter:
                MobileAddPrinterSheetView(model: model)
            }
        }
        .onOpenURL { fileURL in
            guard model.openJobFile(fileURL), let printer = model.selectedPrinter else {
                return
            }

            showPrinter(printer, in: .printers)
        }
    }

    @ViewBuilder
    private func destination(for route: MobileRoute) -> some View {
        switch route {
        case .printer(let printerID):
            MobilePrinterDetailRouteView(
                model: model,
                printerID: printerID,
                onShowSettings: showSettingsTab
            )
        }
    }

    private func showAddPrinterSheet() {
        activeSheet = .addPrinter
    }

    private func showSettingsTab() {
        selectedTab = .settings
    }

    private func showPrinter(_ printer: PrinterSnapshot, in tab: MobileAppTab) {
        model.selection = .printer(printer.id)
        selectedTab = tab

        switch tab {
        case .overview:
            append(.printer(printer.id), to: &overviewPath)
        case .printers:
            append(.printer(printer.id), to: &printersPath)
        case .settings:
            selectedTab = .printers
            append(.printer(printer.id), to: &printersPath)
        }
    }

    private func append(_ route: MobileRoute, to path: inout [MobileRoute]) {
        if path.last != route {
            path.append(route)
        }
    }
}

private enum MobileAppTab: Hashable {
    case overview
    case printers
    case settings
}

private enum MobileRoute: Hashable {
    case printer(UUID)
}

private enum MobileSheet: Identifiable {
    case addPrinter

    var id: String {
        switch self {
        case .addPrinter:
            "addPrinter"
        }
    }
}

private struct MobilePrinterListView: View {
    @State private var printerSearchText = ""
    @Bindable private var model: AppModel
    private let onAddPrinter: () -> Void
    private let onShowPrinter: (PrinterSnapshot) -> Void

    init(
        model: AppModel,
        onAddPrinter: @escaping () -> Void,
        onShowPrinter: @escaping (PrinterSnapshot) -> Void
    ) {
        self.model = model
        self.onAddPrinter = onAddPrinter
        self.onShowPrinter = onShowPrinter
    }

    var body: some View {
        List {
            if filteredPrinters.isEmpty {
                ContentUnavailableView {
                    Label(emptyTitle, systemImage: "printer")
                } description: {
                    Text(emptyMessage)
                } actions: {
                    if printerSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button {
                            onAddPrinter()
                        } label: {
                            Label("Add Printer", systemImage: "plus")
                        }
                    }
                }
            } else {
                ForEach(filteredPrinters) { printer in
                    Button {
                        onShowPrinter(printer)
                    } label: {
                        MobilePrinterRow(printer: printer)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("Printers")
        .searchable(text: $printerSearchText, prompt: "Search Printers")
        .toolbar {
            ToolbarItemGroup(placement: mobileToolbarPlacement) {
                Button {
                    onAddPrinter()
                } label: {
                    Label("Add Printer", systemImage: "plus")
                }

                Button {
                    Task { await model.discoverPrinters() }
                } label: {
                    Label("Discover", systemImage: "arrow.clockwise")
                }
                .disabled(model.isDiscovering)
            }
        }
    }

    private var filteredPrinters: [PrinterSnapshot] {
        model.printers(matching: printerSearchText)
    }

    private var emptyTitle: String {
        printerSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "No Printers Yet"
            : "No Matching Printers"
    }

    private var emptyMessage: String {
        printerSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Discover printers on your network or add one by address."
            : "Try a printer name, model, address, or serial number."
    }

    private var mobileToolbarPlacement: ToolbarItemPlacement {
        #if os(macOS)
        .automatic
        #else
        .topBarTrailing
        #endif
    }
}

private struct MobilePrinterRow: View {
    let printer: PrinterSnapshot

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "printer")
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(printer.name)
                    .font(.headline)
                    .lineLimit(1)
                Text("\(printer.model) - \(printer.address)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(printer.status.rawValue)
                .font(.caption.weight(.semibold))
                .foregroundStyle(printer.status.isActionable ? .orange : .secondary)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}

private struct MobilePrinterDetailRouteView: View {
    @Bindable private var model: AppModel
    let printerID: UUID
    let onShowSettings: () -> Void

    init(model: AppModel, printerID: UUID, onShowSettings: @escaping () -> Void) {
        self.model = model
        self.printerID = printerID
        self.onShowSettings = onShowSettings
    }

    var body: some View {
        Group {
            if let printer = model.printers.first(where: { $0.id == printerID }) {
                PrinterDetailView(model: model, printer: printer, onShowSettings: onShowSettings)
            } else {
                EmptyDetailView(message: "This printer is no longer available.")
            }
        }
        .onAppear {
            model.selection = .printer(printerID)
        }
    }
}

private struct MobileAddPrinterSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable private var model: AppModel

    init(model: AppModel) {
        self.model = model
    }

    var body: some View {
        NavigationStack {
            AddPrinterFormView(model: model) {
                dismiss()
            }
            .navigationTitle("Add Printer")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}
