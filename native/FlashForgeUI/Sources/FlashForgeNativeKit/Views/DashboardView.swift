import SwiftUI

public struct DashboardView: View {
    @AppStorage("statusRefreshIntervalSeconds") private var statusRefreshIntervalSeconds = 15
    @Bindable private var model: AppModel
    private let onAddPrinter: () -> Void
    private let onShowPrinter: (PrinterSnapshot) -> Void

    public init(
        model: AppModel,
        onAddPrinter: @escaping () -> Void = {},
        onShowPrinter: @escaping (PrinterSnapshot) -> Void = { _ in }
    ) {
        self.model = model
        self.onAddPrinter = onAddPrinter
        self.onShowPrinter = onShowPrinter
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                statusGrid
                printerList
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Overview")
        .task(id: autoRefreshTaskKey) {
            await runAutoRefreshLoop()
        }
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 16) {
                headerText

                Spacer()

                headerActions
            }

            VStack(alignment: .leading, spacing: 12) {
                headerText
                headerActions
            }
        }
    }

    private var headerText: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Printer Control")
                .font(.largeTitle.weight(.semibold))
            Text(model.connectionMessage ?? NativeFormatters.relativeUpdate(model.lastUpdated))
                .foregroundStyle(.secondary)
            if statusRefreshIntervalSeconds > 0, model.refreshablePrinterCount > 0 {
                Label("Monitoring every \(statusRefreshIntervalSeconds) seconds", systemImage: "clock.arrow.circlepath")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var headerActions: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    addPrinterButton
                    discoverButton
                    identifyButton
                    refreshStatusesButton
                }

                VStack(alignment: .leading, spacing: 8) {
                    addPrinterButton
                    discoverButton
                    identifyButton
                    refreshStatusesButton
                }
            }

            if let actionReadinessMessage = actionReadinessMessage {
                Label(actionReadinessMessage, systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var addPrinterButton: some View {
        Button {
            onAddPrinter()
        } label: {
            Label("Add Printer", systemImage: "plus")
        }
        .controlSize(.large)
    }

    private var discoverButton: some View {
        Button {
            Task { await model.discoverPrinters() }
        } label: {
            Label(model.isDiscovering ? "Discovering" : "Discover Printers", systemImage: "arrow.clockwise")
        }
        .controlSize(.large)
        .disabled(!model.canDiscoverPrinters)
    }

    private var identifyButton: some View {
        Button {
            Task { await model.connectKnownPrinters() }
        } label: {
            Label(model.isConnectingKnownPrinters ? "Identifying" : "Identify Printers", systemImage: "network")
        }
        .controlSize(.large)
        .disabled(!model.canConnectKnownPrinters)
    }

    private var refreshStatusesButton: some View {
        Button {
            Task { await model.refreshKnownPrinterStatuses() }
        } label: {
            Label(model.isRefreshingAllStatuses ? "Refreshing" : "Refresh Statuses", systemImage: "arrow.triangle.2.circlepath")
        }
        .controlSize(.large)
        .disabled(!model.canRefreshKnownPrinterStatuses)
    }

    private var actionReadinessMessage: String? {
        if let discoveryReadinessMessage = model.discoverPrintersReadinessMessage {
            return discoveryReadinessMessage
        }

        if model.printers.isEmpty {
            return model.connectKnownPrintersReadinessMessage
        }

        return model.refreshKnownPrinterStatusesReadinessMessage
            ?? model.connectKnownPrintersReadinessMessage
    }

    private var statusGrid: some View {
        LazyVGrid(columns: metricColumns, alignment: .leading, spacing: 16) {
            MetricCard(title: "Printers", value: "\(model.printers.count)", symbol: "printer")
            MetricCard(title: "Identified", value: "\(model.identifiedPrinterCount)", symbol: "number")
            MetricCard(title: "Refreshable", value: "\(model.refreshablePrinterCount)", symbol: "checkmark.seal")
            MetricCard(title: "Printing", value: "\(model.activePrintCount)", symbol: "play.circle")
            MetricCard(title: "Needs Attention", value: "\(model.attentionCount)", symbol: "exclamationmark.triangle")
        }
    }

    private var metricColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 180), spacing: 16)]
    }

    private var printerList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Printers")
                .font(.title2.weight(.semibold))

            if model.printers.isEmpty {
                emptyPrinterState
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                ForEach(model.overviewPrinters) { printer in
                    Button {
                        model.selection = .printer(printer.id)
                        onShowPrinter(printer)
                    } label: {
                        PrinterSummaryRow(
                            printer: printer,
                            cameraState: model.resolvedCameraState(for: printer),
                            statusFailureSummary: model.statusFailureSummary(for: printer),
                            statusRefreshContextMessage: model.statusRefreshContextMessage(for: printer),
                            canRefreshStatus: model.canRefreshStatus(for: printer)
                        )
                    }
                    .buttonStyle(PrinterSummaryButtonStyle())
                    .accessibilityHint("Opens printer details")
                }
            }
        }
    }

    private var emptyPrinterState: some View {
        ContentUnavailableView {
            Label("No Printers Yet", systemImage: "printer")
        } description: {
            Text("Discover printers on your network or add one by address.")
        } actions: {
            ViewThatFits(in: .horizontal) {
                HStack {
                    discoverButton
                    addPrinterButton
                }

                VStack {
                    discoverButton
                    addPrinterButton
                }
            }
        }
    }

    private var autoRefreshTaskKey: DashboardRefreshTaskKey {
        DashboardRefreshTaskKey(
            intervalSeconds: statusRefreshIntervalSeconds,
            refreshablePrinterCount: model.refreshablePrinterCount,
            printerIDs: model.printers.map(\.id)
        )
    }

    private func runAutoRefreshLoop() async {
        guard statusRefreshIntervalSeconds > 0, model.refreshablePrinterCount > 0 else {
            return
        }

        while !Task.isCancelled {
            do {
                try await Task.sleep(for: .seconds(statusRefreshIntervalSeconds))
            } catch {
                return
            }

            if Task.isCancelled {
                return
            }

            await model.refreshKnownPrinterStatusesInBackground()
        }
    }
}

private struct DashboardRefreshTaskKey: Equatable {
    let intervalSeconds: Int
    let refreshablePrinterCount: Int
    let printerIDs: [UUID]
}

private struct MetricCard: View {
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.tint)
            Text(value)
                .font(.title.weight(.semibold))
            Text(title)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct PrinterSummaryRow: View {
    let printer: PrinterSnapshot
    let cameraState: CameraState
    let statusFailureSummary: String?
    let statusRefreshContextMessage: String
    let canRefreshStatus: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 16) {
                Image(systemName: "printer")
                    .font(.title2)
                    .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 6) {
                    Text(printer.name)
                        .font(.headline)
                    Text("\(printer.model) - \(printer.address)")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                StatusBadge(status: printer.status)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }

            if let job = printer.activeJob {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label(job.fileName, systemImage: "doc.text")
                            .font(.callout.weight(.medium))
                            .lineLimit(1)
                        Spacer()
                        Text(NativeFormatters.percent(job.progress))
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: job.progress)
                    if let timeRemaining = job.timeRemaining {
                        Text("Remaining \(NativeFormatters.duration(timeRemaining))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) {
                    metadataLabels
                }

                VStack(alignment: .leading, spacing: 6) {
                    metadataLabels
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if let statusFailureSummary {
                Label(statusFailureSummary, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var metadataLabels: some View {
        Label(NativeFormatters.temperature(printer.nozzleTemperature), systemImage: "thermometer.medium")
        Label(NativeFormatters.temperature(printer.bedTemperature), systemImage: "rectangle.3.group")
        Label(cameraState.rawValue, systemImage: "video")
        Label(statusRefreshContextMessage, systemImage: canRefreshStatus ? "checkmark.circle" : "info.circle")
    }
}

private struct PrinterSummaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.quaternary, lineWidth: 1)
            }
            .overlay {
                if configuration.isPressed {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.accentColor.opacity(0.12))
                }
            }
            .scaleEffect(configuration.isPressed ? 0.995 : 1)
    }
}

private struct StatusBadge: View {
    let status: PrinterStatus

    var body: some View {
        Text(status.rawValue)
            .font(.callout.weight(.semibold))
            .foregroundStyle(status.isActionable ? .orange : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.quaternary.opacity(0.5), in: Capsule())
    }
}
