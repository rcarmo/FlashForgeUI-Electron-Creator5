import Foundation
import Observation

@MainActor
@Observable
public final class AppModel {
    nonisolated public static let supportedUploadFileExtensions = ["gcode", "gx", "3mf"]
    nonisolated public static let manualPrinterCheckCodeHelpMessage =
        "Needed later for refresh, upload, and job controls. You can add it now or save it later."

    public var printers: [PrinterSnapshot]
    public var selection: AppSelection? {
        willSet {
            rememberProfileSettings(for: selection)
        }
        didSet {
            loadProfileSettingsForSelection()
            saveProfiles()
            applyPendingOpenedJobFileIfNeeded()
        }
    }
    public var isDiscovering: Bool
    public var isConnecting: Bool
    public var lastUpdated: Date?
    public var connectionMessage: String?
    public var lastPrinterInfo: PrinterInfo? {
        get {
            guard let selectedPrinter else {
                return nil
            }
            return printerInfoByPrinterID[selectedPrinter.id]
        }
        set {
            guard let selectedPrinter else {
                return
            }
            if let newValue {
                printerInfoByPrinterID[selectedPrinter.id] = newValue
            } else {
                printerInfoByPrinterID.removeValue(forKey: selectedPrinter.id)
            }
        }
    }
    public var checkCode: String {
        didSet {
            guard !isApplyingProfileSettings else {
                return
            }
            rememberProfileSettings(for: selection)
            saveProfiles()
        }
    }
    public var isRefreshingStatus: Bool
    public var isRefreshingAllStatuses: Bool
    public var isConnectingKnownPrinters: Bool
    public var isSendingJobCommand: Bool
    public var activeJobCommand: PrinterJobCommand?
    public var selectedUploadFileURL: URL? {
        get {
            guard let selectedPrinter else {
                return nil
            }
            return uploadFileURLsByPrinterID[selectedPrinter.id]
        }
        set {
            guard let selectedPrinter else {
                return
            }
            if let newValue {
                uploadFileURLsByPrinterID[selectedPrinter.id] = newValue
            } else {
                uploadFileURLsByPrinterID.removeValue(forKey: selectedPrinter.id)
            }
        }
    }
    public var startPrintAfterUpload: Bool
    public var levelingBeforePrint: Bool
    public var isUploadingJob: Bool
    public var lastModernStatus: ModernPrinterStatus? {
        get {
            guard let selectedPrinter else {
                return nil
            }
            return modernStatusesByPrinterID[selectedPrinter.id]
        }
        set {
            guard let selectedPrinter else {
                return
            }
            if let newValue {
                modernStatusesByPrinterID[selectedPrinter.id] = newValue
            } else {
                modernStatusesByPrinterID.removeValue(forKey: selectedPrinter.id)
            }
        }
    }
    public var customCameraEnabled: Bool {
        didSet {
            guard !isApplyingProfileSettings else {
                return
            }
            rememberProfileSettings(for: selection)
            saveProfiles()
        }
    }
    public var customCameraURL: String {
        didSet {
            guard !isApplyingProfileSettings else {
                return
            }
            rememberProfileSettings(for: selection)
            saveProfiles()
        }
    }

    private let service: PrinterService
    private let bootstrapClient: PrinterBootstrapClient
    private let modernClient: ModernPrinterHTTPClient
    private let commandClient: ModernPrinterCommandClient
    private let uploadClient: ModernPrinterUploadClient
    private let profileStore: PrinterProfileStore?
    private var checkCodesByPrinterID: [UUID: String]
    private var cameraConfigsByPrinterID: [UUID: CameraUserConfig]
    private var printerInfoByPrinterID: [UUID: PrinterInfo]
    private var modernStatusesByPrinterID: [UUID: ModernPrinterStatus]
    private var statusUpdatedAtByPrinterID: [UUID: Date]
    private var statusFailureMessagesByPrinterID: [UUID: String]
    private var uploadFileURLsByPrinterID: [UUID: URL]
    private var recentUploadFileURLsByPrinterID: [UUID: [URL]]
    private var pendingOpenedJobFileURL: URL?
    private var isApplyingProfileSettings: Bool
    private var hasStarted: Bool

    public init(
        service: PrinterService,
        bootstrapClient: PrinterBootstrapClient = TCPPrinterBootstrapClient(),
        modernClient: ModernPrinterHTTPClient = URLSessionModernPrinterHTTPClient(),
        commandClient: ModernPrinterCommandClient = URLSessionModernPrinterCommandClient(),
        uploadClient: ModernPrinterUploadClient = URLSessionModernPrinterUploadClient(),
        profileStore: PrinterProfileStore? = nil,
        printers: [PrinterSnapshot] = []
    ) {
        self.service = service
        self.bootstrapClient = bootstrapClient
        self.modernClient = modernClient
        self.commandClient = commandClient
        self.uploadClient = uploadClient
        self.profileStore = profileStore
        self.printers = printers
        self.selection = .dashboard
        self.isDiscovering = false
        self.isConnecting = false
        self.isRefreshingStatus = false
        self.isRefreshingAllStatuses = false
        self.isConnectingKnownPrinters = false
        self.isSendingJobCommand = false
        self.activeJobCommand = nil
        self.startPrintAfterUpload = true
        self.levelingBeforePrint = true
        self.isUploadingJob = false
        self.lastUpdated = nil
        self.customCameraEnabled = false
        self.customCameraURL = ""
        self.checkCode = ""
        self.checkCodesByPrinterID = [:]
        self.cameraConfigsByPrinterID = [:]
        self.printerInfoByPrinterID = [:]
        self.modernStatusesByPrinterID = [:]
        self.statusUpdatedAtByPrinterID = [:]
        self.statusFailureMessagesByPrinterID = [:]
        self.uploadFileURLsByPrinterID = [:]
        self.recentUploadFileURLsByPrinterID = [:]
        self.pendingOpenedJobFileURL = nil
        self.isApplyingProfileSettings = false
        self.hasStarted = false
        self.connectionMessage = printers.isEmpty ? "Discover printers on your local network." : nil

        if printers.isEmpty {
            loadSavedProfiles()
        }
    }

    public var selectedPrinter: PrinterSnapshot? {
        guard case .printer(let id) = selection else {
            return nil
        }
        return printers.first { $0.id == id }
    }

    public var hasSelectedPrinterCheckCode: Bool {
        guard let printer = selectedPrinter else {
            return false
        }

        return storedCheckCode(for: printer.id) != nil
    }

    public var selectedPrinterCheckCodeStatusMessage: String? {
        guard selectedPrinter != nil else {
            return nil
        }

        return hasSelectedPrinterCheckCode
            ? "Check code saved for this printer."
            : "Needed for refresh, upload, and job controls."
    }

    public var canClearSelectedPrinterCheckCode: Bool {
        hasSelectedPrinterCheckCode && selectedPrinterProfileChangeReadinessMessage == nil
    }

    public func clearSelectedPrinterCheckCode() {
        guard canClearSelectedPrinterCheckCode else {
            if let readinessMessage = selectedPrinterProfileChangeReadinessMessage {
                connectionMessage = readinessMessage
            }
            return
        }

        checkCode = ""
        connectionMessage = "Check code cleared for this printer."
    }

    public var activePrintCount: Int {
        printers.filter { $0.activeJob != nil }.count
    }

    public var attentionCount: Int {
        printers.filter { $0.status.isActionable }.count
    }

    public var overviewPrinters: [PrinterSnapshot] {
        printers.sorted { lhs, rhs in
            let leftPriority = overviewPriority(for: lhs)
            let rightPriority = overviewPriority(for: rhs)
            if leftPriority != rightPriority {
                return leftPriority < rightPriority
            }

            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    public func printers(matching searchText: String) -> [PrinterSnapshot] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return printers
        }

        return printers.filter { printer in
            printer.searchableFields.contains { field in
                field.localizedCaseInsensitiveContains(query)
            }
        }
    }

    public var identifiedPrinterCount: Int {
        printers.filter { !($0.serialNumber ?? "").isEmpty }.count
    }

    public var selectedPrinterIdentitySummary: String? {
        guard let printer = selectedPrinter else {
            return nil
        }

        guard let serialNumber = printer.serialNumber, !serialNumber.isEmpty else {
            return "Connect to identify serial number."
        }

        return "Serial \(serialNumber)"
    }

    public var selectedPrinterStatusRecencySummary: String? {
        guard let printer = selectedPrinter else {
            return nil
        }

        guard let lastSelectedStatusUpdate = statusUpdatedAtByPrinterID[printer.id] else {
            return "Status not refreshed yet."
        }

        return "Updated \(NativeFormatters.relativeUpdate(lastSelectedStatusUpdate))"
    }

    public var selectedPrinterStatusFailureSummary: String? {
        guard let printer = selectedPrinter else {
            return nil
        }

        return statusFailureSummary(for: printer)
    }

    public var selectedPrinterActivityMessage: String? {
        guard selectedPrinter != nil else {
            return nil
        }

        let trimmedMessage = connectionMessage?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedMessage.isEmpty ? nil : trimmedMessage
    }

    public func statusFailureSummary(for printer: PrinterSnapshot) -> String? {
        statusFailureMessagesByPrinterID[printer.id]
    }

    public var availableJobCommands: Set<PrinterJobCommand> {
        guard let printer = selectedPrinter else {
            return []
        }

        switch printer.status {
        case .printing:
            return [.pause, .cancel]
        case .paused:
            return [.resume, .cancel]
        case .busy:
            return [.cancel]
        case .ready, .offline, .needsAttention:
            return []
        }
    }

    public var selectedJobControlSummary: String? {
        guard selectedPrinter?.activeJob != nil else {
            return nil
        }

        let availableCommands = [PrinterJobCommand.pause, .resume, .cancel]
            .filter { availableJobCommands.contains($0) }

        guard !availableCommands.isEmpty else {
            return "No job controls are available for this printer state."
        }

        let labels = availableCommands.map(\.displayName)
        return "\(NativeFormatters.list(labels)) available."
    }

    public func canSendSelectedPrinterJobCommand(_ command: PrinterJobCommand) -> Bool {
        selectedPrinterJobCommandReadinessMessage(for: command) == nil
    }

    public var canDiscoverPrinters: Bool {
        discoverPrintersReadinessMessage == nil
    }

    public var discoverPrintersReadinessMessage: String? {
        if isDiscovering {
            return "Discovery in progress."
        }

        if isConnecting {
            return "Connecting to the selected printer."
        }

        if isConnectingKnownPrinters {
            return "Identifying printers."
        }

        if isRefreshingStatus {
            return "Refreshing the selected printer."
        }

        if isRefreshingAllStatuses {
            return "Refreshing printer statuses."
        }

        if isUploadingJob {
            return "Upload in progress."
        }

        if isSendingJobCommand {
            return "Sending job command."
        }

        return nil
    }

    public func selectedPrinterJobCommandReadinessMessage(for command: PrinterJobCommand) -> String? {
        if isSendingJobCommand {
            return activeJobCommand == command ? "Sending \(command.rawValue)." : "Sending another job command."
        }

        if isDiscovering {
            return "Discovery in progress."
        }

        if isConnecting {
            return "Connecting to this printer."
        }

        if isConnectingKnownPrinters {
            return "Identifying printers."
        }

        if isRefreshingStatus {
            return "Refreshing this printer."
        }

        if isRefreshingAllStatuses {
            return "Refreshing printer statuses."
        }

        if isUploadingJob {
            return "Upload in progress."
        }

        guard let printer = selectedPrinter else {
            return "Select a printer first."
        }

        guard availableJobCommands.contains(command) else {
            return "That job action is not available for the selected printer."
        }

        guard let serialNumber = printer.serialNumber, !serialNumber.isEmpty else {
            return "This printer did not report a serial number."
        }

        guard storedCheckCode(for: printer.id) != nil else {
            return "Enter the printer check code to control this job."
        }

        return nil
    }

    public var canUploadSelectedJob: Bool {
        selectedUploadReadinessMessage == nil
    }

    public var selectedUploadReadinessMessage: String? {
        if isUploadingJob {
            return "Upload in progress."
        }

        if isDiscovering {
            return "Discovery in progress."
        }

        if isConnecting {
            return "Connecting to this printer."
        }

        if isConnectingKnownPrinters {
            return "Identifying printers."
        }

        if isRefreshingStatus {
            return "Refreshing this printer."
        }

        if isRefreshingAllStatuses {
            return "Refreshing printer statuses."
        }

        if isSendingJobCommand {
            return "Sending job command."
        }

        guard let printer = selectedPrinter else {
            return "Select a printer first."
        }

        guard let fileURL = selectedUploadFileURL else {
            return "Choose a job file first."
        }

        guard isSupportedUploadFile(fileURL) else {
            return "Choose a .gcode, .gx, or .3mf file."
        }

        guard let serialNumber = printer.serialNumber, !serialNumber.isEmpty else {
            return "This printer did not report a serial number."
        }

        guard storedCheckCode(for: printer.id) != nil else {
            return "Enter the printer check code to upload a job."
        }

        guard doesUploadFileExist(fileURL) else {
            return "Choose the job file again."
        }

        return nil
    }

    public var refreshablePrinterCount: Int {
        printers.filter(isStatusRefreshable).count
    }

    public func canRefreshStatus(for printer: PrinterSnapshot) -> Bool {
        isStatusRefreshable(printer)
    }

    public func statusRefreshContextMessage(for printer: PrinterSnapshot) -> String {
        guard let serialNumber = printer.serialNumber, !serialNumber.isEmpty else {
            return "Identify printer first."
        }

        guard storedCheckCode(for: printer.id) != nil else {
            return "Needs check code."
        }

        return "Ready to refresh."
    }

    public var canConnectSelectedPrinter: Bool {
        selectedPrinterConnectReadinessMessage == nil
    }

    public var selectedPrinterConnectReadinessMessage: String? {
        if isDiscovering {
            return "Discovery in progress."
        }

        if isConnecting {
            return "Connecting to this printer."
        }

        if isConnectingKnownPrinters {
            return "Identifying printers."
        }

        if isRefreshingStatus {
            return "Refreshing this printer."
        }

        if isRefreshingAllStatuses {
            return "Refreshing printer statuses."
        }

        if isUploadingJob {
            return "Upload in progress."
        }

        if isSendingJobCommand {
            return "Sending job command."
        }

        guard selectedPrinter != nil else {
            return "Select a printer first."
        }

        return nil
    }

    public var canRefreshSelectedPrinterStatus: Bool {
        selectedPrinterStatusRefreshReadinessMessage == nil
    }

    public var selectedPrinterStatusRefreshReadinessMessage: String? {
        if isDiscovering {
            return "Discovery in progress."
        }

        if isRefreshingStatus {
            return "Refreshing this printer."
        }

        if isRefreshingAllStatuses {
            return "Refreshing printer statuses."
        }

        if isConnecting {
            return "Connecting to this printer."
        }

        if isConnectingKnownPrinters {
            return "Identifying printers."
        }

        if isUploadingJob {
            return "Upload in progress."
        }

        if isSendingJobCommand {
            return "Sending job command."
        }

        guard let printer = selectedPrinter else {
            return "Select a printer first."
        }

        guard let serialNumber = printer.serialNumber, !serialNumber.isEmpty else {
            return "This printer did not report a serial number."
        }

        guard storedCheckCode(for: printer.id) != nil else {
            return "Enter the printer check code to refresh status."
        }

        return nil
    }

    public var canRefreshKnownPrinterStatuses: Bool {
        refreshKnownPrinterStatusesReadinessMessage == nil
    }

    public var canConnectKnownPrinters: Bool {
        connectKnownPrintersReadinessMessage == nil
    }

    public var connectKnownPrintersReadinessMessage: String? {
        if isDiscovering {
            return "Discovery in progress."
        }

        if isConnectingKnownPrinters {
            return "Identifying printers."
        }

        if isConnecting {
            return "Connecting to the selected printer."
        }

        if isRefreshingStatus {
            return "Refreshing the selected printer."
        }

        if isRefreshingAllStatuses {
            return "Refreshing printer statuses."
        }

        if isUploadingJob {
            return "Upload in progress."
        }

        if isSendingJobCommand {
            return "Sending job command."
        }

        guard !printers.isEmpty else {
            return "Add or discover printers first."
        }

        return nil
    }

    public var refreshKnownPrinterStatusesReadinessMessage: String? {
        if isDiscovering {
            return "Discovery in progress."
        }

        if isRefreshingAllStatuses {
            return "Refreshing printer statuses."
        }

        if isRefreshingStatus {
            return "Refreshing the selected printer."
        }

        if isConnecting {
            return "Connecting to the selected printer."
        }

        if isConnectingKnownPrinters {
            return "Identifying printers."
        }

        if isUploadingJob {
            return "Upload in progress."
        }

        if isSendingJobCommand {
            return "Sending job command."
        }

        guard !printers.isEmpty else {
            return "Add or discover printers first."
        }

        guard refreshablePrinterCount > 0 else {
            return "Identify printers and save check codes before refreshing statuses."
        }

        return nil
    }

    public var selectedUploadFileName: String {
        selectedUploadFileURL?.lastPathComponent ?? "No file selected"
    }

    public var selectedUploadFileSummary: JobFileSummary? {
        selectedUploadFileURL.map { JobFileSummary(fileURL: $0, isSelected: true) }
    }

    public var selectedPendingJobSummary: String? {
        guard selectedUploadFileURL != nil else {
            return nil
        }

        return "\(selectedUploadFileName) selected for upload."
    }

    public var selectedUploadActionSummary: String {
        if startPrintAfterUpload {
            return levelingBeforePrint
                ? "Upload, level the bed, then start printing."
                : "Upload, then start printing without bed leveling."
        }

        return "Upload only. The print will stay on the printer until you start it."
    }

    public var canChooseUploadLeveling: Bool {
        startPrintAfterUpload
    }

    public var canChangeSelectedUploadOptions: Bool {
        selectedUploadOptionChangeReadinessMessage == nil
    }

    public var selectedUploadOptionChangeReadinessMessage: String? {
        if isUploadingJob {
            return "Upload in progress."
        }

        return nil
    }

    public var canClearSelectedUploadFile: Bool {
        selectedUploadFileURL != nil && canChangeSelectedUploadFile
    }

    public var canChangeSelectedUploadFile: Bool {
        selectedUploadFileChangeReadinessMessage == nil
    }

    public var selectedUploadFileChangeReadinessMessage: String? {
        if isUploadingJob {
            return "Upload in progress."
        }

        guard !printers.isEmpty else {
            return "Add or discover a printer before opening a job file."
        }

        return nil
    }

    public var recentUploadFileURLs: [URL] {
        guard let selectedPrinter else {
            return []
        }

        return recentUploadFileURLsByPrinterID[selectedPrinter.id] ?? []
    }

    public var recentUploadFileSummaries: [JobFileSummary] {
        recentUploadFileURLs.map { fileURL in
            JobFileSummary(fileURL: fileURL, isSelected: fileURL == selectedUploadFileURL)
        }
    }

    public var canClearRecentUploadFiles: Bool {
        !recentUploadFileURLs.isEmpty && canChangeSelectedUploadFile
    }

    public var selectedCameraStreamConfig: CameraStreamConfig {
        guard let printer = selectedPrinter else {
            return CameraStreamConfig(
                sourceType: .none,
                isAvailable: false,
                unavailableReason: "Select a printer first."
            )
        }

        return cameraStreamConfig(for: printer)
    }

    public func cameraStreamConfig(for printer: PrinterSnapshot) -> CameraStreamConfig {
        let status = modernStatusesByPrinterID[printer.id]
        let fallbackURL = supportsLocalCameraFallback(printer: printer, status: status)
            ? CameraStreamResolver.flashForgeMJPEGURL(ipAddress: printer.address)
            : ""

        return CameraStreamResolver.resolve(
            userConfig: cameraConfigsByPrinterID[printer.id] ?? CameraUserConfig(),
            cameraFeatures: CameraFeatureConfig(
                oemStreamURL: status?.cameraStreamURL ?? "",
                fallbackStreamURL: fallbackURL
            )
        )
    }

    public func resolvedCameraState(for printer: PrinterSnapshot) -> CameraState {
        cameraStreamConfig(for: printer).isAvailable ? .available : printer.cameraState
    }

    public var selectedCameraStreamURL: URL? {
        let config = selectedCameraStreamConfig
        guard config.isAvailable else {
            return nil
        }
        return config.streamURL
    }

    public var selectedCameraUserConfig: CameraUserConfig {
        CameraUserConfig(
            customCameraEnabled: customCameraEnabled,
            customCameraURL: customCameraURL
        )
    }

    public var canOpenSelectedCamera: Bool {
        selectedCameraStreamURL != nil
    }

    public var canResetSelectedCameraSettings: Bool {
        guard selectedPrinter != nil else {
            return false
        }

        return selectedPrinterProfileChangeReadinessMessage == nil
            && (customCameraEnabled || !customCameraURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    public func resetSelectedCameraSettings() {
        guard canResetSelectedCameraSettings else {
            if let readinessMessage = selectedPrinterProfileChangeReadinessMessage {
                connectionMessage = readinessMessage
            }
            return
        }

        customCameraEnabled = false
        customCameraURL = ""
        connectionMessage = "Camera settings reset for this printer."
    }

    public var canRemoveSelectedPrinter: Bool {
        guard let selectedPrinter else {
            return false
        }

        return !isPreviewPrinter(selectedPrinter) && selectedPrinterProfileChangeReadinessMessage == nil
    }

    public var selectedPrinterProfileChangeReadinessMessage: String? {
        if isDiscovering {
            return "Discovery in progress."
        }

        if isConnecting {
            return "Connecting to the selected printer."
        }

        if isConnectingKnownPrinters {
            return "Identifying printers."
        }

        if isRefreshingStatus {
            return "Refreshing the selected printer."
        }

        if isRefreshingAllStatuses {
            return "Refreshing printer statuses."
        }

        if isUploadingJob {
            return "Upload in progress."
        }

        if isSendingJobCommand {
            return "Sending job command."
        }

        return nil
    }

    public var selectedPrinterRemovalConfirmationTitle: String {
        guard let printer = selectedPrinter else {
            return "Forget selected printer?"
        }

        return "Forget \(printer.name)?"
    }

    public var selectedPrinterRemovalConfirmationMessage: String {
        "This removes the saved profile, check code, camera settings, and cached status from this app."
    }

    public var canOpenJobFile: Bool {
        selectedUploadFileChangeReadinessMessage == nil
    }

    public var manualPrinterProfileChangeReadinessMessage: String? {
        selectedPrinterProfileChangeReadinessMessage
    }

    public func manualPrinterAddressPreview(for address: String) -> String? {
        guard let normalizedAddress = normalizedManualPrinterAddress(address) else {
            return nil
        }

        return "Will save as \(normalizedAddress)."
    }

    public func manualPrinterAddressValidationMessage(for address: String) -> String? {
        let trimmedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAddress.isEmpty else {
            return nil
        }

        return normalizedManualPrinterAddress(address) == nil
            ? "Enter a valid printer address or URL."
            : nil
    }

    public func canSubmitManualPrinterAddress(_ address: String) -> Bool {
        manualPrinterProfileChangeReadinessMessage == nil
            && normalizedManualPrinterAddress(address) != nil
    }

    public func start(discoverOnLaunch: Bool) async {
        guard !hasStarted else {
            return
        }

        hasStarted = true
        if discoverOnLaunch {
            await discoverPrinters()
        }
    }

    public func selectUploadFile(_ fileURL: URL) {
        if let readinessMessage = selectedUploadFileChangeReadinessMessage {
            connectionMessage = readinessMessage
            return
        }

        guard selectedPrinter != nil else {
            connectionMessage = "Select a printer first."
            return
        }

        guard isSupportedUploadFile(fileURL) else {
            connectionMessage = "Choose a .gcode, .gx, or .3mf file."
            return
        }

        setSelectedUploadFile(fileURL)
    }

    @discardableResult
    public func openJobFile(_ fileURL: URL) -> Bool {
        if let readinessMessage = selectedUploadFileChangeReadinessMessage {
            connectionMessage = readinessMessage
            return false
        }

        guard isSupportedUploadFile(fileURL) else {
            connectionMessage = "Choose a .gcode, .gx, or .3mf file."
            return false
        }

        guard !printers.isEmpty else {
            connectionMessage = "Add or discover a printer before opening a job file."
            return false
        }

        if selectedPrinter == nil, printers.count == 1, let printer = printers.first {
            selection = .printer(printer.id)
        }

        guard selectedPrinter != nil else {
            pendingOpenedJobFileURL = fileURL
            connectionMessage = "Select a printer to use \(fileURL.lastPathComponent)."
            return false
        }

        setSelectedUploadFile(fileURL)
        return true
    }

    @discardableResult
    public func openRecentJobFile(_ fileURL: URL) -> Bool {
        if let readinessMessage = selectedUploadFileChangeReadinessMessage {
            connectionMessage = readinessMessage
            return false
        }

        guard let selectedPrinter else {
            connectionMessage = "Select a printer first."
            return false
        }

        guard isSupportedUploadFile(fileURL) else {
            removeRecentUploadFile(fileURL, for: selectedPrinter.id)
            connectionMessage = "Choose a .gcode, .gx, or .3mf file."
            return false
        }

        guard doesUploadFileExist(fileURL) else {
            removeRecentUploadFile(fileURL, for: selectedPrinter.id)
            if selectedUploadFileURL == fileURL {
                selectedUploadFileURL = nil
            }
            connectionMessage = "\(fileURL.lastPathComponent) is no longer available. Choose the job file again."
            return false
        }

        setSelectedUploadFile(fileURL)
        return true
    }

    public func clearSelectedUploadFile() {
        guard canClearSelectedUploadFile else {
            if let readinessMessage = selectedUploadFileChangeReadinessMessage {
                connectionMessage = readinessMessage
            }
            return
        }

        selectedUploadFileURL = nil
        connectionMessage = "Selected job file cleared."
    }

    public func clearRecentUploadFiles() {
        guard canClearRecentUploadFiles else {
            if let readinessMessage = selectedUploadFileChangeReadinessMessage {
                connectionMessage = readinessMessage
            }
            return
        }

        guard let selectedPrinter else {
            return
        }

        recentUploadFileURLsByPrinterID.removeValue(forKey: selectedPrinter.id)
        saveProfiles()
        connectionMessage = "Recent job files cleared."
    }

    public func acknowledgeCameraOpen() {
        let config = selectedCameraStreamConfig
        if config.isAvailable, let streamURL = config.streamURL {
            switch config.streamType {
            case .mjpeg:
                connectionMessage = "Camera preview ready: \(streamURL.absoluteString)"
            case .rtsp:
                connectionMessage = "Opening RTSP stream in the default app: \(streamURL.absoluteString)"
            case nil:
                connectionMessage = "Opening camera stream: \(streamURL.absoluteString)"
            }
        } else {
            connectionMessage = config.unavailableReason ?? "Camera is not available."
        }
    }

    @discardableResult
    public func addManualPrinter(name: String, address: String, checkCode: String = "") -> Bool {
        if let readinessMessage = manualPrinterProfileChangeReadinessMessage {
            connectionMessage = readinessMessage
            return false
        }

        let trimmedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAddress.isEmpty else {
            connectionMessage = "Enter the printer address."
            return false
        }

        guard let normalizedAddress = normalizedManualPrinterAddress(address) else {
            connectionMessage = "Enter a valid printer address or URL."
            return false
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCheckCode = checkCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = trimmedName.isEmpty ? normalizedAddress : trimmedName

        if let index = printers.firstIndex(where: {
            $0.address == normalizedAddress && ($0.commandPort ?? 8899) == 8899
        }) {
            let existingPrinter = printers[index]
            printers[index].name = displayName
            printers[index].model = existingPrinter.model == "Manual Printer" ? "Manual Printer" : existingPrinter.model
            printers[index].address = normalizedAddress
            printers[index].commandPort = existingPrinter.commandPort ?? 8899
            printers[index].eventPort = existingPrinter.eventPort ?? 8898
            printers[index].protocolFormat = existingPrinter.protocolFormat ?? .modern

            selection = .printer(printers[index].id)
            if !trimmedCheckCode.isEmpty {
                self.checkCode = trimmedCheckCode
            }
            connectionMessage = "Updated \(displayName)."
            return true
        }

        let printer = PrinterSnapshot(
            name: displayName,
            model: "Manual Printer",
            address: normalizedAddress,
            commandPort: 8899,
            eventPort: 8898,
            protocolFormat: .modern,
            status: .offline,
            nozzleTemperature: TemperatureReading(current: 0),
            bedTemperature: TemperatureReading(current: 0)
        )

        printers.append(printer)
        if !trimmedCheckCode.isEmpty {
            checkCodesByPrinterID[printer.id] = trimmedCheckCode
        }
        selection = .printer(printer.id)
        connectionMessage = "Added \(displayName). Connect to identify it."
        return true
    }

    public func removeSelectedPrinter() {
        guard let printer = selectedPrinter else {
            connectionMessage = "Select a saved printer to forget."
            return
        }

        if let readinessMessage = selectedPrinterProfileChangeReadinessMessage {
            connectionMessage = readinessMessage
            return
        }

        guard canRemoveSelectedPrinter else {
            connectionMessage = "Select a saved printer to forget."
            return
        }

        let removedPrinterID = printer.id
        let removedPrinterName = printer.name
        guard let removedIndex = printers.firstIndex(where: { $0.id == removedPrinterID }) else {
            return
        }

        printers.remove(at: removedIndex)

        let nextPrinter = printers.indices.contains(removedIndex)
            ? printers[removedIndex]
            : printers.last

        if let nextPrinter {
            selection = .printer(nextPrinter.id)
        } else {
            selection = .dashboard
        }

        checkCodesByPrinterID.removeValue(forKey: removedPrinterID)
        cameraConfigsByPrinterID.removeValue(forKey: removedPrinterID)
        printerInfoByPrinterID.removeValue(forKey: removedPrinterID)
        modernStatusesByPrinterID.removeValue(forKey: removedPrinterID)
        statusUpdatedAtByPrinterID.removeValue(forKey: removedPrinterID)
        statusFailureMessagesByPrinterID.removeValue(forKey: removedPrinterID)
        uploadFileURLsByPrinterID.removeValue(forKey: removedPrinterID)
        recentUploadFileURLsByPrinterID.removeValue(forKey: removedPrinterID)
        saveProfiles()
        connectionMessage = "Forgot \(removedPrinterName)."
    }

    public func uploadSelectedJob() async {
        guard let printer = selectedPrinter else {
            connectionMessage = "Select a printer first."
            return
        }

        guard let fileURL = selectedUploadFileURL else {
            connectionMessage = "Choose a job file first."
            return
        }

        guard isSupportedUploadFile(fileURL) else {
            connectionMessage = "Choose a .gcode, .gx, or .3mf file."
            return
        }

        guard let serialNumber = printer.serialNumber, !serialNumber.isEmpty else {
            connectionMessage = "This printer did not report a serial number."
            return
        }

        let trimmedCheckCode = checkCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCheckCode.isEmpty else {
            connectionMessage = "Enter the printer check code to upload a job."
            return
        }

        guard doesUploadFileExist(fileURL) else {
            selectedUploadFileURL = nil
            connectionMessage = "Choose the job file again."
            return
        }

        isUploadingJob = true
        connectionMessage = "Uploading \(fileURL.lastPathComponent)..."
        defer { isUploadingJob = false }

        let didStartAccessing = fileURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }

        do {
            try await uploadClient.upload(
                PrinterUploadRequest(
                    fileURL: fileURL,
                    startPrint: startPrintAfterUpload,
                    levelingBeforePrint: startPrintAfterUpload && levelingBeforePrint,
                    firmwareVersion: lastModernStatus?.firmwareVersion ?? lastPrinterInfo?.firmwareVersion
                ),
                host: printer.address,
                port: UInt16(printer.eventPort ?? 8898),
                serialNumber: serialNumber,
                checkCode: trimmedCheckCode
            )
            applyUploadSuccess(fileURL: fileURL, printerID: printer.id)
            if startPrintAfterUpload {
                _ = await refreshStatus(
                    for: printer,
                    announcesProgress: false,
                    reportsBackgroundFailure: false
                )
            }
            lastUpdated = Date()
            connectionMessage = startPrintAfterUpload ? "Uploaded and started \(fileURL.lastPathComponent)." : "Uploaded \(fileURL.lastPathComponent)."
        } catch {
            connectionMessage = uploadFailureMessage(for: error)
        }
    }

    public func sendSelectedPrinterJobCommand(_ command: PrinterJobCommand) async {
        if let readinessMessage = selectedPrinterJobCommandReadinessMessage(for: command) {
            connectionMessage = readinessMessage
            return
        }

        guard let printer = selectedPrinter,
              let serialNumber = printer.serialNumber,
              let trimmedCheckCode = storedCheckCode(for: printer.id) else {
            return
        }

        isSendingJobCommand = true
        activeJobCommand = command
        connectionMessage = "Sending \(command.rawValue) to \(printer.name)..."
        defer {
            isSendingJobCommand = false
            activeJobCommand = nil
        }

        do {
            try await commandClient.sendJobCommand(
                command,
                host: printer.address,
                port: UInt16(printer.eventPort ?? 8898),
                serialNumber: serialNumber,
                checkCode: trimmedCheckCode
            )
            applyOptimisticState(for: command, printerID: printer.id)
            _ = await refreshStatus(
                for: printer,
                announcesProgress: false,
                reportsBackgroundFailure: false
            )
            lastUpdated = Date()
            connectionMessage = command.successMessage
        } catch {
            connectionMessage = jobCommandFailureMessage(for: command, error: error)
        }
    }

    public func discoverPrinters() async {
        if let readinessMessage = discoverPrintersReadinessMessage {
            connectionMessage = readinessMessage
            return
        }

        isDiscovering = true
        connectionMessage = nil
        defer { isDiscovering = false }

        do {
            let discoveredPrinters = try await service.discoverPrinters()
            lastUpdated = Date()

            if discoveredPrinters.isEmpty {
                if printers.isEmpty {
                    selection = .dashboard
                    connectionMessage = "No printers found. Add a printer by address or try discovery again."
                } else {
                    connectionMessage = "No printers found. Showing saved printers."
                }
                return
            }

            let previousCount = printers.count
            printers = mergedPrinters(with: discoveredPrinters)
            if selectedPrinter == nil {
                selection = .printer(printers[0].id)
            }
            connectionMessage = discoverySummary(
                discoveredCount: discoveredPrinters.count,
                previousCount: previousCount,
                mergedCount: printers.count
            )
            saveProfiles()
        } catch {
            if printers.isEmpty {
                selection = .dashboard
                connectionMessage = "Discovery failed. Check local network access or add a printer by address."
            } else {
                connectionMessage = "Discovery failed. Showing saved printers."
            }
        }
    }

    public func connectSelectedPrinter() async {
        if let readinessMessage = selectedPrinterConnectReadinessMessage {
            connectionMessage = readinessMessage
            return
        }

        guard let printer = selectedPrinter else {
            return
        }

        isConnecting = true
        connectionMessage = "Connecting to \(printer.name)..."
        defer { isConnecting = false }

        if await identify(printer: printer, persists: true) {
            if let info = lastPrinterInfo {
                connectionMessage = "\(info.displayName) reports \(info.typeName)."
            }
            if let identifiedPrinter = selectedPrinter,
               isStatusRefreshable(identifiedPrinter) {
                _ = await refreshStatus(
                    for: identifiedPrinter,
                    announcesProgress: true,
                    reportsBackgroundFailure: false
                )
            }
        } else {
            connectionMessage = selectedPrinterIdentificationFailureMessage(for: printer)
        }
    }

    @discardableResult
    public func connectKnownPrinters() async -> Int {
        if let readinessMessage = connectKnownPrintersReadinessMessage {
            connectionMessage = readinessMessage
            return 0
        }

        isConnectingKnownPrinters = true
        connectionMessage = "Identifying \(NativeFormatters.itemCount(printers.count, singular: "printer", plural: "printers"))..."
        defer { isConnectingKnownPrinters = false }

        var identifiedCount = 0
        for printer in printers {
            if await identify(printer: printer, persists: false) {
                identifiedCount += 1
            }
        }

        if identifiedCount > 0 {
            saveProfiles()
        }

        connectionMessage = knownPrinterIdentificationSummary(identifiedCount: identifiedCount, targetCount: printers.count)
        return identifiedCount
    }

    private func identify(printer: PrinterSnapshot, persists: Bool) async -> Bool {
        do {
            let info = try await bootstrapClient.fetchPrinterInfo(
                host: printer.address,
                port: UInt16(printer.commandPort ?? 8899)
            )
            printerInfoByPrinterID[printer.id] = info
            merge(info: info, intoPrinterID: printer.id)
            if persists {
                saveProfiles()
            }
            return true
        } catch {
            printerInfoByPrinterID.removeValue(forKey: printer.id)
            return false
        }
    }

    @discardableResult
    public func refreshSelectedPrinterStatus() async -> Bool {
        await refreshSelectedPrinterStatus(announcesProgress: true)
    }

    @discardableResult
    public func refreshSelectedPrinterStatusInBackground() async -> Bool {
        await refreshSelectedPrinterStatus(announcesProgress: false)
    }

    @discardableResult
    public func refreshKnownPrinterStatuses() async -> Int {
        await refreshKnownPrinterStatuses(announcesProgress: true)
    }

    @discardableResult
    public func refreshKnownPrinterStatusesInBackground() async -> Int {
        await refreshKnownPrinterStatuses(announcesProgress: false)
    }

    @discardableResult
    private func refreshKnownPrinterStatuses(announcesProgress: Bool) async -> Int {
        if let readinessMessage = refreshKnownPrinterStatusesReadinessMessage {
            if announcesProgress {
                connectionMessage = readinessMessage
            }
            return 0
        }

        let targets = printers.filter(isStatusRefreshable)

        isRefreshingAllStatuses = true
        if announcesProgress {
            connectionMessage = "Refreshing \(NativeFormatters.itemCount(targets.count, singular: "printer", plural: "printers"))..."
        }
        defer { isRefreshingAllStatuses = false }

        var refreshedCount = 0
        for printer in targets {
            if await refreshStatus(for: printer, announcesProgress: false, reportsBackgroundFailure: announcesProgress) {
                refreshedCount += 1
            }
        }

        if refreshedCount > 0 {
            lastUpdated = Date()
            saveProfiles()
        }

        if announcesProgress {
            connectionMessage = knownPrinterRefreshSummary(refreshedCount: refreshedCount, targetCount: targets.count)
        }
        return refreshedCount
    }

    @discardableResult
    private func refreshSelectedPrinterStatus(announcesProgress: Bool) async -> Bool {
        if let readinessMessage = selectedPrinterStatusRefreshReadinessMessage {
            if announcesProgress {
                connectionMessage = readinessMessage
            }
            return false
        }

        guard let printer = selectedPrinter else {
            return false
        }

        isRefreshingStatus = true
        if announcesProgress {
            connectionMessage = "Refreshing \(printer.name)..."
        }
        defer { isRefreshingStatus = false }

        return await refreshStatus(
            for: printer,
            announcesProgress: announcesProgress,
            reportsBackgroundFailure: true
        )
    }

    private func refreshStatus(
        for printer: PrinterSnapshot,
        announcesProgress: Bool,
        reportsBackgroundFailure: Bool
    ) async -> Bool {
        guard let serialNumber = printer.serialNumber, !serialNumber.isEmpty else {
            if announcesProgress {
                connectionMessage = "This printer did not report a serial number."
            }
            return false
        }

        guard let trimmedCheckCode = storedCheckCode(for: printer.id) else {
            if announcesProgress {
                connectionMessage = "Enter the printer check code to refresh status."
            }
            return false
        }

        do {
            let status = try await modernClient.fetchStatus(
                host: printer.address,
                port: UInt16(printer.eventPort ?? 8898),
                serialNumber: serialNumber,
                checkCode: trimmedCheckCode
            )
            modernStatusesByPrinterID[printer.id] = status
            merge(status: status, intoPrinterID: printer.id)
            let updatedAt = Date()
            statusUpdatedAtByPrinterID[printer.id] = updatedAt
            statusFailureMessagesByPrinterID.removeValue(forKey: printer.id)
            lastUpdated = updatedAt
            saveProfiles()
            if announcesProgress || reportsBackgroundFailure {
                connectionMessage = "\(status.displayName) status is \(status.state.rawValue)."
            }
            return true
        } catch {
            modernStatusesByPrinterID.removeValue(forKey: printer.id)
            statusFailureMessagesByPrinterID[printer.id] = statusRefreshFailureSummary(for: error)
            if announcesProgress || reportsBackgroundFailure {
                connectionMessage = statusRefreshFailureMessage(
                    for: printer,
                    error: error,
                    isBackground: !announcesProgress
                )
            }
            return false
        }
    }

    private func loadSavedProfiles() {
        guard let profileStore else {
            return
        }

        do {
            let document = try profileStore.loadDocument()
            checkCodesByPrinterID = Dictionary(
                uniqueKeysWithValues: document.profiles.compactMap { profile in
                    guard let code = profile.checkCode, !code.isEmpty else {
                        return nil
                    }
                    return (profile.id, code)
                }
            )
            cameraConfigsByPrinterID = Dictionary(
                uniqueKeysWithValues: document.profiles.compactMap { profile in
                    guard let config = profile.cameraUserConfig else {
                        return nil
                    }
                    return (profile.id, config)
                }
            )
            recentUploadFileURLsByPrinterID = Dictionary(
                uniqueKeysWithValues: document.profiles.compactMap { profile in
                    let recentFiles = sanitizedRecentUploadFileURLs(profile.recentUploadFileURLs)
                    guard !recentFiles.isEmpty else {
                        return nil
                    }
                    return (profile.id, recentFiles)
                }
            )
            printers = document.profiles.map { $0.snapshot() }

            if let selectedPrinterID = document.selectedPrinterID,
               printers.contains(where: { $0.id == selectedPrinterID }) {
                selection = .printer(selectedPrinterID)
            } else if let firstPrinter = printers.first {
                selection = .printer(firstPrinter.id)
            } else {
                selection = .dashboard
            }
            loadProfileSettingsForSelection()

            if !printers.isEmpty {
                connectionMessage = "Loaded saved printers."
            }
        } catch {
            connectionMessage = "Saved printer profiles could not be loaded."
        }
    }

    private func saveProfiles() {
        guard let profileStore else {
            return
        }

        let selectedPrinterID: UUID?
        if case .printer(let id) = selection {
            selectedPrinterID = id
        } else {
            selectedPrinterID = nil
        }

        let profiles = printers
            .filter { !isPreviewPrinter($0) }
            .map { printer in
                PrinterProfile(
                    snapshot: printer,
                    checkCode: checkCodesByPrinterID[printer.id],
                    cameraUserConfig: cameraConfigsByPrinterID[printer.id],
                    recentUploadFileURLs: recentUploadFileURLsByPrinterID[printer.id] ?? []
                )
            }

        try? profileStore.saveDocument(
            PrinterProfileDocument(
                profiles: profiles,
                selectedPrinterID: selectedPrinterID
            )
        )
    }

    private func rememberProfileSettings(for selection: AppSelection?) {
        guard case .printer(let id) = selection else {
            return
        }

        let trimmedCode = checkCode.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedCode.isEmpty {
            checkCodesByPrinterID.removeValue(forKey: id)
        } else {
            checkCodesByPrinterID[id] = trimmedCode
        }

        let trimmedCameraURL = customCameraURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if customCameraEnabled || !trimmedCameraURL.isEmpty {
            cameraConfigsByPrinterID[id] = CameraUserConfig(
                customCameraEnabled: customCameraEnabled,
                customCameraURL: trimmedCameraURL.isEmpty ? nil : trimmedCameraURL
            )
        } else {
            cameraConfigsByPrinterID.removeValue(forKey: id)
        }
    }

    private func loadProfileSettingsForSelection() {
        isApplyingProfileSettings = true
        defer { isApplyingProfileSettings = false }

        guard case .printer(let id) = selection else {
            checkCode = ""
            customCameraEnabled = false
            customCameraURL = ""
            return
        }

        checkCode = checkCodesByPrinterID[id] ?? ""
        let config = cameraConfigsByPrinterID[id] ?? CameraUserConfig()
        customCameraEnabled = config.customCameraEnabled
        customCameraURL = config.customCameraURL ?? ""
    }

    private func mergedPrinters(with discoveredPrinters: [PrinterSnapshot]) -> [PrinterSnapshot] {
        let storedPrinters = printers
        var mergedPrinters: [PrinterSnapshot] = []
        var matchedStoredPrinterIDs: Set<UUID> = []

        for discoveredPrinter in discoveredPrinters {
            var printer = discoveredPrinter
            if let storedPrinter = storedPrinters.first(where: { isSamePrinter($0, discoveredPrinter) }) {
                printer.id = storedPrinter.id
                matchedStoredPrinterIDs.insert(storedPrinter.id)
            }

            if !mergedPrinters.contains(where: { isSamePrinter($0, printer) }) {
                mergedPrinters.append(printer)
            }
        }

        for storedPrinter in storedPrinters where !matchedStoredPrinterIDs.contains(storedPrinter.id) {
            if !mergedPrinters.contains(where: { isSamePrinter($0, storedPrinter) }) {
                mergedPrinters.append(storedPrinter)
            }
        }

        return mergedPrinters
    }

    private func isSamePrinter(_ lhs: PrinterSnapshot, _ rhs: PrinterSnapshot) -> Bool {
        if let leftSerial = lhs.serialNumber, let rightSerial = rhs.serialNumber,
           !leftSerial.isEmpty, leftSerial == rightSerial {
            return true
        }

        return lhs.address == rhs.address && normalizedCommandPort(lhs) == normalizedCommandPort(rhs)
    }

    private func normalizedCommandPort(_ printer: PrinterSnapshot) -> Int {
        printer.commandPort ?? 8899
    }

    private func isPreviewPrinter(_ printer: PrinterSnapshot) -> Bool {
        printer.address.hasPrefix("preview.")
    }

    private func isStatusRefreshable(_ printer: PrinterSnapshot) -> Bool {
        guard let serialNumber = printer.serialNumber, !serialNumber.isEmpty else {
            return false
        }

        return storedCheckCode(for: printer.id) != nil
    }

    private func overviewPriority(for printer: PrinterSnapshot) -> Int {
        switch printer.status {
        case .needsAttention:
            return 0
        case .paused:
            return 1
        case .printing, .busy:
            return 2
        case .ready:
            return 3
        case .offline:
            return 4
        }
    }

    private func storedCheckCode(for printerID: UUID) -> String? {
        let trimmedCode = checkCodesByPrinterID[printerID]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedCode.isEmpty ? nil : trimmedCode
    }

    private func isSupportedUploadFile(_ fileURL: URL) -> Bool {
        Self.supportedUploadFileExtensions.contains(fileURL.pathExtension.lowercased())
    }

    private func doesUploadFileExist(_ fileURL: URL) -> Bool {
        let didStartAccessing = fileURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }

        return FileManager.default.fileExists(atPath: fileURL.path)
    }

    private func normalizedManualPrinterAddress(_ address: String) -> String? {
        let trimmedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAddress.isEmpty else {
            return nil
        }

        if trimmedAddress.contains("://") {
            guard let url = URL(string: trimmedAddress), let host = url.host(), isValidManualPrinterHost(host) else {
                return nil
            }
            return host
        }

        let withoutPath = trimmedAddress.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true)
            .first
            .map(String.init) ?? trimmedAddress
        let withoutPort = withoutPath.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: true)
            .first
            .map(String.init) ?? withoutPath
        let normalizedAddress = withoutPort.trimmingCharacters(in: .whitespacesAndNewlines)
        return isValidManualPrinterHost(normalizedAddress) ? normalizedAddress : nil
    }

    private func isValidManualPrinterHost(_ host: String) -> Bool {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty,
              trimmedHost.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              !trimmedHost.hasPrefix("."),
              !trimmedHost.hasSuffix("."),
              !trimmedHost.hasPrefix("-"),
              !trimmedHost.hasSuffix("-") else {
            return false
        }

        return true
    }

    private func rememberRecentUploadFile(_ fileURL: URL) {
        guard isSupportedUploadFile(fileURL), let selectedPrinter else {
            return
        }

        var recentFiles = recentUploadFileURLsByPrinterID[selectedPrinter.id] ?? []
        recentFiles.removeAll { $0 == fileURL }
        recentFiles.insert(fileURL, at: 0)
        recentUploadFileURLsByPrinterID[selectedPrinter.id] = Array(recentFiles.prefix(5))
        saveProfiles()
    }

    private func removeRecentUploadFile(_ fileURL: URL, for printerID: UUID) {
        guard var recentFiles = recentUploadFileURLsByPrinterID[printerID] else {
            return
        }

        recentFiles.removeAll { $0 == fileURL }
        if recentFiles.isEmpty {
            recentUploadFileURLsByPrinterID.removeValue(forKey: printerID)
        } else {
            recentUploadFileURLsByPrinterID[printerID] = recentFiles
        }
        saveProfiles()
    }

    private func setSelectedUploadFile(_ fileURL: URL) {
        selectedUploadFileURL = fileURL
        rememberRecentUploadFile(fileURL)
        connectionMessage = "\(fileURL.lastPathComponent) selected."
    }

    private func applyPendingOpenedJobFileIfNeeded() {
        guard selectedPrinter != nil, let fileURL = pendingOpenedJobFileURL else {
            return
        }

        pendingOpenedJobFileURL = nil
        setSelectedUploadFile(fileURL)
    }

    private func sanitizedRecentUploadFileURLs(_ fileURLs: [URL]) -> [URL] {
        var seenFileURLs: Set<URL> = []
        var sanitizedFileURLs: [URL] = []

        for fileURL in fileURLs where isSupportedUploadFile(fileURL) && !seenFileURLs.contains(fileURL) {
            sanitizedFileURLs.append(fileURL)
            seenFileURLs.insert(fileURL)

            if sanitizedFileURLs.count == 5 {
                break
            }
        }

        return sanitizedFileURLs
    }

    private func uploadFailureMessage(for error: Error) -> String {
        guard let uploadError = error as? ModernPrinterUploadError else {
            return "Upload failed. Check the file, code, and network."
        }

        switch uploadError {
        case .fileNotFound:
            return "Upload failed because the job file could not be found. Choose the file again."
        case .invalidFileName:
            return "Upload failed because the job file name is invalid. Choose a named .gcode, .gx, or .3mf file."
        case .transportFailed:
            return "Upload failed. Check that the printer is online and reachable on the network."
        case .httpStatus(let statusCode, let message):
            let trimmedMessage = message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if trimmedMessage.isEmpty {
                return "Upload failed with HTTP \(statusCode). Check printer status, check code, and network."
            }

            return "Upload failed with HTTP \(statusCode): \(trimmedMessage)."
        case .invalidResponse:
            return "Upload failed because the printer returned an unexpected response."
        case .rejected(let message):
            let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedMessage.isEmpty {
                return "Printer rejected the upload. Check the code and printer status."
            }

            return "Printer rejected the upload: \(trimmedMessage)."
        }
    }

    private func knownPrinterRefreshSummary(refreshedCount: Int, targetCount: Int) -> String {
        if refreshedCount == targetCount {
            return "Refreshed \(NativeFormatters.itemCount(refreshedCount, singular: "printer", plural: "printers"))."
        }

        if refreshedCount == 0 {
            return "Could not refresh any printers. Check saved check codes and network."
        }

        return "Refreshed \(refreshedCount) of \(targetCount) printers. Check the remaining printers' codes and network."
    }

    private func knownPrinterIdentificationSummary(identifiedCount: Int, targetCount: Int) -> String {
        if identifiedCount == targetCount {
            return "Identified \(NativeFormatters.itemCount(identifiedCount, singular: "printer", plural: "printers"))."
        }

        if identifiedCount == 0 {
            return "Could not identify any printers. Check that they are powered on and reachable on the local network."
        }

        return "Identified \(identifiedCount) of \(targetCount) printers. Check the remaining printers' addresses and local network."
    }

    private func discoverySummary(discoveredCount: Int, previousCount: Int, mergedCount: Int) -> String {
        let discoveredSummary = "Found \(NativeFormatters.itemCount(discoveredCount, singular: "printer", plural: "printers"))."
        let savedCount = max(mergedCount - discoveredCount, 0)
        guard previousCount > 0, savedCount > 0 else {
            return discoveredSummary
        }

        let savedSummary = NativeFormatters.itemCount(
            savedCount,
            singular: "saved printer",
            plural: "saved printers"
        )
        let suffix = savedCount == 1 ? "was" : "were"
        return "\(discoveredSummary) Kept \(savedSummary) that \(suffix) not discovered."
    }

    private func selectedPrinterIdentificationFailureMessage(for printer: PrinterSnapshot) -> String {
        let port = printer.commandPort.map { ":\($0)" } ?? ""
        return "Could not identify \(printer.name) at \(printer.address)\(port). Check that the printer is powered on and reachable on the local network."
    }

    private func statusRefreshFailureSummary(for error: Error) -> String {
        guard let httpError = error as? ModernPrinterHTTPError else {
            return "Last refresh failed. Check the check code and network."
        }

        switch httpError {
        case .transportFailed:
            return "Last refresh failed. Check that the printer is online and reachable on the network."
        case .invalidURL, .invalidResponse:
            return "Last refresh failed. The printer returned an unexpected status response."
        case .httpStatus(let statusCode, let message):
            let trimmedMessage = message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if trimmedMessage.isEmpty {
                return "Last refresh failed with HTTP \(statusCode). Check the check code and network."
            }

            return "Last refresh failed with HTTP \(statusCode): \(trimmedMessage)."
        case .printerRejectedRequest(let message):
            let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedMessage.isEmpty {
                return "Last refresh rejected. Check the check code and printer status."
            }

            return "Last refresh rejected: \(trimmedMessage)."
        case .missingDetail:
            return "Last refresh failed. The printer did not include status details."
        }
    }

    private func statusRefreshFailureMessage(for printer: PrinterSnapshot, error: Error, isBackground: Bool) -> String {
        let target = "\(printer.name) at \(printer.address)"
        let action = isBackground ? "Auto-refresh failed for" : "Could not refresh"
        guard let httpError = error as? ModernPrinterHTTPError else {
            if isBackground {
                return "Auto-refresh failed for \(target). Check the check code and network."
            }

            return "Could not refresh \(target). Check the check code and network."
        }

        switch httpError {
        case .transportFailed:
            return "\(action) \(target). Check that the printer is online and reachable on the network."
        case .invalidURL, .invalidResponse:
            return "\(action) \(target). The printer returned an unexpected status response."
        case .httpStatus(let statusCode, let message):
            let trimmedMessage = message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if trimmedMessage.isEmpty {
                return "\(action) \(target). Printer returned HTTP \(statusCode). Check the check code and network."
            }

            return "\(action) \(target). Printer returned HTTP \(statusCode): \(trimmedMessage)."
        case .printerRejectedRequest(let message):
            let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedMessage.isEmpty {
                return "\(action) \(target). Printer rejected the refresh. Check the check code and printer status."
            }

            return "\(action) \(target). Printer rejected the refresh: \(trimmedMessage)."
        case .missingDetail:
            return "\(action) \(target). The printer did not include status details."
        }
    }

    private func supportsLocalCameraFallback(printer: PrinterSnapshot, status: ModernPrinterStatus?) -> Bool {
        status?.isPro == true || status?.isAD5X == true || modelSupportsLocalCameraFallback(printer.model)
    }

    private func modelSupportsLocalCameraFallback(_ model: String) -> Bool {
        let normalizedModel = model
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }

        return normalizedModel.contains("ad5x") || normalizedModel.contains("5mpro")
    }

    private func jobCommandFailureMessage(for command: PrinterJobCommand, error: Error) -> String {
        guard let commandError = error as? ModernPrinterCommandError else {
            return "Could not send \(command.rawValue). Check the code and network."
        }

        switch commandError {
        case .transportFailed:
            return "Could not send \(command.rawValue). Check that the printer is online and reachable on the network."
        case .httpStatus(let statusCode, let message):
            let trimmedMessage = message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if trimmedMessage.isEmpty {
                return "Could not send \(command.rawValue). Printer returned HTTP \(statusCode). Check printer status, check code, and network."
            }

            return "Could not send \(command.rawValue). Printer returned HTTP \(statusCode): \(trimmedMessage)."
        case .invalidResponse:
            return "Could not send \(command.rawValue). The printer returned an unexpected response."
        case .rejected(let message):
            let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedMessage.isEmpty {
                return "Printer rejected \(command.rawValue). Check the current job state."
            }

            return "Printer rejected \(command.rawValue): \(trimmedMessage)."
        }
    }

    private func merge(info: PrinterInfo, intoPrinterID printerID: UUID) {
        guard let index = printers.firstIndex(where: { $0.id == printerID }) else {
            return
        }

        if !info.name.isEmpty {
            printers[index].name = info.displayName
        }
        if !info.typeName.isEmpty {
            printers[index].model = info.typeName
        }
        if !info.serialNumber.isEmpty {
            printers[index].serialNumber = info.serialNumber
        }
    }

    private func merge(status: ModernPrinterStatus, intoPrinterID printerID: UUID) {
        guard let index = printers.firstIndex(where: { $0.id == printerID }) else {
            return
        }

        printers[index].name = status.displayName
        printers[index].model = status.modelName
        printers[index].status = status.state.printerStatus
        printers[index].nozzleTemperature = TemperatureReading(
            current: status.nozzleCurrent,
            target: status.nozzleTarget
        )
        printers[index].bedTemperature = TemperatureReading(
            current: status.bedCurrent,
            target: status.bedTarget
        )
        printers[index].activeJob = status.jobSnapshot
        printers[index].material = status.materialSnapshot
        printers[index].materialStation = status.materialStation
        printers[index].cameraState = status.cameraStreamURL.isEmpty && !status.isPro && !status.isAD5X ? .unavailable : .available
    }

    private func applyOptimisticState(for command: PrinterJobCommand, printerID: UUID) {
        guard let index = printers.firstIndex(where: { $0.id == printerID }) else {
            return
        }

        switch command {
        case .pause:
            printers[index].status = .paused
        case .resume:
            printers[index].status = .printing
        case .cancel:
            printers[index].status = .ready
            printers[index].activeJob = nil
        }
    }

    private func applyUploadSuccess(fileURL: URL, printerID: UUID) {
        guard startPrintAfterUpload,
              let index = printers.firstIndex(where: { $0.id == printerID }) else {
            return
        }

        printers[index].status = .printing
        printers[index].activeJob = PrintJobSnapshot(
            fileName: fileURL.lastPathComponent,
            progress: 0
        )
    }
}
