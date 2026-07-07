import Foundation
import Observation

@MainActor
@Observable
public final class AppModel {
    nonisolated public static let supportedUploadFileExtensions = ["gcode", "gx", "3mf"]

    public var printers: [PrinterSnapshot]
    public var selection: AppSelection? {
        willSet {
            rememberProfileSettings(for: selection)
        }
        didSet {
            loadProfileSettingsForSelection()
            saveProfiles()
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
    private var uploadFileURLsByPrinterID: [UUID: URL]
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
        self.uploadFileURLsByPrinterID = [:]
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

    public var identifiedPrinterCount: Int {
        printers.filter { !($0.serialNumber ?? "").isEmpty }.count
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

    public func canSendSelectedPrinterJobCommand(_ command: PrinterJobCommand) -> Bool {
        selectedPrinterJobCommandReadinessMessage(for: command) == nil
    }

    public func selectedPrinterJobCommandReadinessMessage(for command: PrinterJobCommand) -> String? {
        if isSendingJobCommand {
            return activeJobCommand == command ? "Sending \(command.rawValue)." : "Sending another job command."
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

        return nil
    }

    public var refreshablePrinterCount: Int {
        printers.filter(canRefreshStatus).count
    }

    public var canConnectSelectedPrinter: Bool {
        selectedPrinterConnectReadinessMessage == nil
    }

    public var selectedPrinterConnectReadinessMessage: String? {
        if isConnecting {
            return "Connecting to this printer."
        }

        if isConnectingKnownPrinters {
            return "Identifying printers."
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
        if isRefreshingStatus {
            return "Refreshing this printer."
        }

        if isRefreshingAllStatuses {
            return "Refreshing printer statuses."
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
        if isConnectingKnownPrinters {
            return "Identifying printers."
        }

        if isConnecting {
            return "Connecting to the selected printer."
        }

        guard !printers.isEmpty else {
            return "Add or discover printers first."
        }

        return nil
    }

    public var refreshKnownPrinterStatusesReadinessMessage: String? {
        if isRefreshingAllStatuses {
            return "Refreshing printer statuses."
        }

        if isRefreshingStatus {
            return "Refreshing the selected printer."
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

    public var selectedCameraStreamConfig: CameraStreamConfig {
        guard let printer = selectedPrinter else {
            return CameraStreamConfig(
                sourceType: .none,
                isAvailable: false,
                unavailableReason: "Select a printer first."
            )
        }

        let status = lastModernStatus
        let fallbackURL = status?.isPro == true || status?.isAD5X == true
            ? CameraStreamResolver.flashForgeMJPEGURL(ipAddress: printer.address)
            : ""

        return CameraStreamResolver.resolve(
            userConfig: selectedCameraUserConfig,
            cameraFeatures: CameraFeatureConfig(
                oemStreamURL: status?.cameraStreamURL ?? "",
                fallbackStreamURL: fallbackURL
            )
        )
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

    public var canRemoveSelectedPrinter: Bool {
        guard let selectedPrinter else {
            return false
        }

        return !isPreviewPrinter(selectedPrinter)
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
        guard selectedPrinter != nil else {
            connectionMessage = "Select a printer first."
            return
        }

        selectedUploadFileURL = fileURL
        connectionMessage = "\(fileURL.lastPathComponent) selected."
    }

    public func acknowledgeCameraOpen() {
        let config = selectedCameraStreamConfig
        if config.isAvailable, let streamURL = config.streamURL {
            connectionMessage = "Camera stream ready: \(streamURL.absoluteString)"
        } else {
            connectionMessage = config.unavailableReason ?? "Camera is not available."
        }
    }

    @discardableResult
    public func addManualPrinter(name: String, address: String, checkCode: String = "") -> Bool {
        let trimmedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAddress.isEmpty else {
            connectionMessage = "Enter the printer address."
            return false
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCheckCode = checkCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = trimmedName.isEmpty ? trimmedAddress : trimmedName

        if let index = printers.firstIndex(where: {
            $0.address == trimmedAddress && ($0.commandPort ?? 8899) == 8899
        }) {
            printers[index].name = displayName
            printers[index].model = "Manual Printer"
            printers[index].address = trimmedAddress
            printers[index].commandPort = 8899
            printers[index].eventPort = 8898
            printers[index].protocolFormat = .modern

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
            address: trimmedAddress,
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
        connectionMessage = "Added \(displayName)."
        return true
    }

    public func removeSelectedPrinter() {
        guard let printer = selectedPrinter, canRemoveSelectedPrinter else {
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
        uploadFileURLsByPrinterID.removeValue(forKey: removedPrinterID)
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
                    levelingBeforePrint: levelingBeforePrint,
                    firmwareVersion: lastModernStatus?.firmwareVersion ?? lastPrinterInfo?.firmwareVersion
                ),
                host: printer.address,
                port: UInt16(printer.eventPort ?? 8898),
                serialNumber: serialNumber,
                checkCode: trimmedCheckCode
            )
            applyUploadSuccess(fileURL: fileURL, printerID: printer.id)
            lastUpdated = Date()
            connectionMessage = startPrintAfterUpload ? "Uploaded and started \(fileURL.lastPathComponent)." : "Uploaded \(fileURL.lastPathComponent)."
        } catch {
            connectionMessage = "Upload failed. Check the file, code, and network."
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
            lastUpdated = Date()
            connectionMessage = command.successMessage
        } catch {
            connectionMessage = "Printer rejected the \(command.rawValue) command."
        }
    }

    public func discoverPrinters() async {
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

            printers = discoveredPrinters.map(preservingStoredIdentity(for:))
            if selectedPrinter == nil {
                selection = .printer(printers[0].id)
            }
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
        } else {
            let port = printer.commandPort.map { ":\($0)" } ?? ""
            connectionMessage = "Could not read printer info at \(printer.address)\(port)."
        }
    }

    @discardableResult
    public func connectKnownPrinters() async -> Int {
        guard canConnectKnownPrinters else {
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

        connectionMessage = "Identified \(NativeFormatters.itemCount(identifiedCount, singular: "printer", plural: "printers"))."
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
        guard !isRefreshingAllStatuses, !isRefreshingStatus else {
            return 0
        }

        let targets = printers.filter(canRefreshStatus)
        guard !targets.isEmpty else {
            if announcesProgress {
                connectionMessage = "Connect printers and save check codes before refreshing all."
            }
            return 0
        }

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
            connectionMessage = "Refreshed \(NativeFormatters.itemCount(refreshedCount, singular: "printer", plural: "printers"))."
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
            lastUpdated = Date()
            saveProfiles()
            if announcesProgress || reportsBackgroundFailure {
                connectionMessage = "\(status.displayName) status is \(status.state.rawValue)."
            }
            return true
        } catch {
            modernStatusesByPrinterID.removeValue(forKey: printer.id)
            connectionMessage = announcesProgress
                ? "Could not refresh status. Check the code and network."
                : reportsBackgroundFailure ? "Auto-refresh failed. Check the code and network." : connectionMessage
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
                    cameraUserConfig: cameraConfigsByPrinterID[printer.id]
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

    private func preservingStoredIdentity(for discoveredPrinter: PrinterSnapshot) -> PrinterSnapshot {
        guard let storedPrinter = printers.first(where: { isSamePrinter($0, discoveredPrinter) }) else {
            return discoveredPrinter
        }

        var printer = discoveredPrinter
        printer.id = storedPrinter.id
        return printer
    }

    private func isSamePrinter(_ lhs: PrinterSnapshot, _ rhs: PrinterSnapshot) -> Bool {
        if let leftSerial = lhs.serialNumber, let rightSerial = rhs.serialNumber,
           !leftSerial.isEmpty, leftSerial == rightSerial {
            return true
        }

        return lhs.address == rhs.address && lhs.commandPort == rhs.commandPort
    }

    private func isPreviewPrinter(_ printer: PrinterSnapshot) -> Bool {
        printer.address.hasPrefix("preview.")
    }

    private func canRefreshStatus(_ printer: PrinterSnapshot) -> Bool {
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
