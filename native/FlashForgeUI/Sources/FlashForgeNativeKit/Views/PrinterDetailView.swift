import Charts
import SwiftUI
import UniformTypeIdentifiers

public struct PrinterDetailView: View {
    @Environment(\.openURL) private var openURL
    @AppStorage("statusRefreshIntervalSeconds") private var statusRefreshIntervalSeconds = 15
    @State private var showsCancelConfirmation = false
    @State private var showsUploadImporter = false
    @State private var isUploadDropTargeted = false
    @State private var accessCodeInput = ""
    @Bindable private var model: AppModel
    private let printer: PrinterSnapshot
    private let onShowSettings: () -> Void

    public init(
        model: AppModel,
        printer: PrinterSnapshot,
        onShowSettings: @escaping () -> Void = {}
    ) {
        self.model = model
        self.printer = printer
        self.onShowSettings = onShowSettings
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                accessCodePrompt
                detailGrid
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            accessCodeInput = model.checkCode
        }
        .onChange(of: printer.id) {
            accessCodeInput = model.checkCode
        }
        .onChange(of: model.checkCode) {
            accessCodeInput = model.checkCode
        }
        .confirmationDialog(
            "Cancel the current print?",
            isPresented: $showsCancelConfirmation,
            titleVisibility: .visible
        ) {
            Button("Cancel Print", role: .destructive) {
                Task { await model.sendSelectedPrinterJobCommand(.cancel) }
            }
            Button("Keep Printing", role: .cancel) {}
        }
        .fileImporter(
            isPresented: $showsUploadImporter,
            allowedContentTypes: supportedUploadTypes,
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let fileURL = urls.first {
                model.selectUploadFile(fileURL)
            }
        }
        .task(id: autoRefreshTaskKey) {
            await runAutoRefreshLoop()
        }
        .navigationTitle(printer.name)
        .toolbar {
            ToolbarItemGroup {
                if model.shouldShowSelectedPrinterConnectAction {
                    Button {
                        Task { await model.connectSelectedPrinter() }
                    } label: {
                        Label("Connect", systemImage: "link")
                    }
                    .disabled(!model.canConnectSelectedPrinter)
                }

                Button {
                    Task { await model.refreshSelectedPrinterStatus() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(!model.canRefreshSelectedPrinterStatus)

                if let streamURL = model.selectedCameraStreamURL {
                    Button {
                        openURL(streamURL)
                        model.acknowledgeCameraOpen()
                    } label: {
                        Label("Open Camera", systemImage: "video")
                    }
                }

                Button {
                    showsUploadImporter = true
                } label: {
                    Label("Choose Job File", systemImage: "doc.badge.plus")
                }
                .disabled(!model.canChangeSelectedUploadFile)
            }
        }
    }

    private var detailGrid: some View {
        DashboardMasonryLayout(minimumColumnWidth: 420, maximumColumnCount: 2, spacing: 20) {
            cameraSection
                .layoutValue(key: DashboardColumnPreferenceKey.self, value: 0)

            telemetrySection
                .layoutValue(key: DashboardColumnPreferenceKey.self, value: 1)

            controlsSection
                .layoutValue(key: DashboardColumnPreferenceKey.self, value: 0)

            materialStationSection
                .layoutValue(key: DashboardColumnPreferenceKey.self, value: 1)
        }
    }

    private var cameraSection: some View {
        CameraPreviewView(
            config: model.selectedCameraStreamConfig,
            isCameraEnabled: model.cameraEnabled,
            recoveryReadiness: cameraRecoveryReadinessMessage(for:),
            onCameraEnabledChange: { isEnabled in
                model.setSelectedCameraEnabled(isEnabled)
            },
            onOpenStream: { _ in
                model.acknowledgeCameraOpen()
            },
            onRecover: { recoveryAction in
                handleCameraRecovery(recoveryAction)
            }
        )
    }

    @ViewBuilder
    private var materialStationSection: some View {
        if let materialStation = printer.materialStation {
            MaterialStationView(station: materialStation)
        }
    }

    @ViewBuilder
    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 24) {
                headerText
                Spacer(minLength: 24)
                headerActions
            }

            VStack(alignment: .leading, spacing: 16) {
                headerText
                headerActions
            }
        }
    }

    private var headerText: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(printer.name)
                .font(.largeTitle.weight(.semibold))
            Text("\(printer.model) - \(printer.address)")
                .foregroundStyle(.secondary)
            Text(printer.status.rawValue)
                .font(.headline)
                .foregroundStyle(printer.status.isActionable ? .orange : .primary)
            if let activityMessage = model.selectedPrinterActivityMessage {
                Label(activityMessage, systemImage: activitySymbol(for: activityMessage))
                    .font(.callout)
                    .foregroundStyle(isWarningActivity(activityMessage) ? .orange : .secondary)
            }
            if let identitySummary = model.selectedPrinterIdentitySummary {
                Label(identitySummary, systemImage: printer.serialNumber?.isEmpty == false ? "number" : "info.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if let recencySummary = model.selectedPrinterStatusRecencySummary {
                Label(recencySummary, systemImage: "clock")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if let failureSummary = model.selectedPrinterStatusFailureSummary {
                actionableMessage(failureSummary, systemImage: "exclamationmark.triangle", isWarning: true)
            }
            if model.shouldShowSelectedPrinterConnectAction,
               let connectReadinessMessage = model.selectedPrinterConnectReadinessMessage {
                Label(connectReadinessMessage, systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
    private var connectButton: some View {
        Button {
            Task { await model.connectSelectedPrinter() }
        } label: {
            Label(model.isConnecting ? "Connecting" : "Connect", systemImage: "link")
        }
        .controlSize(.large)
        .disabled(!model.canConnectSelectedPrinter)
    }

    private var headerActions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) {
                refreshStatusCluster
                if model.shouldShowSelectedPrinterConnectAction {
                    connectButton
                }
                jobSection
                    .frame(width: 240)
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    refreshStatusCluster
                    if model.shouldShowSelectedPrinterConnectAction {
                        connectButton
                    }
                }
                jobSection
                    .frame(maxWidth: 320, alignment: .leading)
            }
        }
    }

    private var refreshStatusCluster: some View {
        VStack(alignment: .leading, spacing: 8) {
            refreshButton

            if statusRefreshIntervalSeconds > 0 {
                Label("Auto-refresh every \(statusRefreshIntervalSeconds) seconds", systemImage: "clock.arrow.circlepath")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if let refreshReadinessMessage = model.selectedPrinterStatusRefreshReadinessMessage {
                actionableMessage(refreshReadinessMessage, systemImage: "info.circle")
            }
        }
    }

    @ViewBuilder
    private var accessCodePrompt: some View {
        if let promptMessage = model.selectedPrinterAccessCodePromptMessage {
            VStack(alignment: .leading, spacing: 12) {
                Label("Device ID Required", systemImage: "key")
                    .font(.title3.weight(.semibold))

                Text(promptMessage)
                    .foregroundStyle(.secondary)

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: 10) {
                        accessCodeField
                        accessCodeButtons
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        accessCodeField
                        accessCodeButtons
                    }
                }
            }
            .padding(16)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var accessCodeField: some View {
        SecureField("Device ID", text: $accessCodeInput)
            .textFieldStyle(.roundedBorder)
            .frame(minWidth: 180)
            .disabled(model.selectedPrinterProfileChangeReadinessMessage != nil)
            .onSubmit {
                Task { await saveAccessCode(refreshesStatus: true) }
            }
    }

    private var accessCodeButtons: some View {
        HStack(spacing: 8) {
            Button {
                Task { await saveAccessCode(refreshesStatus: false) }
            } label: {
                Label("Save", systemImage: "checkmark")
            }

            Button {
                Task { await saveAccessCode(refreshesStatus: true) }
            } label: {
                Label("Save & Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
        }
        .disabled(!canSubmitAccessCode)
    }

    private var canSubmitAccessCode: Bool {
        !accessCodeInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && model.selectedPrinterProfileChangeReadinessMessage == nil
    }

    @MainActor
    private func saveAccessCode(refreshesStatus: Bool) async {
        guard model.saveSelectedPrinterAccessCode(accessCodeInput) else {
            return
        }

        if refreshesStatus {
            await model.refreshSelectedPrinterStatus()
        }
    }

    @ViewBuilder
    private var jobSection: some View {
        if let job = printer.activeJob {
            VStack(alignment: .leading, spacing: 12) {
                Text("Current Job")
                    .font(.title2.weight(.semibold))
                Text(job.fileName)
                    .font(.headline)
                ProgressView(value: job.progress)
                jobProgressText(job)
                if let jobControlSummary = model.selectedJobControlSummary {
                    Label(jobControlSummary, systemImage: "switch.2")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                jobCommandButtons
                if let jobCommandReadinessMessage {
                    Label(jobCommandReadinessMessage, systemImage: "info.circle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("No Active Print")
                    .font(.title2.weight(.semibold))
                Text(model.printJobIdleSummary(for: printer))
                    .foregroundStyle(.secondary)
                if let pendingJobSummary = model.selectedPendingJobSummary {
                    Label(pendingJobSummary, systemImage: "doc.text")
                        .font(.callout)
                    Label(model.selectedUploadActionSummary, systemImage: "checklist")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func jobProgressText(_ job: PrintJobSnapshot) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                Text(NativeFormatters.percent(job.progress))
                Text("remaining \(NativeFormatters.duration(job.timeRemaining))")
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(NativeFormatters.percent(job.progress))
                Text("remaining \(NativeFormatters.duration(job.timeRemaining))")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var jobCommandButtons: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                pauseButton
                resumeButton
                cancelButton
            }

            VStack(alignment: .leading, spacing: 8) {
                pauseButton
                resumeButton
                cancelButton
            }
        }
        .controlSize(.large)
    }

    private var pauseButton: some View {
        Button {
            Task { await model.sendSelectedPrinterJobCommand(.pause) }
        } label: {
            Label(commandLabel(for: .pause, fallback: "Pause"), systemImage: "pause.fill")
        }
        .disabled(!canSend(.pause))
    }

    private var resumeButton: some View {
        Button {
            Task { await model.sendSelectedPrinterJobCommand(.resume) }
        } label: {
            Label(commandLabel(for: .resume, fallback: "Resume"), systemImage: "play.fill")
        }
        .disabled(!canSend(.resume))
    }

    private var cancelButton: some View {
        Button(role: .destructive) {
            showsCancelConfirmation = true
        } label: {
            Label(commandLabel(for: .cancel, fallback: "Cancel"), systemImage: "xmark.circle")
        }
        .disabled(!canSend(.cancel))
    }

    private var controlsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            uploadDropZone

            if let uploadReadinessMessage = model.selectedUploadReadinessMessage {
                actionableMessage(uploadReadinessMessage, systemImage: "info.circle")
            }
        }
    }

    private func actionableMessage(
        _ message: String,
        systemImage: String,
        isWarning: Bool = false
    ) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Label(message, systemImage: systemImage)
                    .font(.callout)
                    .foregroundStyle(isWarning ? .orange : .secondary)
                if shouldOfferPrinterSettings(for: message) {
                    Button("Printer Settings...") {
                        onShowSettings()
                    }
                    .controlSize(.small)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Label(message, systemImage: systemImage)
                    .font(.callout)
                    .foregroundStyle(isWarning ? .orange : .secondary)
                if shouldOfferPrinterSettings(for: message) {
                    Button("Printer Settings...") {
                        onShowSettings()
                    }
                    .controlSize(.small)
                }
            }
        }
    }

    private func shouldOfferPrinterSettings(for message: String) -> Bool {
        let normalizedMessage = message.lowercased()
        return normalizedMessage.contains("api port")
            || normalizedMessage.contains("printer address")
            || normalizedMessage.contains("serial number")
    }

    private var refreshButton: some View {
        Button {
            Task { await model.refreshSelectedPrinterStatus() }
        } label: {
            Label(model.isRefreshingStatus ? "Refreshing" : "Refresh Status", systemImage: "arrow.clockwise")
        }
        .controlSize(.large)
        .disabled(!model.canRefreshSelectedPrinterStatus)
    }

    private var uploadControls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 10) {
                uploadPrimaryActions
            }

            VStack(alignment: .leading, spacing: 10) {
                uploadPrimaryActions
            }
        }
        .controlSize(.large)
    }

    private var uploadPrimaryActions: some View {
        Group {
            Button {
                showsUploadImporter = true
            } label: {
                Label("Choose Job File", systemImage: "doc.badge.plus")
            }
            .disabled(!model.canChangeSelectedUploadFile)

            recentFilesMenu

            Button {
                model.clearSelectedUploadFile()
            } label: {
                Label("Clear Job File", systemImage: "xmark.circle")
            }
            .disabled(!model.canClearSelectedUploadFile)
        }
    }

    private var uploadOptions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Start after upload", isOn: $model.startPrintAfterUpload)
                .disabled(!model.canChangeSelectedUploadOptions)

            if model.canChooseUploadLeveling {
                Toggle("Level before print", isOn: $model.levelingBeforePrint)
                    .disabled(!model.canChangeSelectedUploadOptions)
            }

            Label(model.selectedUploadActionSummary, systemImage: "checklist")
                .font(.callout)
                .foregroundStyle(.secondary)

            if let uploadOptionReadinessMessage = model.selectedUploadOptionChangeReadinessMessage {
                Label(uploadOptionReadinessMessage, systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var uploadButton: some View {
        Button {
            Task { await model.uploadSelectedJob() }
        } label: {
            Label(model.isUploadingJob ? "Uploading" : "Upload Job", systemImage: "square.and.arrow.up")
        }
        .controlSize(.large)
        .disabled(!model.canUploadSelectedJob)
    }

    private var recentFilesMenu: some View {
        Menu {
            if model.recentUploadFileURLs.isEmpty {
                Text("No Recent Files")
            } else {
                ForEach(model.recentUploadFileSummaries) { recentFile in
                    Button {
                        _ = model.openRecentJobFile(recentFile.fileURL)
                    } label: {
                        Label(
                            recentFile.menuTitle,
                            systemImage: recentFile.isSelected ? "checkmark" : "doc"
                        )
                    }
                }

                Divider()

                Button("Clear Recent", role: .destructive) {
                    model.clearRecentUploadFiles()
                }
            }
        } label: {
            Label("Recent Files", systemImage: "clock")
        }
        .controlSize(.large)
        .disabled(!model.canClearRecentUploadFiles)
    }

    private var selectedUploadFileSummary: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isUploadDropTargeted ? "tray.and.arrow.down.fill" : "doc.text")
                .font(.title2)
                .foregroundStyle(model.selectedUploadFileURL == nil ? .secondary : .primary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(model.selectedUploadFileSummary?.fileName ?? uploadDropPrompt)
                    .font(.headline)
                    .lineLimit(1)

                if let location = model.selectedUploadFileSummary?.location {
                    Text(location)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text("Choose, reopen, or drop a .gcode, .gx, or .3mf file.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(
            isUploadDropTargeted ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 8)
        )
    }

    private var uploadDropZone: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Job File", systemImage: "doc.badge.plus")
                    .font(.headline)

                Spacer()

                uploadButton
            }

            selectedUploadFileSummary

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    uploadControls
                    Spacer(minLength: 12)
                    uploadOptions
                }

                VStack(alignment: .leading, spacing: 12) {
                    uploadControls
                    uploadOptions
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    isUploadDropTargeted ? Color.accentColor : Color.secondary.opacity(0.3),
                    style: StrokeStyle(lineWidth: isUploadDropTargeted ? 2 : 1, dash: [5, 4])
                )
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let fileURL = urls.first else {
                return false
            }

            return model.openJobFile(fileURL)
        } isTargeted: { isTargeted in
            isUploadDropTargeted = isTargeted
        }
    }

    private var uploadDropPrompt: String {
        isUploadDropTargeted ? "Release job file" : "No file selected"
    }

    private func activitySymbol(for message: String) -> String {
        isWarningActivity(message) ? "exclamationmark.triangle" : "info.circle"
    }

    private func isWarningActivity(_ message: String) -> Bool {
        let normalizedMessage = message.lowercased()
        return normalizedMessage.contains("failed")
            || normalizedMessage.hasPrefix("could not")
            || normalizedMessage.contains("rejected")
            || normalizedMessage.contains("invalid")
            || normalizedMessage.contains("missing")
    }

    private var telemetrySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Telemetry")
                .font(.title2.weight(.semibold))

            LazyVGrid(columns: telemetryColumns, alignment: .leading, spacing: 12) {
                ForEach(model.temperatureTelemetryItems(for: printer)) { item in
                    TemperatureTelemetryTile(item: item)
                }
            }

            if !printerDetailItems.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Printer Details")
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: telemetryColumns, alignment: .leading, spacing: 12) {
                        ForEach(printerDetailItems) { item in
                            TelemetryTile(title: item.title, value: item.value)
                        }
                    }
                }
            }
        }
    }

    private var telemetryColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 160), spacing: 12)]
    }

    private var printerDetailItems: [TelemetryItem] {
        var items: [TelemetryItem] = []
        if let material = printer.material {
            items.append(contentsOf: [
                TelemetryItem(title: "Material", value: material.name),
                TelemetryItem(
                    title: "Remaining",
                    value: material.remainingGrams.map { "\(Int($0.rounded())) g" } ?? "Unknown"
                ),
                TelemetryItem(title: "Color", value: material.colorHex)
            ])
        }

        if let info = model.lastPrinterInfo {
            items.append(contentsOf: [
                TelemetryItem(title: "Firmware", value: info.firmwareVersion),
                TelemetryItem(title: "Serial", value: info.serialNumber.isEmpty ? "Unknown" : info.serialNumber),
                TelemetryItem(title: "Volume", value: info.dimensions.isEmpty ? "Unknown" : info.dimensions)
            ])
        }

        if let status = model.lastModernStatus {
            items.append(contentsOf: [
                TelemetryItem(title: "HTTP Model", value: status.modelName),
                TelemetryItem(title: "Toolheads", value: "\(status.nozzleCount)"),
                TelemetryItem(title: "Runtime", value: NativeFormatters.duration(status.printDuration))
            ])
        }

        return items
    }

    private func canSend(_ command: PrinterJobCommand) -> Bool {
        model.canSendSelectedPrinterJobCommand(command)
    }

    private func commandLabel(for command: PrinterJobCommand, fallback: String) -> String {
        model.activeJobCommand == command ? "Sending" : fallback
    }

    private var jobCommandReadinessMessage: String? {
        for command in [PrinterJobCommand.pause, .resume, .cancel] where model.availableJobCommands.contains(command) {
            if let message = model.selectedPrinterJobCommandReadinessMessage(for: command) {
                return message
            }
        }

        return nil
    }

    private var supportedUploadTypes: [UTType] {
        AppModel.supportedUploadFileExtensions.compactMap { UTType(filenameExtension: $0) }
    }

    private var autoRefreshTaskKey: AutoRefreshTaskKey {
        AutoRefreshTaskKey(
            printerID: printer.id,
            intervalSeconds: statusRefreshIntervalSeconds,
            hasSerialNumber: !(printer.serialNumber ?? "").isEmpty,
            trimmedCheckCode: model.checkCode.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private func runAutoRefreshLoop() async {
        guard statusRefreshIntervalSeconds > 0, model.canRefreshSelectedPrinterStatus else {
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

            await model.refreshSelectedPrinterStatusInBackground()
        }
    }

    private func handleCameraRecovery(_ recoveryAction: CameraRecoveryAction) {
        switch recoveryAction {
        case .refreshStatus:
            Task { await model.refreshSelectedPrinterStatus() }
        case .openSettings:
            onShowSettings()
        }
    }

    private func cameraRecoveryReadinessMessage(for recoveryAction: CameraRecoveryAction) -> String? {
        switch recoveryAction {
        case .refreshStatus:
            model.selectedPrinterStatusRefreshReadinessMessage
        case .openSettings:
            nil
        }
    }
}

private struct AutoRefreshTaskKey: Equatable {
    let printerID: UUID
    let intervalSeconds: Int
    let hasSerialNumber: Bool
    let trimmedCheckCode: String
}

private struct TelemetryItem: Identifiable {
    var id: String { title }
    let title: String
    let value: String
}

private struct DashboardColumnPreferenceKey: LayoutValueKey {
    static let defaultValue: Int? = nil
}

private struct DashboardMasonryLayout: Layout {
    let minimumColumnWidth: CGFloat
    let maximumColumnCount: Int
    let spacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let availableWidth = proposal.width ?? minimumColumnWidth
        let columnCount = columnCount(for: availableWidth)
        let columnWidth = widthPerColumn(for: availableWidth, columnCount: columnCount)
        var columnHeights = Array(repeating: CGFloat.zero, count: columnCount)

        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil))
            guard size.width > 0 || size.height > 0 else {
                continue
            }

            let columnIndex = targetColumn(for: subview, in: columnHeights)
            if columnHeights[columnIndex] > 0 {
                columnHeights[columnIndex] += spacing
            }
            columnHeights[columnIndex] += size.height
        }

        return CGSize(width: availableWidth, height: columnHeights.max() ?? 0)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let columnCount = columnCount(for: bounds.width)
        let columnWidth = widthPerColumn(for: bounds.width, columnCount: columnCount)
        var columnHeights = Array(repeating: CGFloat.zero, count: columnCount)

        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil))
            guard size.width > 0 || size.height > 0 else {
                continue
            }

            let columnIndex = targetColumn(for: subview, in: columnHeights)
            if columnHeights[columnIndex] > 0 {
                columnHeights[columnIndex] += spacing
            }

            let origin = CGPoint(
                x: bounds.minX + CGFloat(columnIndex) * (columnWidth + spacing),
                y: bounds.minY + columnHeights[columnIndex]
            )
            subview.place(
                at: origin,
                anchor: .topLeading,
                proposal: ProposedViewSize(width: columnWidth, height: nil)
            )
            columnHeights[columnIndex] += size.height
        }
    }

    private func columnCount(for width: CGFloat) -> Int {
        guard width > 0 else {
            return 1
        }

        let possibleColumns = Int((width + spacing) / (minimumColumnWidth + spacing))
        return min(maximumColumnCount, max(1, possibleColumns))
    }

    private func widthPerColumn(for width: CGFloat, columnCount: Int) -> CGFloat {
        let totalSpacing = CGFloat(max(0, columnCount - 1)) * spacing
        return max(0, (width - totalSpacing) / CGFloat(columnCount))
    }

    private func targetColumn(for subview: LayoutSubviews.Element, in heights: [CGFloat]) -> Int {
        if let preferredColumn = subview[DashboardColumnPreferenceKey.self],
           heights.indices.contains(preferredColumn) {
            return preferredColumn
        }

        return heights.indices.min { lhs, rhs in
            heights[lhs] < heights[rhs]
        } ?? 0
    }
}

private struct TelemetryTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct TemperatureTelemetryTile: View {
    let item: TemperatureTelemetryItem

    var body: some View {
        ZStack {
            temperatureChart
                .opacity(0.35)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)

            VStack(alignment: .leading, spacing: 8) {
                Text(item.title)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text(NativeFormatters.temperature(item.reading))
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                if item.history.count < 2 {
                    Text(item.history.isEmpty ? "Waiting for samples" : "Waiting for trend")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
        }
        .frame(minHeight: 92)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var temperatureChart: some View {
        if item.history.count >= 2 {
            Chart {
                ForEach(item.history) { point in
                    LineMark(
                        x: .value("Time", point.timestamp),
                        y: .value("Current", point.current)
                    )
                    .interpolationMethod(.catmullRom)

                    if let target = point.target, target > 0 {
                        LineMark(
                            x: .value("Time", point.timestamp),
                            y: .value("Target", target)
                        )
                        .foregroundStyle(.secondary.opacity(0.65))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    }
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartLegend(.hidden)
            .chartYScale(domain: 0...chartMaximumTemperature)
        } else {
            Color.clear
        }
    }

    private var chartMaximumTemperature: Double {
        let normalizedID = item.id.lowercased()
        let normalizedTitle = item.title.lowercased()

        if normalizedID == "bed" || normalizedTitle.contains("bed") {
            return 120
        }

        if normalizedID.contains("chamber")
            || normalizedID.contains("enclosure")
            || normalizedTitle.contains("chamber")
            || normalizedTitle.contains("enclosure") {
            return 65
        }

        return 320
    }
}
