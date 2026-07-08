import FlashForgeNativeKit
import Foundation
import Testing

@Test func supportedUploadExtensionsMatchNativeJobFiles() {
    #expect(AppModel.supportedUploadFileExtensions == ["gcode", "gx", "3mf"])
}

@MainActor
@Test func discoverySelectsFirstPrinter() async {
    let model = AppModel(service: PreviewPrinterService(), bootstrapClient: FakeBootstrapClient())

    await model.discoverPrinters()

    #expect(model.printers.count == 2)
    #expect(model.selectedPrinter?.name == "Creator 5 Studio")
    #expect(model.activePrintCount == 1)
}

@MainActor
@Test func emptyDiscoveryShowsTruthfulEmptyState() async {
    let model = AppModel(service: EmptyPrinterService(), bootstrapClient: FakeBootstrapClient())

    await model.discoverPrinters()

    #expect(model.printers.isEmpty)
    #expect(model.selection == .dashboard)
    #expect(model.connectionMessage == "No printers found. Add a printer by address or try discovery again.")
    #expect(model.isDiscovering == false)
}

@MainActor
@Test func failedDiscoveryDoesNotShowSamplePrinters() async {
    let model = AppModel(service: FailingPrinterService(), bootstrapClient: FakeBootstrapClient())

    await model.discoverPrinters()

    #expect(model.printers.isEmpty)
    #expect(model.selection == .dashboard)
    #expect(model.connectionMessage == "Discovery failed. Check local network access or add a printer by address.")
    #expect(model.isDiscovering == false)
}

@MainActor
@Test func discoveryRequestWhileAlreadyDiscoveringDoesNotStartAnotherScan() async {
    let service = RecordingPrinterService()
    let model = AppModel(service: service, bootstrapClient: FakeBootstrapClient())
    model.isDiscovering = true

    await model.discoverPrinters()

    #expect(service.requestCount == 0)
    #expect(model.connectionMessage == "Discovery in progress.")
    #expect(model.isDiscovering == true)
}

@MainActor
@Test func discoveryInProgressPausesOtherPrinterNetworkActions() async {
    let printer = PrinterSnapshot(
        name: "Desk Printer",
        model: "AD5X",
        address: "192.168.1.44",
        serialNumber: "SN-TEST",
        eventPort: 8898,
        status: .ready,
        nozzleTemperature: TemperatureReading(current: 30),
        bedTemperature: TemperatureReading(current: 28)
    )
    let model = AppModel(service: EmptyPrinterService(), bootstrapClient: FakeBootstrapClient(), printers: [printer])
    model.selection = .printer(printer.id)
    model.checkCode = "123456"
    model.isDiscovering = true

    #expect(model.selectedPrinterConnectReadinessMessage == "Discovery in progress.")
    #expect(model.canConnectSelectedPrinter == false)
    #expect(model.connectKnownPrintersReadinessMessage == "Discovery in progress.")
    #expect(model.canConnectKnownPrinters == false)
    #expect(model.selectedPrinterStatusRefreshReadinessMessage == "Discovery in progress.")
    #expect(model.canRefreshSelectedPrinterStatus == false)
    #expect(model.refreshKnownPrinterStatusesReadinessMessage == "Discovery in progress.")
    #expect(model.canRefreshKnownPrinterStatuses == false)
}

@MainActor
@Test func savedProfilesLoadSelectedPrinterAndCheckCode() async {
    let printerID = UUID()
    let store = RecordingProfileStore(
        document: PrinterProfileDocument(
            profiles: [
                PrinterProfile(
                    id: printerID,
                    name: "Saved Printer",
                    model: "Adventurer 5M Pro",
                    address: "192.168.1.55",
                    serialNumber: "SN-SAVED",
                    commandPort: 8899,
                    eventPort: 8898,
                    protocolFormat: .modern,
                    checkCode: "654321",
                    cameraUserConfig: CameraUserConfig(
                        customCameraEnabled: true,
                        customCameraURL: "http://camera.local:8080/?action=stream"
                    )
                )
            ],
            selectedPrinterID: printerID
        )
    )

    let model = AppModel(
        service: EmptyPrinterService(),
        bootstrapClient: FakeBootstrapClient(),
        profileStore: store
    )

    #expect(model.printers.count == 1)
    #expect(model.selection == AppSelection.printer(printerID))
    #expect(model.selectedPrinter?.status == .offline)
    #expect(model.checkCode == "654321")
    #expect(model.hasSelectedPrinterCheckCode == true)
    #expect(model.canClearSelectedPrinterCheckCode == true)
    #expect(model.selectedPrinterCheckCodeStatusMessage == "Check code saved for this printer.")
    #expect(model.customCameraEnabled == true)
    #expect(model.customCameraURL == "http://camera.local:8080/?action=stream")
    #expect(model.selectedCameraStreamConfig.sourceType == .custom)

    model.clearSelectedPrinterCheckCode()

    #expect(model.checkCode == "")
    #expect(model.hasSelectedPrinterCheckCode == false)
    #expect(model.canClearSelectedPrinterCheckCode == false)
    #expect(model.selectedPrinterCheckCodeStatusMessage == "Needed for refresh, upload, and job controls.")
    #expect(store.document.profiles.first?.checkCode == nil)
    #expect(model.connectionMessage == "Check code cleared for this printer.")
}

@MainActor
@Test func overviewPrintersPrioritizeAttentionAndActiveJobs() async {
    let readyPrinter = PrinterSnapshot(
        name: "Ready A",
        model: "AD5X",
        address: "192.168.1.44",
        status: .ready,
        nozzleTemperature: TemperatureReading(current: 30),
        bedTemperature: TemperatureReading(current: 28)
    )
    let offlinePrinter = PrinterSnapshot(
        name: "Offline B",
        model: "Adventurer 5M",
        address: "192.168.1.45",
        status: .offline,
        nozzleTemperature: TemperatureReading(current: 0),
        bedTemperature: TemperatureReading(current: 0)
    )
    let printingPrinter = PrinterSnapshot(
        name: "Printing C",
        model: "Adventurer 5M Pro",
        address: "192.168.1.46",
        status: .printing,
        nozzleTemperature: TemperatureReading(current: 220),
        bedTemperature: TemperatureReading(current: 60),
        activeJob: PrintJobSnapshot(fileName: "benchy.3mf", progress: 0.4)
    )
    let attentionPrinter = PrinterSnapshot(
        name: "Attention D",
        model: "AD5X",
        address: "192.168.1.47",
        status: .needsAttention,
        nozzleTemperature: TemperatureReading(current: 200),
        bedTemperature: TemperatureReading(current: 55)
    )
    let model = AppModel(
        service: EmptyPrinterService(),
        bootstrapClient: FakeBootstrapClient(),
        printers: [readyPrinter, offlinePrinter, printingPrinter, attentionPrinter]
    )

    #expect(model.overviewPrinters.map(\.name) == [
        "Attention D",
        "Printing C",
        "Ready A",
        "Offline B"
    ])
}

@MainActor
@Test func printerSearchMatchesVisiblePrinterFields() async {
    let studioPrinter = PrinterSnapshot(
        name: "Studio Printer",
        model: "Adventurer 5M Pro",
        address: "192.168.1.44",
        serialNumber: "SN-STUDIO",
        status: .printing,
        nozzleTemperature: TemperatureReading(current: 220),
        bedTemperature: TemperatureReading(current: 60)
    )
    let workshopPrinter = PrinterSnapshot(
        name: "Workshop",
        model: "AD5X",
        address: "printer.local",
        serialNumber: "SN-WORKSHOP",
        status: .needsAttention,
        nozzleTemperature: TemperatureReading(current: 200),
        bedTemperature: TemperatureReading(current: 55)
    )
    let model = AppModel(
        service: EmptyPrinterService(),
        bootstrapClient: FakeBootstrapClient(),
        printers: [studioPrinter, workshopPrinter]
    )

    #expect(model.printers(matching: "").map(\.name) == ["Studio Printer", "Workshop"])
    #expect(model.printers(matching: "  5m pro ").map(\.name) == ["Studio Printer"])
    #expect(model.printers(matching: "printer.local").map(\.name) == ["Workshop"])
    #expect(model.printers(matching: "sn-studio").map(\.name) == ["Studio Printer"])
    #expect(model.printers(matching: "attention").map(\.name) == ["Workshop"])
    #expect(model.printers(matching: "not-here").isEmpty)
}

@MainActor
@Test func knownPrinterActionReadinessExplainsEmptyState() async {
    let model = AppModel(service: EmptyPrinterService(), bootstrapClient: FakeBootstrapClient())

    #expect(model.connectKnownPrintersReadinessMessage == "Add or discover printers first.")
    #expect(model.canConnectKnownPrinters == false)
    #expect(model.refreshKnownPrinterStatusesReadinessMessage == "Add or discover printers first.")
    #expect(model.canRefreshKnownPrinterStatuses == false)
}

@MainActor
@Test func knownPrinterActionReadinessExplainsRefreshPrerequisites() async {
    let model = AppModel(
        service: EmptyPrinterService(),
        bootstrapClient: FakeBootstrapClient(),
        printers: [
            PrinterSnapshot(
                name: "Desk Printer",
                model: "Adventurer 5M Pro",
                address: "192.168.1.44",
                status: .offline,
                nozzleTemperature: TemperatureReading(current: 0),
                bedTemperature: TemperatureReading(current: 0)
            )
        ]
    )

    #expect(model.connectKnownPrintersReadinessMessage == nil)
    #expect(model.canConnectKnownPrinters == true)
    #expect(model.refreshKnownPrinterStatusesReadinessMessage == "Identify printers and save check codes before refreshing statuses.")
    #expect(model.canRefreshKnownPrinterStatuses == false)
}

@MainActor
@Test func knownPrinterActionReadinessClearsForSavedIdentifiedProfile() async {
    let printerID = UUID()
    let store = RecordingProfileStore(
        document: PrinterProfileDocument(
            profiles: [
                PrinterProfile(
                    id: printerID,
                    name: "Saved Printer",
                    model: "Adventurer 5M Pro",
                    address: "192.168.1.55",
                    serialNumber: "SN-SAVED",
                    commandPort: 8899,
                    eventPort: 8898,
                    protocolFormat: .modern,
                    checkCode: "654321"
                )
            ],
            selectedPrinterID: printerID
        )
    )
    let model = AppModel(
        service: EmptyPrinterService(),
        bootstrapClient: FakeBootstrapClient(),
        profileStore: store
    )

    #expect(model.connectKnownPrintersReadinessMessage == nil)
    #expect(model.canConnectKnownPrinters == true)
    #expect(model.refreshKnownPrinterStatusesReadinessMessage == nil)
    #expect(model.canRefreshKnownPrinterStatuses == true)
}

@MainActor
@Test func discoveryPreservesSavedProfileIdentityAndCheckCode() async {
    let printerID = UUID()
    let store = RecordingProfileStore(
        document: PrinterProfileDocument(
            profiles: [
                PrinterProfile(
                    id: printerID,
                    name: "Saved Printer",
                    model: "Unknown",
                    address: "192.168.1.55",
                    serialNumber: "SN-SAVED",
                    commandPort: 8899,
                    eventPort: 8898,
                    protocolFormat: .modern,
                    checkCode: "654321"
                )
            ],
            selectedPrinterID: printerID
        )
    )
    let discoveredPrinter = PrinterSnapshot(
        name: "Fresh Printer",
        model: "Adventurer 5M Pro",
        address: "192.168.1.55",
        serialNumber: "SN-SAVED",
        commandPort: 8899,
        eventPort: 8898,
        protocolFormat: .modern,
        status: .ready,
        nozzleTemperature: TemperatureReading(current: 0),
        bedTemperature: TemperatureReading(current: 0)
    )
    let model = AppModel(
        service: SinglePrinterService(printer: discoveredPrinter),
        bootstrapClient: FakeBootstrapClient(),
        profileStore: store
    )

    await model.discoverPrinters()

    #expect(model.selectedPrinter?.id == printerID)
    #expect(model.selectedPrinter?.name == "Fresh Printer")
    #expect(model.checkCode == "654321")
    #expect(store.document.profiles.first?.id == printerID)
    #expect(store.document.profiles.first?.name == "Fresh Printer")
    #expect(store.document.profiles.first?.checkCode == "654321")
}

@MainActor
@Test func discoveryKeepsSavedPrintersThatAreNotRediscovered() async {
    let studioID = UUID()
    let workshopID = UUID()
    let store = RecordingProfileStore(
        document: PrinterProfileDocument(
            profiles: [
                PrinterProfile(
                    id: studioID,
                    name: "Saved Studio",
                    model: "Unknown",
                    address: "192.168.1.55",
                    serialNumber: "SN-STUDIO",
                    commandPort: 8899,
                    eventPort: 8898,
                    protocolFormat: .modern,
                    checkCode: "111111"
                ),
                PrinterProfile(
                    id: workshopID,
                    name: "Offline Workshop",
                    model: "Adventurer 5M Pro",
                    address: "192.168.1.56",
                    serialNumber: "SN-WORKSHOP",
                    commandPort: 8899,
                    eventPort: 8898,
                    protocolFormat: .modern,
                    checkCode: "222222"
                )
            ],
            selectedPrinterID: workshopID
        )
    )
    let discoveredPrinter = PrinterSnapshot(
        name: "Fresh Studio",
        model: "Adventurer 5M Pro",
        address: "192.168.1.55",
        serialNumber: "SN-STUDIO",
        commandPort: 8899,
        eventPort: 8898,
        protocolFormat: .modern,
        status: .ready,
        nozzleTemperature: TemperatureReading(current: 0),
        bedTemperature: TemperatureReading(current: 0)
    )
    let model = AppModel(
        service: SinglePrinterService(printer: discoveredPrinter),
        bootstrapClient: FakeBootstrapClient(),
        profileStore: store
    )

    await model.discoverPrinters()

    #expect(model.printers.count == 2)
    #expect(model.printers.first { $0.id == studioID }?.name == "Fresh Studio")
    #expect(model.printers.first { $0.id == workshopID }?.name == "Offline Workshop")
    #expect(model.selectedPrinter?.id == workshopID)
    #expect(model.checkCode == "222222")
    #expect(model.connectionMessage == "Found 1 printer. Kept 1 saved printer that was not discovered.")
    #expect(store.document.profiles.count == 2)
    #expect(store.document.profiles.first { $0.id == studioID }?.name == "Fresh Studio")
    #expect(store.document.profiles.first { $0.id == workshopID }?.checkCode == "222222")
    #expect(store.document.selectedPrinterID == workshopID)
}

@MainActor
@Test func customCameraSettingsPersistWithSelectedPrinterProfile() async {
    let printer = PrinterSnapshot(
        name: "Desk Printer",
        model: "AD5X",
        address: "192.168.1.44",
        serialNumber: "SN-TEST",
        commandPort: 8899,
        eventPort: 8898,
        protocolFormat: .modern,
        status: .ready,
        nozzleTemperature: TemperatureReading(current: 0),
        bedTemperature: TemperatureReading(current: 0)
    )
    let store = RecordingProfileStore()
    let model = AppModel(
        service: PreviewPrinterService(),
        bootstrapClient: FakeBootstrapClient(),
        profileStore: store,
        printers: [printer]
    )
    model.selection = .printer(printer.id)
    model.customCameraEnabled = true
    model.customCameraURL = "rtsp://camera.local/live"

    #expect(store.document.profiles.first?.cameraUserConfig?.customCameraEnabled == true)
    #expect(store.document.profiles.first?.cameraUserConfig?.customCameraURL == "rtsp://camera.local/live")
    #expect(model.selectedCameraStreamConfig.sourceType == .custom)
    #expect(model.selectedCameraStreamConfig.streamType == .rtsp)
    #expect(model.resolvedCameraState(for: printer) == .available)
    #expect(model.canResetSelectedCameraSettings == true)

    model.resetSelectedCameraSettings()

    #expect(model.customCameraEnabled == false)
    #expect(model.customCameraURL == "")
    #expect(model.selectedCameraStreamConfig.sourceType == .intelligentFallback)
    #expect(model.resolvedCameraState(for: printer) == .available)
    #expect(model.canResetSelectedCameraSettings == false)
    #expect(store.document.profiles.first?.cameraUserConfig == nil)
    #expect(model.connectionMessage == "Camera settings reset for this printer.")
}

@MainActor
@Test func manualPrinterProfileIsAddedSelectedAndSaved() async {
    let store = RecordingProfileStore()
    let model = AppModel(
        service: EmptyPrinterService(),
        bootstrapClient: FakeBootstrapClient(),
        profileStore: store
    )

    model.addManualPrinter(
        name: "Workshop",
        address: " 192.168.1.77 ",
        checkCode: " 123456 "
    )

    #expect(model.printers.count == 1)
    #expect(model.selectedPrinter?.name == "Workshop")
    #expect(model.selectedPrinter?.address == "192.168.1.77")
    #expect(model.selectedPrinter?.model == "Manual Printer")
    #expect(model.selectedPrinter?.commandPort == 8899)
    #expect(model.selectedPrinter?.eventPort == 8898)
    #expect(model.selectedPrinter?.protocolFormat == .modern)
    #expect(model.selectedPrinter?.status == .offline)
    #expect(model.connectionMessage == "Added Workshop. Connect to identify it.")
    #expect(AppModel.manualPrinterCheckCodeHelpMessage == "Needed later for refresh, upload, and job controls. You can add it now or save it later.")
    #expect(model.checkCode == "123456")
    #expect(store.document.profiles.count == 1)
    #expect(store.document.profiles.first?.checkCode == "123456")
    #expect(store.document.selectedPrinterID == model.selectedPrinter?.id)
}

@MainActor
@Test func manualPrinterProfileRejectsBlankAddress() async {
    let store = RecordingProfileStore()
    let model = AppModel(
        service: EmptyPrinterService(),
        bootstrapClient: FakeBootstrapClient(),
        profileStore: store
    )

    #expect(model.canSubmitManualPrinterAddress("   ") == false)

    let didAdd = model.addManualPrinter(name: "Workshop", address: "   ", checkCode: "123456")

    #expect(didAdd == false)
    #expect(model.printers.isEmpty)
    #expect(store.document.profiles.isEmpty)
    #expect(model.connectionMessage == "Enter the printer address.")
}

@MainActor
@Test func manualPrinterProfileRejectsMalformedAddress() async {
    let store = RecordingProfileStore()
    let model = AppModel(
        service: EmptyPrinterService(),
        bootstrapClient: FakeBootstrapClient(),
        profileStore: store
    )
    #expect(model.canSubmitManualPrinterAddress("http://") == false)
    #expect(model.canSubmitManualPrinterAddress("printer local") == false)

    let didAddBrokenURL = model.addManualPrinter(name: "Workshop", address: "http://", checkCode: "123456")
    let didAddSpacedHost = model.addManualPrinter(name: "Workshop", address: "printer local", checkCode: "123456")

    #expect(didAddBrokenURL == false)
    #expect(didAddSpacedHost == false)
    #expect(model.printers.isEmpty)
    #expect(store.document.profiles.isEmpty)
    #expect(model.connectionMessage == "Enter a valid printer address or URL.")
}

@MainActor
@Test func manualPrinterProfileNormalizesPastedAddressURL() async {
    let store = RecordingProfileStore()
    let model = AppModel(
        service: EmptyPrinterService(),
        bootstrapClient: FakeBootstrapClient(),
        profileStore: store
    )

    #expect(model.manualPrinterAddressPreview(for: " http://192.168.1.77:8898/detail ") == "Will save as 192.168.1.77.")
    #expect(model.manualPrinterAddressValidationMessage(for: " http://192.168.1.77:8898/detail ") == nil)
    #expect(model.canSubmitManualPrinterAddress(" http://192.168.1.77:8898/detail ") == true)

    model.addManualPrinter(
        name: "",
        address: " http://192.168.1.77:8898/detail ",
        checkCode: "123456"
    )

    #expect(model.printers.count == 1)
    #expect(model.selectedPrinter?.name == "192.168.1.77")
    #expect(model.selectedPrinter?.address == "192.168.1.77")
    #expect(store.document.profiles.first?.address == "192.168.1.77")
}

@MainActor
@Test func manualPrinterProfileNormalizesHostPortAndUpdatesExistingProfile() async {
    let store = RecordingProfileStore()
    let model = AppModel(
        service: EmptyPrinterService(),
        bootstrapClient: FakeBootstrapClient(),
        profileStore: store
    )

    #expect(model.manualPrinterAddressPreview(for: "printer.local:8898") == "Will save as printer.local.")
    #expect(model.manualPrinterAddressValidationMessage(for: "http://") == "Enter a valid printer address or URL.")
    #expect(model.canSubmitManualPrinterAddress("printer.local:8898") == true)

    model.addManualPrinter(name: "Old Name", address: "printer.local:8898", checkCode: "111111")
    model.addManualPrinter(name: "New Name", address: "http://printer.local:8899/", checkCode: "222222")

    #expect(model.printers.count == 1)
    #expect(model.selectedPrinter?.name == "New Name")
    #expect(model.selectedPrinter?.address == "printer.local")
    #expect(model.checkCode == "222222")
    #expect(store.document.profiles.count == 1)
}

@MainActor
@Test func manualPrinterProfileUpdatesExistingAddress() async {
    let store = RecordingProfileStore()
    let model = AppModel(
        service: EmptyPrinterService(),
        bootstrapClient: FakeBootstrapClient(),
        profileStore: store
    )

    model.addManualPrinter(name: "Old Name", address: "192.168.1.77", checkCode: "111111")
    model.addManualPrinter(name: "New Name", address: "192.168.1.77", checkCode: "222222")

    #expect(model.printers.count == 1)
    #expect(model.selectedPrinter?.name == "New Name")
    #expect(model.checkCode == "222222")
    #expect(store.document.profiles.count == 1)
    #expect(store.document.profiles.first?.name == "New Name")
    #expect(store.document.profiles.first?.checkCode == "222222")
}

@MainActor
@Test func manualPrinterProfilePreservesDiscoveredPrinterIdentity() async {
    let store = RecordingProfileStore()
    let printer = PrinterSnapshot(
        name: "Desk Printer",
        model: "Adventurer 5M Pro",
        address: "192.168.1.77",
        serialNumber: "SN-DISCOVERED",
        commandPort: 8899,
        eventPort: 8898,
        protocolFormat: .modern,
        status: .ready,
        nozzleTemperature: TemperatureReading(current: 32),
        bedTemperature: TemperatureReading(current: 29)
    )
    let model = AppModel(
        service: EmptyPrinterService(),
        bootstrapClient: FakeBootstrapClient(),
        profileStore: store,
        printers: [printer]
    )

    model.addManualPrinter(name: "Workshop", address: "192.168.1.77", checkCode: "123456")

    #expect(model.printers.count == 1)
    #expect(model.selectedPrinter?.name == "Workshop")
    #expect(model.selectedPrinter?.model == "Adventurer 5M Pro")
    #expect(model.selectedPrinter?.serialNumber == "SN-DISCOVERED")
    #expect(model.selectedPrinter?.status == .ready)
    #expect(model.checkCode == "123456")
    #expect(store.document.profiles.first?.model == "Adventurer 5M Pro")
    #expect(store.document.profiles.first?.serialNumber == "SN-DISCOVERED")
    #expect(store.document.profiles.first?.checkCode == "123456")
}

@MainActor
@Test func removeSelectedPrinterDeletesProfileAndSelectsRemainingPrinter() async {
    let store = RecordingProfileStore()
    let model = AppModel(
        service: EmptyPrinterService(),
        bootstrapClient: FakeBootstrapClient(),
        profileStore: store
    )

    model.addManualPrinter(name: "First", address: "192.168.1.77", checkCode: "111111")
    let firstID = model.selectedPrinter?.id
    model.addManualPrinter(name: "Second", address: "192.168.1.78", checkCode: "222222")
    let removedID = model.selectedPrinter?.id

    #expect(model.selectedPrinterRemovalConfirmationTitle == "Forget Second?")
    #expect(model.selectedPrinterRemovalConfirmationMessage == "This removes the saved profile, check code, camera settings, and cached status from this app.")
    model.removeSelectedPrinter()

    #expect(model.printers.count == 1)
    #expect(model.selectedPrinter?.id == firstID)
    #expect(store.document.profiles.count == 1)
    #expect(store.document.profiles.first?.id == firstID)
    #expect(store.document.profiles.contains { $0.id == removedID } == false)
    #expect(store.document.selectedPrinterID == firstID)
    #expect(model.checkCode == "111111")
}

@MainActor
@Test func selectedPrinterConnectReadinessExplainsMissingSelection() async {
    let model = AppModel(service: EmptyPrinterService(), bootstrapClient: FakeBootstrapClient())

    #expect(model.selectedPrinterConnectReadinessMessage == "Select a printer first.")
    #expect(model.canConnectSelectedPrinter == false)

    await model.connectSelectedPrinter()

    #expect(model.connectionMessage == "Select a printer first.")
}

@MainActor
@Test func connectSelectedPrinterFetchesBootstrapInfo() async {
    let printer = PrinterSnapshot(
        name: "Desk Printer",
        model: "Unknown",
        address: "192.168.1.44",
        commandPort: 8899,
        status: .ready,
        nozzleTemperature: TemperatureReading(current: 0),
        bedTemperature: TemperatureReading(current: 0)
    )
    let model = AppModel(
        service: PreviewPrinterService(),
        bootstrapClient: FakeBootstrapClient(),
        printers: [printer]
    )
    model.selection = .printer(printer.id)

    #expect(model.selectedPrinterConnectReadinessMessage == nil)
    #expect(model.canConnectSelectedPrinter == true)
    #expect(model.selectedPrinterIdentitySummary == "Connect to identify serial number.")

    await model.connectSelectedPrinter()

    #expect(model.lastPrinterInfo?.typeName == "FlashForge Adventurer 5M Pro")
    #expect(model.selectedPrinterIdentitySummary == "Serial SN-TEST")
    #expect(model.connectionMessage == "Desk Printer reports FlashForge Adventurer 5M Pro.")
    #expect(model.isConnecting == false)
}

@MainActor
@Test func connectSelectedPrinterRefreshesStatusWhenCheckCodeIsSaved() async {
    let modernClient = RecordingModernClient(status: .printing)
    let printer = PrinterSnapshot(
        name: "Desk Printer",
        model: "Unknown",
        address: "192.168.1.44",
        commandPort: 8899,
        eventPort: 8898,
        status: .ready,
        nozzleTemperature: TemperatureReading(current: 0),
        bedTemperature: TemperatureReading(current: 0)
    )
    let model = AppModel(
        service: PreviewPrinterService(),
        bootstrapClient: FakeBootstrapClient(),
        modernClient: modernClient,
        printers: [printer]
    )
    model.selection = .printer(printer.id)
    model.checkCode = "123456"

    await model.connectSelectedPrinter()

    #expect(model.lastPrinterInfo?.serialNumber == "SN-TEST")
    #expect(modernClient.requestCount == 1)
    #expect(modernClient.lastHost == "192.168.1.44")
    #expect(modernClient.lastSerialNumber == "SN-TEST")
    #expect(modernClient.lastCheckCode == "123456")
    #expect(model.selectedPrinter?.status == .printing)
    #expect(model.connectionMessage == "Desk Printer status is Printing.")
    #expect(model.isConnecting == false)
}

@MainActor
@Test func connectSelectedPrinterExplainsUnreachablePrinter() async {
    let printer = PrinterSnapshot(
        name: "Desk Printer",
        model: "Unknown",
        address: "192.168.1.44",
        commandPort: 8899,
        status: .offline,
        nozzleTemperature: TemperatureReading(current: 0),
        bedTemperature: TemperatureReading(current: 0)
    )
    let bootstrapClient = RecordingBootstrapClient(
        infosByHost: [:],
        failingHosts: ["192.168.1.44"]
    )
    let model = AppModel(
        service: EmptyPrinterService(),
        bootstrapClient: bootstrapClient,
        printers: [printer]
    )
    model.selection = .printer(printer.id)

    await model.connectSelectedPrinter()

    #expect(bootstrapClient.requestedHosts == ["192.168.1.44"])
    #expect(model.lastPrinterInfo == nil)
    #expect(model.selectedPrinter?.serialNumber == nil)
    #expect(model.connectionMessage == "Could not identify Desk Printer at 192.168.1.44:8899. Check that the printer is powered on and reachable on the local network.")
    #expect(model.isConnecting == false)
}

@MainActor
@Test func connectKnownPrintersIdentifiesSavedProfiles() async {
    let firstID = UUID()
    let secondID = UUID()
    let bootstrapClient = RecordingBootstrapClient(
        infosByHost: [
            "192.168.1.44": PrinterInfo(
                typeName: "FlashForge Adventurer 5M Pro",
                name: "Studio",
                firmwareVersion: "3.1.2",
                serialNumber: "SN-FIRST"
            ),
            "192.168.1.45": PrinterInfo(
                typeName: "FlashForge AD5X",
                name: "Workshop",
                firmwareVersion: "3.2.0",
                serialNumber: "SN-SECOND"
            )
        ]
    )
    let store = RecordingProfileStore(
        document: PrinterProfileDocument(
            profiles: [
                PrinterProfile(
                    id: firstID,
                    name: "Studio",
                    model: "Unknown",
                    address: "192.168.1.44",
                    commandPort: 8899
                ),
                PrinterProfile(
                    id: secondID,
                    name: "Workshop",
                    model: "Unknown",
                    address: "192.168.1.45",
                    commandPort: 8899
                )
            ],
            selectedPrinterID: firstID
        )
    )
    let model = AppModel(
        service: EmptyPrinterService(),
        bootstrapClient: bootstrapClient,
        profileStore: store
    )

    let identifiedCount = await model.connectKnownPrinters()

    #expect(identifiedCount == 2)
    #expect(bootstrapClient.requestedHosts == ["192.168.1.44", "192.168.1.45"])
    #expect(model.identifiedPrinterCount == 2)
    #expect(model.printers.first { $0.id == firstID }?.serialNumber == "SN-FIRST")
    #expect(model.printers.first { $0.id == secondID }?.model == "FlashForge AD5X")
    #expect(store.document.profiles.first { $0.id == secondID }?.serialNumber == "SN-SECOND")
    #expect(model.lastPrinterInfo?.serialNumber == "SN-FIRST")
    model.selection = .printer(secondID)
    #expect(model.lastPrinterInfo?.serialNumber == "SN-SECOND")
    #expect(model.connectionMessage == "Identified 2 printers.")
    #expect(model.isConnectingKnownPrinters == false)
}

@MainActor
@Test func connectKnownPrintersCountsOnlySuccessfulIdentifications() async {
    let firstID = UUID()
    let secondID = UUID()
    let bootstrapClient = RecordingBootstrapClient(
        infosByHost: [
            "192.168.1.44": PrinterInfo(
                typeName: "FlashForge Adventurer 5M Pro",
                name: "Studio",
                firmwareVersion: "3.1.2",
                serialNumber: "SN-FIRST"
            )
        ],
        failingHosts: ["192.168.1.45"]
    )
    let store = RecordingProfileStore(
        document: PrinterProfileDocument(
            profiles: [
                PrinterProfile(
                    id: firstID,
                    name: "Studio",
                    model: "Unknown",
                    address: "192.168.1.44",
                    commandPort: 8899
                ),
                PrinterProfile(
                    id: secondID,
                    name: "Workshop",
                    model: "Unknown",
                    address: "192.168.1.45",
                    commandPort: 8899
                )
            ],
            selectedPrinterID: firstID
        )
    )
    let model = AppModel(
        service: EmptyPrinterService(),
        bootstrapClient: bootstrapClient,
        profileStore: store
    )

    let identifiedCount = await model.connectKnownPrinters()

    #expect(identifiedCount == 1)
    #expect(bootstrapClient.requestedHosts == ["192.168.1.44", "192.168.1.45"])
    #expect(model.identifiedPrinterCount == 1)
    #expect(model.printers.first { $0.id == firstID }?.serialNumber == "SN-FIRST")
    #expect(model.printers.first { $0.id == secondID }?.serialNumber == nil)
    #expect(model.connectionMessage == "Identified 1 of 2 printers. Check the remaining printers' addresses and local network.")
}

@MainActor
@Test func connectKnownPrintersExplainsWhenNoPrintersIdentify() async {
    let firstID = UUID()
    let secondID = UUID()
    let bootstrapClient = RecordingBootstrapClient(
        infosByHost: [:],
        failingHosts: ["192.168.1.44", "192.168.1.45"]
    )
    let store = RecordingProfileStore(
        document: PrinterProfileDocument(
            profiles: [
                PrinterProfile(
                    id: firstID,
                    name: "Studio",
                    model: "Unknown",
                    address: "192.168.1.44",
                    commandPort: 8899
                ),
                PrinterProfile(
                    id: secondID,
                    name: "Workshop",
                    model: "Unknown",
                    address: "192.168.1.45",
                    commandPort: 8899
                )
            ],
            selectedPrinterID: firstID
        )
    )
    let model = AppModel(
        service: EmptyPrinterService(),
        bootstrapClient: bootstrapClient,
        profileStore: store
    )

    let identifiedCount = await model.connectKnownPrinters()

    #expect(identifiedCount == 0)
    #expect(bootstrapClient.requestedHosts == ["192.168.1.44", "192.168.1.45"])
    #expect(model.identifiedPrinterCount == 0)
    #expect(model.connectionMessage == "Could not identify any printers. Check that they are powered on and reachable on the local network.")
    #expect(model.isConnectingKnownPrinters == false)
}

@MainActor
@Test func refreshSelectedPrinterStatusMergesModernDetail() async {
    let printer = PrinterSnapshot(
        name: "Desk Printer",
        model: "Unknown",
        address: "192.168.1.44",
        serialNumber: "SN-TEST",
        commandPort: 8899,
        eventPort: 8898,
        status: .ready,
        nozzleTemperature: TemperatureReading(current: 0),
        bedTemperature: TemperatureReading(current: 0)
    )
    let model = AppModel(
        service: PreviewPrinterService(),
        bootstrapClient: FakeBootstrapClient(),
        modernClient: FakeModernClient(),
        printers: [printer]
    )
    model.selection = .printer(printer.id)
    model.checkCode = "123456"

    #expect(model.selectedPrinterStatusRefreshReadinessMessage == nil)
    #expect(model.canRefreshSelectedPrinterStatus == true)
    #expect(model.selectedPrinterStatusRecencySummary == "Status not refreshed yet.")

    await model.refreshSelectedPrinterStatus()

    #expect(model.selectedPrinter?.model == "AD5X")
    #expect(model.selectedPrinter?.status == .printing)
    #expect(model.selectedPrinter?.nozzleTemperature.current == 221)
    #expect(model.selectedPrinter?.activeJob?.fileName == "benchy.3mf")
    #expect(model.selectedPrinter?.materialStation?.activeSlot == 1)
    #expect(model.selectedPrinter?.materialStation?.slots.first?.materialType == "PLA")
    #expect(model.selectedCameraStreamConfig.sourceType == .oem)
    #expect(model.selectedCameraStreamConfig.streamURL?.absoluteString == "rtsp://192.168.1.44/live")
    #expect(model.lastUpdated != nil)
    #expect(model.selectedPrinterStatusRecencySummary != "Status not refreshed yet.")
    #expect(model.connectionMessage == "Desk Printer status is Printing.")
    #expect(model.isRefreshingStatus == false)
}

@MainActor
@Test func selectedStatusRecencyIsTrackedPerPrinter() async {
    let firstPrinter = PrinterSnapshot(
        name: "Studio",
        model: "AD5X",
        address: "192.168.1.44",
        serialNumber: "SN-FIRST",
        eventPort: 8898,
        status: .ready,
        nozzleTemperature: TemperatureReading(current: 30),
        bedTemperature: TemperatureReading(current: 28)
    )
    let secondPrinter = PrinterSnapshot(
        name: "Workshop",
        model: "Adventurer 5M Pro",
        address: "192.168.1.45",
        serialNumber: "SN-SECOND",
        eventPort: 8898,
        status: .ready,
        nozzleTemperature: TemperatureReading(current: 29),
        bedTemperature: TemperatureReading(current: 27)
    )
    let model = AppModel(
        service: EmptyPrinterService(),
        bootstrapClient: FakeBootstrapClient(),
        modernClient: RecordingModernClient(status: .ready),
        printers: [firstPrinter, secondPrinter]
    )

    model.selection = .printer(firstPrinter.id)
    model.checkCode = "111111"
    #expect(model.selectedPrinterStatusRecencySummary == "Status not refreshed yet.")

    await model.refreshSelectedPrinterStatus()

    #expect(model.lastUpdated != nil)
    #expect(model.selectedPrinterStatusRecencySummary != "Status not refreshed yet.")

    model.selection = .printer(secondPrinter.id)

    #expect(model.selectedPrinterStatusRecencySummary == "Status not refreshed yet.")
}

@MainActor
@Test func refreshSelectedPrinterStatusExplainsMissingSerialNumber() async {
    let client = RecordingModernClient(status: .ready)
    let printer = PrinterSnapshot(
        name: "Desk Printer",
        model: "Unknown",
        address: "192.168.1.44",
        eventPort: 8898,
        status: .ready,
        nozzleTemperature: TemperatureReading(current: 0),
        bedTemperature: TemperatureReading(current: 0)
    )
    let model = AppModel(
        service: PreviewPrinterService(),
        bootstrapClient: FakeBootstrapClient(),
        modernClient: client,
        printers: [printer]
    )
    model.selection = .printer(printer.id)
    model.checkCode = "123456"

    #expect(model.selectedPrinterStatusRefreshReadinessMessage == "This printer did not report a serial number.")
    #expect(model.canRefreshSelectedPrinterStatus == false)

    let didRefresh = await model.refreshSelectedPrinterStatus()

    #expect(didRefresh == false)
    #expect(client.requestCount == 0)
    #expect(model.connectionMessage == "This printer did not report a serial number.")
    #expect(model.isRefreshingStatus == false)
}

@MainActor
@Test func backgroundRefreshSkipsPrinterWithoutCredentials() async {
    let client = RecordingModernClient(status: .ready)
    let printer = PrinterSnapshot(
        name: "Desk Printer",
        model: "Unknown",
        address: "192.168.1.44",
        serialNumber: "SN-TEST",
        eventPort: 8898,
        status: .ready,
        nozzleTemperature: TemperatureReading(current: 0),
        bedTemperature: TemperatureReading(current: 0)
    )
    let model = AppModel(
        service: PreviewPrinterService(),
        bootstrapClient: FakeBootstrapClient(),
        modernClient: client,
        printers: [printer]
    )
    model.selection = .printer(printer.id)
    model.connectionMessage = "Standing by."

    #expect(model.selectedPrinterStatusRefreshReadinessMessage == "Enter the printer check code to refresh status.")
    #expect(model.canRefreshSelectedPrinterStatus == false)

    let didRefresh = await model.refreshSelectedPrinterStatusInBackground()

    #expect(didRefresh == false)
    #expect(client.requestCount == 0)
    #expect(model.connectionMessage == "Standing by.")
    #expect(model.isRefreshingStatus == false)
}

@MainActor
@Test func statusRefreshContextExplainsPrinterCredentialState() async {
    let identifiedPrinter = PrinterSnapshot(
        name: "Desk Printer",
        model: "Unknown",
        address: "192.168.1.44",
        serialNumber: "SN-TEST",
        eventPort: 8898,
        status: .ready,
        nozzleTemperature: TemperatureReading(current: 0),
        bedTemperature: TemperatureReading(current: 0)
    )
    let unidentifiedPrinter = PrinterSnapshot(
        name: "New Printer",
        model: "Unknown",
        address: "192.168.1.45",
        status: .offline,
        nozzleTemperature: TemperatureReading(current: 0),
        bedTemperature: TemperatureReading(current: 0)
    )
    let model = AppModel(
        service: PreviewPrinterService(),
        bootstrapClient: FakeBootstrapClient(),
        printers: [identifiedPrinter, unidentifiedPrinter]
    )

    #expect(model.statusRefreshContextMessage(for: identifiedPrinter) == "Needs check code.")
    #expect(model.canRefreshStatus(for: identifiedPrinter) == false)
    #expect(model.statusRefreshContextMessage(for: unidentifiedPrinter) == "Identify printer first.")
    #expect(model.canRefreshStatus(for: unidentifiedPrinter) == false)

    model.selection = .printer(identifiedPrinter.id)
    model.checkCode = "123456"

    #expect(model.statusRefreshContextMessage(for: identifiedPrinter) == "Ready to refresh.")
    #expect(model.canRefreshStatus(for: identifiedPrinter) == true)
}

@MainActor
@Test func backgroundRefreshUsesModernClientWhenCredentialsAreReady() async {
    let client = RecordingModernClient(status: .printing)
    let printer = PrinterSnapshot(
        name: "Desk Printer",
        model: "Unknown",
        address: "192.168.1.44",
        serialNumber: "SN-TEST",
        eventPort: 8898,
        status: .ready,
        nozzleTemperature: TemperatureReading(current: 0),
        bedTemperature: TemperatureReading(current: 0)
    )
    let model = AppModel(
        service: PreviewPrinterService(),
        bootstrapClient: FakeBootstrapClient(),
        modernClient: client,
        printers: [printer]
    )
    model.selection = .printer(printer.id)
    model.checkCode = "123456"

    let didRefresh = await model.refreshSelectedPrinterStatusInBackground()

    #expect(didRefresh == true)
    #expect(client.requestCount == 1)
    #expect(client.lastHost == "192.168.1.44")
    #expect(client.lastCheckCode == "123456")
    #expect(model.selectedPrinter?.status == .printing)
    #expect(model.connectionMessage == "Desk Printer status is Printing.")
    #expect(model.isRefreshingStatus == false)
}

@MainActor
@Test func refreshSelectedPrinterStatusNamesUnreachablePrinter() async {
    let client = FailingModernClient(error: URLError(.cannotConnectToHost))
    let printer = PrinterSnapshot(
        name: "Desk Printer",
        model: "Unknown",
        address: "192.168.1.44",
        serialNumber: "SN-TEST",
        eventPort: 8898,
        status: .ready,
        nozzleTemperature: TemperatureReading(current: 0),
        bedTemperature: TemperatureReading(current: 0)
    )
    let model = AppModel(
        service: PreviewPrinterService(),
        bootstrapClient: FakeBootstrapClient(),
        modernClient: client,
        printers: [printer]
    )
    model.selection = .printer(printer.id)
    model.checkCode = "123456"

    let didRefresh = await model.refreshSelectedPrinterStatus()

    #expect(didRefresh == false)
    #expect(client.requestCount == 1)
    #expect(model.selectedPrinterStatusFailureSummary == "Last refresh failed. Check the check code and network.")
    #expect(model.connectionMessage == "Could not refresh Desk Printer at 192.168.1.44. Check the check code and network.")
    #expect(model.isRefreshingStatus == false)
}

@MainActor
@Test func transportStatusRefreshFailureSuggestsNetworkCheck() async {
    let client = FailingModernClient(error: ModernPrinterHTTPError.transportFailed)
    let printer = PrinterSnapshot(
        name: "Desk Printer",
        model: "Unknown",
        address: "192.168.1.44",
        serialNumber: "SN-TEST",
        eventPort: 8898,
        status: .ready,
        nozzleTemperature: TemperatureReading(current: 0),
        bedTemperature: TemperatureReading(current: 0)
    )
    let model = AppModel(
        service: PreviewPrinterService(),
        bootstrapClient: FakeBootstrapClient(),
        modernClient: client,
        printers: [printer]
    )
    model.selection = .printer(printer.id)
    model.checkCode = "123456"

    let didRefresh = await model.refreshSelectedPrinterStatus()

    #expect(didRefresh == false)
    #expect(model.selectedPrinterStatusFailureSummary == "Last refresh failed. Check that the printer is online and reachable on the network.")
    #expect(model.connectionMessage == "Could not refresh Desk Printer at 192.168.1.44. Check that the printer is online and reachable on the network.")
}

@MainActor
@Test func httpStatusRefreshFailureShowsStatusAndPrinterReason() async {
    let client = FailingModernClient(error: ModernPrinterHTTPError.httpStatus(403, "Check code is invalid"))
    let printer = PrinterSnapshot(
        name: "Desk Printer",
        model: "Unknown",
        address: "192.168.1.44",
        serialNumber: "SN-TEST",
        eventPort: 8898,
        status: .ready,
        nozzleTemperature: TemperatureReading(current: 0),
        bedTemperature: TemperatureReading(current: 0)
    )
    let model = AppModel(
        service: PreviewPrinterService(),
        bootstrapClient: FakeBootstrapClient(),
        modernClient: client,
        printers: [printer]
    )
    model.selection = .printer(printer.id)
    model.checkCode = "123456"

    let didRefresh = await model.refreshSelectedPrinterStatus()

    #expect(didRefresh == false)
    #expect(model.selectedPrinterStatusFailureSummary == "Last refresh failed with HTTP 403: Check code is invalid.")
    #expect(model.connectionMessage == "Could not refresh Desk Printer at 192.168.1.44. Printer returned HTTP 403: Check code is invalid.")
    #expect(model.isRefreshingStatus == false)
}

@MainActor
@Test func successfulStatusRefreshClearsPriorFailureSummary() async {
    let client = FlakyModernClient(failuresBeforeSuccess: 1, status: .ready)
    let printer = PrinterSnapshot(
        name: "Desk Printer",
        model: "Unknown",
        address: "192.168.1.44",
        serialNumber: "SN-TEST",
        eventPort: 8898,
        status: .printing,
        nozzleTemperature: TemperatureReading(current: 221),
        bedTemperature: TemperatureReading(current: 58),
        activeJob: PrintJobSnapshot(fileName: "benchy.3mf", progress: 0.4)
    )
    let model = AppModel(
        service: PreviewPrinterService(),
        bootstrapClient: FakeBootstrapClient(),
        modernClient: client,
        printers: [printer]
    )
    model.selection = .printer(printer.id)
    model.checkCode = "123456"

    let failedRefresh = await model.refreshSelectedPrinterStatus()

    #expect(failedRefresh == false)
    #expect(model.selectedPrinterStatusFailureSummary == "Last refresh failed. Check the check code and network.")

    let successfulRefresh = await model.refreshSelectedPrinterStatus()

    #expect(successfulRefresh == true)
    #expect(client.requestCount == 2)
    #expect(model.selectedPrinterStatusFailureSummary == nil)
    #expect(model.selectedPrinter?.status == .ready)
}

@MainActor
@Test func refreshKnownPrinterStatusesUpdatesRefreshableProfiles() async {
    let firstID = UUID()
    let secondID = UUID()
    let client = RecordingModernClient(status: .printing)
    let store = RecordingProfileStore(
        document: PrinterProfileDocument(
            profiles: [
                PrinterProfile(
                    id: firstID,
                    name: "Studio",
                    model: "AD5X",
                    address: "192.168.1.44",
                    serialNumber: "SN-FIRST",
                    eventPort: 8898,
                    checkCode: "111111"
                ),
                PrinterProfile(
                    id: secondID,
                    name: "Workshop",
                    model: "Adventurer 5M Pro",
                    address: "192.168.1.45",
                    serialNumber: "SN-SECOND",
                    eventPort: 8898,
                    checkCode: "222222"
                )
            ],
            selectedPrinterID: firstID
        )
    )
    let model = AppModel(
        service: EmptyPrinterService(),
        bootstrapClient: FakeBootstrapClient(),
        modernClient: client,
        profileStore: store
    )

    let refreshedCount = await model.refreshKnownPrinterStatuses()

    #expect(refreshedCount == 2)
    #expect(client.requestCount == 2)
    #expect(client.requestedHosts == ["192.168.1.44", "192.168.1.45"])
    #expect(model.refreshablePrinterCount == 2)
    #expect(model.printers.allSatisfy { $0.status == .printing })
    #expect(model.connectionMessage == "Refreshed 2 printers.")
    #expect(model.isRefreshingAllStatuses == false)
}

@MainActor
@Test func refreshKnownPrinterStatusesExplainsAllFailures() async {
    let firstID = UUID()
    let secondID = UUID()
    let client = FailingModernClient(error: URLError(.cannotConnectToHost))
    let store = RecordingProfileStore(
        document: PrinterProfileDocument(
            profiles: [
                PrinterProfile(
                    id: firstID,
                    name: "Studio",
                    model: "AD5X",
                    address: "192.168.1.44",
                    serialNumber: "SN-FIRST",
                    eventPort: 8898,
                    checkCode: "111111"
                ),
                PrinterProfile(
                    id: secondID,
                    name: "Workshop",
                    model: "Adventurer 5M Pro",
                    address: "192.168.1.45",
                    serialNumber: "SN-SECOND",
                    eventPort: 8898,
                    checkCode: "222222"
                )
            ],
            selectedPrinterID: firstID
        )
    )
    let model = AppModel(
        service: EmptyPrinterService(),
        bootstrapClient: FakeBootstrapClient(),
        modernClient: client,
        profileStore: store
    )

    let refreshedCount = await model.refreshKnownPrinterStatuses()

    #expect(refreshedCount == 0)
    #expect(client.requestCount == 2)
    #expect(model.statusFailureSummary(for: model.printers[0]) == "Last refresh failed. Check the check code and network.")
    #expect(model.statusFailureSummary(for: model.printers[1]) == "Last refresh failed. Check the check code and network.")
    #expect(model.connectionMessage == "Could not refresh any printers. Check saved check codes and network.")
    #expect(model.isRefreshingAllStatuses == false)
}

@MainActor
@Test func refreshKnownPrinterStatusesSkipsProfilesWithoutSavedCredentials() async {
    let firstID = UUID()
    let secondID = UUID()
    let client = RecordingModernClient(status: .ready)
    let store = RecordingProfileStore(
        document: PrinterProfileDocument(
            profiles: [
                PrinterProfile(
                    id: firstID,
                    name: "Studio",
                    model: "AD5X",
                    address: "192.168.1.44",
                    serialNumber: "SN-FIRST",
                    eventPort: 8898,
                    checkCode: "111111"
                ),
                PrinterProfile(
                    id: secondID,
                    name: "Workshop",
                    model: "Adventurer 5M Pro",
                    address: "192.168.1.45",
                    serialNumber: "SN-SECOND",
                    eventPort: 8898
                )
            ],
            selectedPrinterID: firstID
        )
    )
    let model = AppModel(
        service: EmptyPrinterService(),
        bootstrapClient: FakeBootstrapClient(),
        modernClient: client,
        profileStore: store
    )

    let refreshedCount = await model.refreshKnownPrinterStatuses()

    #expect(refreshedCount == 1)
    #expect(client.requestCount == 1)
    #expect(client.requestedHosts == ["192.168.1.44"])
    #expect(model.refreshablePrinterCount == 1)
    #expect(model.printers.first { $0.id == firstID }?.status == .ready)
    #expect(model.printers.first { $0.id == secondID }?.status == .offline)
    #expect(model.connectionMessage == "Refreshed 1 printer.")
}

@MainActor
@Test func backgroundRefreshKnownPrinterStatusesLeavesMessageUntouched() async {
    let firstID = UUID()
    let client = RecordingModernClient(status: .printing)
    let store = RecordingProfileStore(
        document: PrinterProfileDocument(
            profiles: [
                PrinterProfile(
                    id: firstID,
                    name: "Studio",
                    model: "AD5X",
                    address: "192.168.1.44",
                    serialNumber: "SN-FIRST",
                    eventPort: 8898,
                    checkCode: "111111"
                )
            ],
            selectedPrinterID: firstID
        )
    )
    let model = AppModel(
        service: EmptyPrinterService(),
        bootstrapClient: FakeBootstrapClient(),
        modernClient: client,
        profileStore: store
    )
    model.connectionMessage = "Loaded saved printers."

    let refreshedCount = await model.refreshKnownPrinterStatusesInBackground()

    #expect(refreshedCount == 1)
    #expect(client.requestCount == 1)
    #expect(model.selectedPrinter?.status == .printing)
    #expect(model.connectionMessage == "Loaded saved printers.")
    #expect(model.isRefreshingAllStatuses == false)
}

@MainActor
@Test func backgroundRefreshKnownPrinterStatusesWithoutEligiblePrintersIsQuiet() async {
    let client = RecordingModernClient(status: .ready)
    let store = RecordingProfileStore(
        document: PrinterProfileDocument(
            profiles: [
                PrinterProfile(
                    name: "Studio",
                    model: "Unknown",
                    address: "192.168.1.44",
                    serialNumber: "SN-FIRST",
                    eventPort: 8898
                )
            ]
        )
    )
    let model = AppModel(
        service: EmptyPrinterService(),
        bootstrapClient: FakeBootstrapClient(),
        modernClient: client,
        profileStore: store
    )
    model.connectionMessage = "Standing by."

    let refreshedCount = await model.refreshKnownPrinterStatusesInBackground()

    #expect(refreshedCount == 0)
    #expect(client.requestCount == 0)
    #expect(model.connectionMessage == "Standing by.")
}

@MainActor
@Test func refreshSelectedPrinterStatusUsesCameraFallbackWhenModernPrinterOmitsStreamURL() async {
    let printer = PrinterSnapshot(
        name: "Desk Printer",
        model: "Unknown",
        address: "192.168.1.44",
        serialNumber: "SN-TEST",
        commandPort: 8899,
        eventPort: 8898,
        status: .ready,
        nozzleTemperature: TemperatureReading(current: 0),
        bedTemperature: TemperatureReading(current: 0)
    )
    let model = AppModel(
        service: PreviewPrinterService(),
        bootstrapClient: FakeBootstrapClient(),
        modernClient: FakeModernProNoCameraURLClient(),
        printers: [printer]
    )
    model.selection = .printer(printer.id)
    model.checkCode = "123456"

    await model.refreshSelectedPrinterStatus()

    #expect(model.selectedPrinter?.cameraState == .available)
    #expect(model.selectedCameraStreamConfig.sourceType == .intelligentFallback)
    #expect(model.selectedCameraStreamConfig.streamType == .mjpeg)
    #expect(model.selectedCameraStreamConfig.streamURL?.absoluteString == "http://192.168.1.44:8080/?action=stream")
    #expect(model.selectedCameraStreamURL?.absoluteString == "http://192.168.1.44:8080/?action=stream")
}

@MainActor
@Test func selectedCameraStreamUsesKnownModelFallbackBeforeStatusRefresh() async {
    let ad5xPrinter = PrinterSnapshot(
        name: "Workshop",
        model: "FlashForge AD5X",
        address: "192.168.1.44",
        serialNumber: "SN-AD5X",
        eventPort: 8898,
        status: .ready,
        nozzleTemperature: TemperatureReading(current: 30),
        bedTemperature: TemperatureReading(current: 28)
    )
    let proPrinter = PrinterSnapshot(
        name: "Studio",
        model: "FlashForge Adventurer 5M Pro",
        address: "192.168.1.45",
        serialNumber: "SN-PRO",
        eventPort: 8898,
        status: .ready,
        nozzleTemperature: TemperatureReading(current: 31),
        bedTemperature: TemperatureReading(current: 29)
    )
    let model = AppModel(
        service: EmptyPrinterService(),
        bootstrapClient: FakeBootstrapClient(),
        printers: [ad5xPrinter, proPrinter]
    )

    model.selection = .printer(ad5xPrinter.id)

    #expect(model.lastModernStatus == nil)
    #expect(model.selectedCameraStreamConfig.sourceType == .intelligentFallback)
    #expect(model.selectedCameraStreamConfig.streamType == .mjpeg)
    #expect(model.selectedCameraStreamURL?.absoluteString == "http://192.168.1.44:8080/?action=stream")
    #expect(model.resolvedCameraState(for: ad5xPrinter) == .available)

    model.selection = .printer(proPrinter.id)

    #expect(model.lastModernStatus == nil)
    #expect(model.selectedCameraStreamConfig.sourceType == .intelligentFallback)
    #expect(model.selectedCameraStreamConfig.streamType == .mjpeg)
    #expect(model.selectedCameraStreamURL?.absoluteString == "http://192.168.1.45:8080/?action=stream")
    #expect(model.resolvedCameraState(for: proPrinter) == .available)
}

@MainActor
@Test func selectedCameraStreamDoesNotInventFallbackForStandard5MModel() async {
    let printer = PrinterSnapshot(
        name: "Desk Printer",
        model: "FlashForge Adventurer 5M",
        address: "192.168.1.46",
        serialNumber: "SN-5M",
        eventPort: 8898,
        status: .ready,
        nozzleTemperature: TemperatureReading(current: 29),
        bedTemperature: TemperatureReading(current: 27)
    )
    let model = AppModel(
        service: EmptyPrinterService(),
        bootstrapClient: FakeBootstrapClient(),
        printers: [printer]
    )
    model.selection = .printer(printer.id)

    #expect(model.lastModernStatus == nil)
    #expect(model.selectedCameraStreamConfig.isAvailable == false)
    #expect(model.selectedCameraStreamURL == nil)
    #expect(model.resolvedCameraState(for: printer) == .unavailable)
}

@MainActor
@Test func selectedCameraStreamDoesNotReuseAnotherPrintersCachedStatus() async {
    let firstPrinter = PrinterSnapshot(
        name: "Studio",
        model: "AD5X",
        address: "192.168.1.44",
        serialNumber: "SN-FIRST",
        eventPort: 8898,
        status: .ready,
        nozzleTemperature: TemperatureReading(current: 30),
        bedTemperature: TemperatureReading(current: 28)
    )
    let secondPrinter = PrinterSnapshot(
        name: "Workshop",
        model: "Adventurer 5M",
        address: "192.168.1.45",
        serialNumber: "SN-SECOND",
        eventPort: 8898,
        status: .ready,
        nozzleTemperature: TemperatureReading(current: 29),
        bedTemperature: TemperatureReading(current: 27)
    )
    let model = AppModel(
        service: EmptyPrinterService(),
        bootstrapClient: FakeBootstrapClient(),
        printers: [firstPrinter, secondPrinter]
    )

    model.selection = .printer(firstPrinter.id)
    model.lastModernStatus = ModernPrinterStatus(
        displayName: "Studio",
        firmwareVersion: "3.2.0",
        pid: 38,
        isPro: false,
        isAD5X: true,
        state: .ready,
        nozzleCurrent: 30,
        nozzleTarget: 0,
        bedCurrent: 28,
        bedTarget: 0,
        cameraStreamURL: "rtsp://192.168.1.44/live"
    )

    model.selection = .printer(secondPrinter.id)

    #expect(model.lastModernStatus == nil)
    #expect(model.selectedCameraStreamConfig.isAvailable == false)
    #expect(model.selectedCameraStreamURL == nil)
    #expect(model.selectedCameraStreamConfig.streamURL == nil)
}

@MainActor
@Test func acknowledgeCameraOpenReportsResolvedStreamURL() async {
    let printer = PrinterSnapshot(
        name: "Desk Printer",
        model: "Unknown",
        address: "192.168.1.44",
        serialNumber: "SN-TEST",
        commandPort: 8899,
        eventPort: 8898,
        status: .ready,
        nozzleTemperature: TemperatureReading(current: 0),
        bedTemperature: TemperatureReading(current: 0)
    )
    let model = AppModel(
        service: PreviewPrinterService(),
        bootstrapClient: FakeBootstrapClient(),
        modernClient: FakeModernProNoCameraURLClient(),
        printers: [printer]
    )
    model.selection = .printer(printer.id)
    model.checkCode = "123456"

    await model.refreshSelectedPrinterStatus()
    model.acknowledgeCameraOpen()

    #expect(model.connectionMessage == "Camera preview ready: http://192.168.1.44:8080/?action=stream")
}

@MainActor
@Test func acknowledgeCameraOpenExplainsRTSPSystemHandoff() async {
    let printer = PrinterSnapshot(
        name: "Desk Printer",
        model: "Unknown",
        address: "192.168.1.44",
        serialNumber: "SN-TEST",
        commandPort: 8899,
        eventPort: 8898,
        status: .ready,
        nozzleTemperature: TemperatureReading(current: 0),
        bedTemperature: TemperatureReading(current: 0)
    )
    let model = AppModel(
        service: PreviewPrinterService(),
        bootstrapClient: FakeBootstrapClient(),
        modernClient: FakeModernClient(),
        printers: [printer]
    )
    model.selection = .printer(printer.id)
    model.checkCode = "123456"

    await model.refreshSelectedPrinterStatus()
    model.acknowledgeCameraOpen()

    #expect(model.connectionMessage == "Opening RTSP stream in the default app: rtsp://192.168.1.44/live")
}

@MainActor
@Test func selectedJobCommandReadinessExplainsMissingSelection() async {
    let model = AppModel(service: EmptyPrinterService(), bootstrapClient: FakeBootstrapClient())

    #expect(model.selectedPrinterJobCommandReadinessMessage(for: .pause) == "Select a printer first.")
    #expect(model.canSendSelectedPrinterJobCommand(.pause) == false)
    #expect(model.selectedJobControlSummary == nil)

    await model.sendSelectedPrinterJobCommand(.pause)

    #expect(model.connectionMessage == "Select a printer first.")
}

@MainActor
@Test func pauseSelectedPrintSendsModernCommandAndUpdatesState() async {
    let commandClient = RecordingCommandClient()
    let modernClient = JobCommandRefreshModernClient(status: .paused)
    let printer = PrinterSnapshot(
        name: "Desk Printer",
        model: "AD5X",
        address: "192.168.1.44",
        serialNumber: "SN-TEST",
        eventPort: 8898,
        status: .printing,
        nozzleTemperature: TemperatureReading(current: 221),
        bedTemperature: TemperatureReading(current: 58),
        activeJob: PrintJobSnapshot(fileName: "benchy.3mf", progress: 0.4)
    )
    let model = AppModel(
        service: PreviewPrinterService(),
        bootstrapClient: FakeBootstrapClient(),
        modernClient: modernClient,
        commandClient: commandClient,
        printers: [printer]
    )
    model.selection = .printer(printer.id)
    model.checkCode = "123456"

    #expect(model.selectedPrinterJobCommandReadinessMessage(for: .pause) == nil)
    #expect(model.canSendSelectedPrinterJobCommand(.pause) == true)
    #expect(model.selectedJobControlSummary == "Pause and Cancel available.")

    await model.sendSelectedPrinterJobCommand(.pause)

    #expect(commandClient.lastCommand == .pause)
    #expect(commandClient.lastHost == "192.168.1.44")
    #expect(commandClient.lastSerialNumber == "SN-TEST")
    #expect(commandClient.lastCheckCode == "123456")
    #expect(modernClient.requestCount == 1)
    #expect(modernClient.lastHost == "192.168.1.44")
    #expect(modernClient.lastSerialNumber == "SN-TEST")
    #expect(modernClient.lastCheckCode == "123456")
    #expect(model.selectedPrinter?.status == .paused)
    #expect(model.selectedPrinter?.activeJob?.fileName == "benchy.3mf")
    #expect(model.selectedPrinter?.activeJob?.progress == 0.42)
    #expect(model.connectionMessage == "Print paused.")
}

@MainActor
@Test func cancelSelectedPrintClearsActiveJob() async {
    let commandClient = RecordingCommandClient()
    let printer = PrinterSnapshot(
        name: "Desk Printer",
        model: "AD5X",
        address: "192.168.1.44",
        serialNumber: "SN-TEST",
        eventPort: 8898,
        status: .paused,
        nozzleTemperature: TemperatureReading(current: 221),
        bedTemperature: TemperatureReading(current: 58),
        activeJob: PrintJobSnapshot(fileName: "benchy.3mf", progress: 0.4)
    )
    let model = AppModel(
        service: PreviewPrinterService(),
        bootstrapClient: FakeBootstrapClient(),
        commandClient: commandClient,
        printers: [printer]
    )
    model.selection = .printer(printer.id)
    model.checkCode = "123456"

    #expect(model.selectedJobControlSummary == "Resume and Cancel available.")

    await model.sendSelectedPrinterJobCommand(.cancel)

    #expect(commandClient.lastCommand == .cancel)
    #expect(model.selectedPrinter?.status == .ready)
    #expect(model.selectedPrinter?.activeJob == nil)
}

@MainActor
@Test func rejectedJobCommandShowsPrinterReason() async {
    let commandClient = FailingCommandClient(error: ModernPrinterCommandError.rejected("Printer is not printing"))
    let printer = PrinterSnapshot(
        name: "Desk Printer",
        model: "AD5X",
        address: "192.168.1.44",
        serialNumber: "SN-TEST",
        eventPort: 8898,
        status: .printing,
        nozzleTemperature: TemperatureReading(current: 221),
        bedTemperature: TemperatureReading(current: 58),
        activeJob: PrintJobSnapshot(fileName: "benchy.3mf", progress: 0.4)
    )
    let model = AppModel(
        service: PreviewPrinterService(),
        bootstrapClient: FakeBootstrapClient(),
        commandClient: commandClient,
        printers: [printer]
    )
    model.selection = .printer(printer.id)
    model.checkCode = "123456"

    await model.sendSelectedPrinterJobCommand(.pause)

    #expect(model.connectionMessage == "Printer rejected pause: Printer is not printing.")
    #expect(model.isSendingJobCommand == false)
    #expect(model.activeJobCommand == nil)
}

@MainActor
@Test func transportJobCommandFailureSuggestsNetworkCheck() async {
    let commandClient = FailingCommandClient(error: ModernPrinterCommandError.transportFailed)
    let printer = PrinterSnapshot(
        name: "Desk Printer",
        model: "AD5X",
        address: "192.168.1.44",
        serialNumber: "SN-TEST",
        eventPort: 8898,
        status: .paused,
        nozzleTemperature: TemperatureReading(current: 221),
        bedTemperature: TemperatureReading(current: 58),
        activeJob: PrintJobSnapshot(fileName: "benchy.3mf", progress: 0.4)
    )
    let model = AppModel(
        service: PreviewPrinterService(),
        bootstrapClient: FakeBootstrapClient(),
        commandClient: commandClient,
        printers: [printer]
    )
    model.selection = .printer(printer.id)
    model.checkCode = "123456"

    await model.sendSelectedPrinterJobCommand(.resume)

    #expect(model.connectionMessage == "Could not send resume. Check that the printer is online and reachable on the network.")
}

@MainActor
@Test func httpJobCommandFailureShowsStatusAndPrinterReason() async {
    let commandClient = FailingCommandClient(error: ModernPrinterCommandError.httpStatus(409, "Printer is not paused"))
    let printer = PrinterSnapshot(
        name: "Desk Printer",
        model: "AD5X",
        address: "192.168.1.44",
        serialNumber: "SN-TEST",
        eventPort: 8898,
        status: .paused,
        nozzleTemperature: TemperatureReading(current: 221),
        bedTemperature: TemperatureReading(current: 58),
        activeJob: PrintJobSnapshot(fileName: "benchy.3mf", progress: 0.4)
    )
    let model = AppModel(
        service: PreviewPrinterService(),
        bootstrapClient: FakeBootstrapClient(),
        commandClient: commandClient,
        printers: [printer]
    )
    model.selection = .printer(printer.id)
    model.checkCode = "123456"

    await model.sendSelectedPrinterJobCommand(.resume)

    #expect(model.connectionMessage == "Could not send resume. Printer returned HTTP 409: Printer is not paused.")
    #expect(model.isSendingJobCommand == false)
    #expect(model.activeJobCommand == nil)
}

@MainActor
@Test func selectedJobCommandReadinessExplainsMissingCheckCode() async {
    let commandClient = RecordingCommandClient()
    let printer = PrinterSnapshot(
        name: "Desk Printer",
        model: "AD5X",
        address: "192.168.1.44",
        serialNumber: "SN-TEST",
        eventPort: 8898,
        status: .printing,
        nozzleTemperature: TemperatureReading(current: 221),
        bedTemperature: TemperatureReading(current: 58),
        activeJob: PrintJobSnapshot(fileName: "benchy.3mf", progress: 0.4)
    )
    let model = AppModel(
        service: PreviewPrinterService(),
        bootstrapClient: FakeBootstrapClient(),
        commandClient: commandClient,
        printers: [printer]
    )
    model.selection = .printer(printer.id)

    #expect(model.hasSelectedPrinterCheckCode == false)
    #expect(model.selectedPrinterCheckCodeStatusMessage == "Needed for refresh, upload, and job controls.")
    #expect(model.selectedPrinterJobCommandReadinessMessage(for: .pause) == "Enter the printer check code to control this job.")
    #expect(model.canSendSelectedPrinterJobCommand(.pause) == false)

    await model.sendSelectedPrinterJobCommand(.pause)

    #expect(commandClient.lastCommand == nil)
    #expect(model.connectionMessage == "Enter the printer check code to control this job.")
}

@MainActor
@Test func readyPrinterDoesNotSendUnavailableJobCommand() async {
    let commandClient = RecordingCommandClient()
    let printer = PrinterSnapshot(
        name: "Desk Printer",
        model: "AD5X",
        address: "192.168.1.44",
        serialNumber: "SN-TEST",
        eventPort: 8898,
        status: .ready,
        nozzleTemperature: TemperatureReading(current: 30),
        bedTemperature: TemperatureReading(current: 28)
    )
    let model = AppModel(
        service: PreviewPrinterService(),
        bootstrapClient: FakeBootstrapClient(),
        commandClient: commandClient,
        printers: [printer]
    )
    model.selection = .printer(printer.id)
    model.checkCode = "123456"

    #expect(model.selectedPrinterJobCommandReadinessMessage(for: .pause) == "That job action is not available for the selected printer.")
    #expect(model.canSendSelectedPrinterJobCommand(.pause) == false)

    await model.sendSelectedPrinterJobCommand(.pause)

    #expect(commandClient.lastCommand == nil)
    #expect(model.connectionMessage == "That job action is not available for the selected printer.")
}

@MainActor
@Test func uploadSelectedJobSendsModernUploadRequestAndStartsPrint() async throws {
    let uploadClient = RecordingUploadClient()
    let modernClient = JobCommandRefreshModernClient(status: .printing)
    let directoryURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("FlashForgeNativeTests-\(UUID().uuidString)", isDirectory: true)
    let fileURL = directoryURL.appendingPathComponent("benchy.gcode")
    defer {
        try? FileManager.default.removeItem(at: directoryURL)
    }
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    try Data("G1 X1 Y1\n".utf8).write(to: fileURL)
    let printer = PrinterSnapshot(
        name: "Desk Printer",
        model: "AD5X",
        address: "192.168.1.44",
        serialNumber: "SN-TEST",
        eventPort: 8898,
        status: .ready,
        nozzleTemperature: TemperatureReading(current: 30),
        bedTemperature: TemperatureReading(current: 28)
    )
    let model = AppModel(
        service: PreviewPrinterService(),
        bootstrapClient: FakeBootstrapClient(),
        modernClient: modernClient,
        uploadClient: uploadClient,
        printers: [printer]
    )
    model.selection = .printer(printer.id)
    model.checkCode = "123456"
    model.lastModernStatus = ModernPrinterStatus(
        displayName: "Desk Printer",
        firmwareVersion: "3.2.0",
        pid: 38,
        isPro: false,
        isAD5X: true,
        state: .ready,
        nozzleCurrent: 30,
        nozzleTarget: 0,
        bedCurrent: 28,
        bedTarget: 0,
        printFileName: "",
        printProgress: 0,
        estimatedTime: 0,
        printDuration: 0,
        filamentType: "",
        cameraStreamURL: ""
    )
    model.selectUploadFile(fileURL)

    #expect(model.selectedUploadReadinessMessage == nil)
    #expect(model.canUploadSelectedJob == true)

    await model.uploadSelectedJob()

    #expect(uploadClient.lastRequest?.fileURL == fileURL)
    #expect(uploadClient.lastRequest?.startPrint == true)
    #expect(uploadClient.lastRequest?.levelingBeforePrint == true)
    #expect(uploadClient.lastRequest?.firmwareVersion == "3.2.0")
    #expect(uploadClient.lastHost == "192.168.1.44")
    #expect(uploadClient.lastSerialNumber == "SN-TEST")
    #expect(uploadClient.lastCheckCode == "123456")
    #expect(modernClient.requestCount == 1)
    #expect(modernClient.lastHost == "192.168.1.44")
    #expect(modernClient.lastSerialNumber == "SN-TEST")
    #expect(modernClient.lastCheckCode == "123456")
    #expect(model.selectedPrinter?.status == .printing)
    #expect(model.selectedPrinter?.activeJob?.fileName == "benchy.3mf")
    #expect(model.selectedPrinter?.activeJob?.progress == 0.42)
    #expect(model.connectionMessage == "Uploaded and started benchy.gcode.")
}

@MainActor
@Test func uploadOnlyDoesNotRequestBedLeveling() async throws {
    let uploadClient = RecordingUploadClient()
    let directoryURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("FlashForgeNativeTests-\(UUID().uuidString)", isDirectory: true)
    let fileURL = directoryURL.appendingPathComponent("benchy.gcode")
    defer {
        try? FileManager.default.removeItem(at: directoryURL)
    }
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    try Data("G1 X1 Y1\n".utf8).write(to: fileURL)
    let printer = PrinterSnapshot(
        name: "Desk Printer",
        model: "AD5X",
        address: "192.168.1.44",
        serialNumber: "SN-TEST",
        eventPort: 8898,
        status: .ready,
        nozzleTemperature: TemperatureReading(current: 30),
        bedTemperature: TemperatureReading(current: 28)
    )
    let model = AppModel(
        service: PreviewPrinterService(),
        bootstrapClient: FakeBootstrapClient(),
        uploadClient: uploadClient,
        printers: [printer]
    )
    model.selection = .printer(printer.id)
    model.checkCode = "123456"
    model.startPrintAfterUpload = false
    model.levelingBeforePrint = true
    model.selectUploadFile(fileURL)

    await model.uploadSelectedJob()

    #expect(uploadClient.lastRequest?.startPrint == false)
    #expect(uploadClient.lastRequest?.levelingBeforePrint == false)
    #expect(model.connectionMessage == "Uploaded benchy.gcode.")
}

@MainActor
@Test func rejectedUploadShowsPrinterReason() async throws {
    let uploadClient = FailingUploadClient(error: ModernPrinterUploadError.rejected("Check code is invalid"))
    let directoryURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("FlashForgeNativeTests-\(UUID().uuidString)", isDirectory: true)
    let fileURL = directoryURL.appendingPathComponent("benchy.gcode")
    defer {
        try? FileManager.default.removeItem(at: directoryURL)
    }
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    try Data("G1 X1 Y1\n".utf8).write(to: fileURL)
    let printer = PrinterSnapshot(
        name: "Desk Printer",
        model: "AD5X",
        address: "192.168.1.44",
        serialNumber: "SN-TEST",
        eventPort: 8898,
        status: .ready,
        nozzleTemperature: TemperatureReading(current: 30),
        bedTemperature: TemperatureReading(current: 28)
    )
    let model = AppModel(
        service: PreviewPrinterService(),
        bootstrapClient: FakeBootstrapClient(),
        uploadClient: uploadClient,
        printers: [printer]
    )
    model.selection = .printer(printer.id)
    model.checkCode = "123456"
    model.selectUploadFile(fileURL)

    await model.uploadSelectedJob()

    #expect(model.connectionMessage == "Printer rejected the upload: Check code is invalid.")
    #expect(model.isUploadingJob == false)
}

@MainActor
@Test func httpUploadFailureShowsStatusAndPrinterReason() async throws {
    let uploadClient = FailingUploadClient(error: ModernPrinterUploadError.httpStatus(403, "Check code is invalid"))
    let directoryURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("FlashForgeNativeTests-\(UUID().uuidString)", isDirectory: true)
    let fileURL = directoryURL.appendingPathComponent("benchy.gcode")
    defer {
        try? FileManager.default.removeItem(at: directoryURL)
    }
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    try Data("G1 X1 Y1\n".utf8).write(to: fileURL)
    let printer = PrinterSnapshot(
        name: "Desk Printer",
        model: "AD5X",
        address: "192.168.1.44",
        serialNumber: "SN-TEST",
        eventPort: 8898,
        status: .ready,
        nozzleTemperature: TemperatureReading(current: 30),
        bedTemperature: TemperatureReading(current: 28)
    )
    let model = AppModel(
        service: PreviewPrinterService(),
        bootstrapClient: FakeBootstrapClient(),
        uploadClient: uploadClient,
        printers: [printer]
    )
    model.selection = .printer(printer.id)
    model.checkCode = "123456"
    model.selectUploadFile(fileURL)

    await model.uploadSelectedJob()

    #expect(model.connectionMessage == "Upload failed with HTTP 403: Check code is invalid.")
    #expect(model.isUploadingJob == false)
}

@MainActor
@Test func missingUploadFileShowsRecoveryMessage() async {
    let uploadClient = FailingUploadClient(error: ModernPrinterUploadError.fileNotFound)
    let printer = PrinterSnapshot(
        name: "Desk Printer",
        model: "AD5X",
        address: "192.168.1.44",
        serialNumber: "SN-TEST",
        eventPort: 8898,
        status: .ready,
        nozzleTemperature: TemperatureReading(current: 30),
        bedTemperature: TemperatureReading(current: 28)
    )
    let model = AppModel(
        service: PreviewPrinterService(),
        bootstrapClient: FakeBootstrapClient(),
        uploadClient: uploadClient,
        printers: [printer]
    )
    model.selection = .printer(printer.id)
    model.checkCode = "123456"
    model.selectUploadFile(URL(fileURLWithPath: "/tmp/missing.gcode"))

    #expect(model.selectedUploadReadinessMessage == "Choose the job file again.")
    #expect(model.canUploadSelectedJob == false)

    await model.uploadSelectedJob()

    #expect(model.connectionMessage == "Choose the job file again.")
}

@MainActor
@Test func selectedUploadFileDoesNotFollowPrinterSelection() async {
    let firstPrinter = PrinterSnapshot(
        name: "Studio",
        model: "AD5X",
        address: "192.168.1.44",
        serialNumber: "SN-FIRST",
        eventPort: 8898,
        status: .ready,
        nozzleTemperature: TemperatureReading(current: 30),
        bedTemperature: TemperatureReading(current: 28)
    )
    let secondPrinter = PrinterSnapshot(
        name: "Workshop",
        model: "AD5X",
        address: "192.168.1.45",
        serialNumber: "SN-SECOND",
        eventPort: 8898,
        status: .ready,
        nozzleTemperature: TemperatureReading(current: 31),
        bedTemperature: TemperatureReading(current: 29)
    )
    let model = AppModel(
        service: EmptyPrinterService(),
        bootstrapClient: FakeBootstrapClient(),
        printers: [firstPrinter, secondPrinter]
    )
    let firstFileURL = URL(fileURLWithPath: "/tmp/studio.gcode")
    let secondFileURL = URL(fileURLWithPath: "/tmp/workshop.gcode")

    model.selection = .printer(firstPrinter.id)
    model.selectUploadFile(firstFileURL)
    #expect(model.selectedUploadFileURL == firstFileURL)
    #expect(model.selectedUploadFileName == "studio.gcode")
    #expect(model.selectedUploadFileSummary?.fileName == "studio.gcode")
    #expect(model.selectedUploadFileSummary?.location == "/tmp")
    #expect(model.selectedUploadFileSummary?.isSelected == true)
    #expect(model.selectedPendingJobSummary == "studio.gcode selected for upload.")
    #expect(model.selectedUploadActionSummary == "Upload, level the bed, then start printing.")
    #expect(model.canChooseUploadLeveling == true)
    #expect(model.canClearSelectedUploadFile == true)
    #expect(model.selectedUploadReadinessMessage == "Enter the printer check code to upload a job.")
    #expect(model.canUploadSelectedJob == false)

    model.levelingBeforePrint = false
    #expect(model.selectedUploadActionSummary == "Upload, then start printing without bed leveling.")
    #expect(model.canChooseUploadLeveling == true)

    model.startPrintAfterUpload = false
    #expect(model.selectedUploadActionSummary == "Upload only. The print will stay on the printer until you start it.")
    #expect(model.canChooseUploadLeveling == false)

    model.selection = .printer(secondPrinter.id)
    #expect(model.selectedUploadFileURL == nil)
    #expect(model.selectedUploadFileName == "No file selected")
    #expect(model.selectedPendingJobSummary == nil)
    #expect(model.canClearSelectedUploadFile == false)
    #expect(model.selectedUploadReadinessMessage == "Choose a job file first.")
    #expect(model.canUploadSelectedJob == false)

    model.selectUploadFile(secondFileURL)
    model.selection = .printer(firstPrinter.id)
    #expect(model.selectedUploadFileURL == firstFileURL)

    model.clearSelectedUploadFile()
    #expect(model.selectedUploadFileURL == nil)
    #expect(model.selectedUploadFileName == "No file selected")
    #expect(model.selectedUploadFileSummary == nil)
    #expect(model.selectedPendingJobSummary == nil)
    #expect(model.canClearSelectedUploadFile == false)
    #expect(model.selectedUploadReadinessMessage == "Choose a job file first.")
    #expect(model.connectionMessage == "Selected job file cleared.")

    model.selection = .printer(secondPrinter.id)
    #expect(model.selectedUploadFileURL == secondFileURL)
}

@MainActor
@Test func recentUploadFilesAreRememberedPerPrinter() async {
    let firstPrinter = PrinterSnapshot(
        name: "Studio",
        model: "AD5X",
        address: "192.168.1.44",
        serialNumber: "SN-FIRST",
        eventPort: 8898,
        status: .ready,
        nozzleTemperature: TemperatureReading(current: 30),
        bedTemperature: TemperatureReading(current: 28)
    )
    let secondPrinter = PrinterSnapshot(
        name: "Workshop",
        model: "AD5X",
        address: "192.168.1.45",
        serialNumber: "SN-SECOND",
        eventPort: 8898,
        status: .ready,
        nozzleTemperature: TemperatureReading(current: 31),
        bedTemperature: TemperatureReading(current: 29)
    )
    let model = AppModel(
        service: EmptyPrinterService(),
        bootstrapClient: FakeBootstrapClient(),
        printers: [firstPrinter, secondPrinter]
    )
    let firstFileURL = URL(fileURLWithPath: "/tmp/studio.gcode")
    let secondFileURL = URL(fileURLWithPath: "/tmp/plate.3mf")
    let thirdFileURL = URL(fileURLWithPath: "/tmp/workshop.gx")

    model.selection = .printer(firstPrinter.id)
    model.selectUploadFile(firstFileURL)
    model.selectUploadFile(secondFileURL)
    model.selectUploadFile(firstFileURL)
    #expect(model.recentUploadFileURLs == [firstFileURL, secondFileURL])
    #expect(model.recentUploadFileSummaries.map(\.menuTitle) == [
        "studio.gcode - tmp",
        "plate.3mf - tmp"
    ])
    #expect(model.recentUploadFileSummaries.map(\.isSelected) == [true, false])
    #expect(model.canClearRecentUploadFiles == true)

    model.selection = .printer(secondPrinter.id)
    #expect(model.recentUploadFileURLs.isEmpty)
    #expect(model.canClearRecentUploadFiles == false)

    model.selectUploadFile(thirdFileURL)
    #expect(model.recentUploadFileURLs == [thirdFileURL])
    #expect(model.canClearRecentUploadFiles == true)

    model.selection = .printer(firstPrinter.id)
    #expect(model.recentUploadFileURLs == [firstFileURL, secondFileURL])
}

@MainActor
@Test func recentUploadFilesIgnoreUnsupportedSelections() async {
    let printer = PrinterSnapshot(
        name: "Desk Printer",
        model: "AD5X",
        address: "192.168.1.44",
        serialNumber: "SN-TEST",
        eventPort: 8898,
        status: .ready,
        nozzleTemperature: TemperatureReading(current: 30),
        bedTemperature: TemperatureReading(current: 28)
    )
    let model = AppModel(
        service: EmptyPrinterService(),
        bootstrapClient: FakeBootstrapClient(),
        printers: [printer]
    )
    model.selection = .printer(printer.id)

    model.selectUploadFile(URL(fileURLWithPath: "/tmp/notes.txt"))

    #expect(model.recentUploadFileURLs.isEmpty)
}

@MainActor
@Test func recentUploadFilesLoadFromProfilesAndPersistSelections() async {
    let printerID = UUID()
    let savedFileURL = URL(fileURLWithPath: "/tmp/saved.gcode")
    let unsupportedFileURL = URL(fileURLWithPath: "/tmp/notes.txt")
    let newFileURL = URL(fileURLWithPath: "/tmp/new-plate.3mf")
    let store = RecordingProfileStore(
        document: PrinterProfileDocument(
            profiles: [
                PrinterProfile(
                    id: printerID,
                    name: "Desk Printer",
                    model: "AD5X",
                    address: "192.168.1.44",
                    serialNumber: "SN-TEST",
                    eventPort: 8898,
                    protocolFormat: .modern,
                    checkCode: "123456",
                    recentUploadFileURLs: [savedFileURL, unsupportedFileURL, savedFileURL]
                )
            ],
            selectedPrinterID: printerID
        )
    )
    let model = AppModel(
        service: EmptyPrinterService(),
        bootstrapClient: FakeBootstrapClient(),
        profileStore: store
    )

    #expect(model.recentUploadFileURLs == [savedFileURL])
    #expect(model.canClearRecentUploadFiles == true)

    model.selectUploadFile(newFileURL)

    #expect(model.recentUploadFileURLs == [newFileURL, savedFileURL])
    #expect(store.document.profiles.first?.recentUploadFileURLs == [newFileURL, savedFileURL])

    model.clearRecentUploadFiles()

    #expect(model.recentUploadFileURLs.isEmpty)
    #expect(model.canClearRecentUploadFiles == false)
    #expect(store.document.profiles.first?.recentUploadFileURLs == [])
    #expect(model.connectionMessage == "Recent job files cleared.")
}

@MainActor
@Test func openJobFileRequiresSelectedPrinter() async {
    let model = AppModel(service: EmptyPrinterService(), bootstrapClient: FakeBootstrapClient())

    let didOpen = model.openJobFile(URL(fileURLWithPath: "/tmp/benchy.gcode"))

    #expect(didOpen == false)
    #expect(model.canOpenJobFile == false)
    #expect(model.selectedUploadFileURL == nil)
    #expect(model.connectionMessage == "Add or discover a printer before opening a job file.")
}

@MainActor
@Test func openJobFileSelectsOnlyKnownPrinterWhenNoPrinterIsSelected() async {
    let printer = PrinterSnapshot(
        name: "Desk Printer",
        model: "AD5X",
        address: "192.168.1.44",
        serialNumber: "SN-TEST",
        eventPort: 8898,
        status: .ready,
        nozzleTemperature: TemperatureReading(current: 30),
        bedTemperature: TemperatureReading(current: 28)
    )
    let model = AppModel(
        service: PreviewPrinterService(),
        bootstrapClient: FakeBootstrapClient(),
        printers: [printer]
    )
    let fileURL = URL(fileURLWithPath: "/tmp/benchy.gcode")

    #expect(model.canOpenJobFile == true)

    let didOpen = model.openJobFile(fileURL)

    #expect(didOpen == true)
    #expect(model.selection == .printer(printer.id))
    #expect(model.selectedUploadFileURL == fileURL)
    #expect(model.connectionMessage == "benchy.gcode selected.")
}

@MainActor
@Test func openJobFileStillRequiresSelectionWhenSeveralPrintersAreKnown() async {
    let firstPrinter = PrinterSnapshot(
        name: "Studio Printer",
        model: "AD5M",
        address: "192.168.1.44",
        serialNumber: "SN-ONE",
        eventPort: 8898,
        status: .ready,
        nozzleTemperature: TemperatureReading(current: 30),
        bedTemperature: TemperatureReading(current: 28)
    )
    let secondPrinter = PrinterSnapshot(
        name: "Workshop Printer",
        model: "AD5X",
        address: "192.168.1.45",
        serialNumber: "SN-TWO",
        eventPort: 8898,
        status: .ready,
        nozzleTemperature: TemperatureReading(current: 31),
        bedTemperature: TemperatureReading(current: 29)
    )
    let model = AppModel(
        service: PreviewPrinterService(),
        bootstrapClient: FakeBootstrapClient(),
        printers: [firstPrinter, secondPrinter]
    )

    let didOpen = model.openJobFile(URL(fileURLWithPath: "/tmp/benchy.gcode"))

    #expect(didOpen == false)
    #expect(model.canOpenJobFile == true)
    #expect(model.selection == .dashboard)
    #expect(model.selectedUploadFileURL == nil)
    #expect(model.connectionMessage == "Select a printer to use benchy.gcode.")

    model.selection = .printer(secondPrinter.id)

    #expect(model.selectedUploadFileURL == URL(fileURLWithPath: "/tmp/benchy.gcode"))
    #expect(model.selectedUploadFileName == "benchy.gcode")
    #expect(model.recentUploadFileURLs == [URL(fileURLWithPath: "/tmp/benchy.gcode")])
    #expect(model.connectionMessage == "benchy.gcode selected.")
}

@MainActor
@Test func openJobFileRejectsUnsupportedFile() async {
    let printer = PrinterSnapshot(
        name: "Desk Printer",
        model: "AD5X",
        address: "192.168.1.44",
        serialNumber: "SN-TEST",
        eventPort: 8898,
        status: .ready,
        nozzleTemperature: TemperatureReading(current: 30),
        bedTemperature: TemperatureReading(current: 28)
    )
    let model = AppModel(
        service: PreviewPrinterService(),
        bootstrapClient: FakeBootstrapClient(),
        printers: [printer]
    )
    model.selection = .printer(printer.id)

    let didOpen = model.openJobFile(URL(fileURLWithPath: "/tmp/notes.txt"))

    #expect(didOpen == false)
    #expect(model.selectedUploadFileURL == nil)
    #expect(model.connectionMessage == "Choose a .gcode, .gx, or .3mf file.")
}

@MainActor
@Test func openJobFileSelectsSupportedJobForCurrentPrinter() async {
    let printer = PrinterSnapshot(
        name: "Desk Printer",
        model: "AD5X",
        address: "192.168.1.44",
        serialNumber: "SN-TEST",
        eventPort: 8898,
        status: .ready,
        nozzleTemperature: TemperatureReading(current: 30),
        bedTemperature: TemperatureReading(current: 28)
    )
    let model = AppModel(
        service: PreviewPrinterService(),
        bootstrapClient: FakeBootstrapClient(),
        printers: [printer]
    )
    let fileURL = URL(fileURLWithPath: "/tmp/plate.3mf")
    model.selection = .printer(printer.id)

    let didOpen = model.openJobFile(fileURL)

    #expect(didOpen == true)
    #expect(model.selectedUploadFileURL == fileURL)
    #expect(model.selectedUploadFileName == "plate.3mf")
    #expect(model.connectionMessage == "plate.3mf selected.")
}

@MainActor
@Test func unsupportedUploadFileDoesNotSendRequest() async {
    let uploadClient = RecordingUploadClient()
    let printer = PrinterSnapshot(
        name: "Desk Printer",
        model: "AD5X",
        address: "192.168.1.44",
        serialNumber: "SN-TEST",
        eventPort: 8898,
        status: .ready,
        nozzleTemperature: TemperatureReading(current: 30),
        bedTemperature: TemperatureReading(current: 28)
    )
    let model = AppModel(
        service: PreviewPrinterService(),
        bootstrapClient: FakeBootstrapClient(),
        uploadClient: uploadClient,
        printers: [printer]
    )
    model.selection = .printer(printer.id)
    model.checkCode = "123456"
    model.selectUploadFile(URL(fileURLWithPath: "/tmp/notes.txt"))

    #expect(model.selectedUploadReadinessMessage == "Choose a .gcode, .gx, or .3mf file.")
    #expect(model.canUploadSelectedJob == false)

    await model.uploadSelectedJob()

    #expect(uploadClient.lastRequest == nil)
    #expect(model.connectionMessage == "Choose a .gcode, .gx, or .3mf file.")
}

private struct FakeBootstrapClient: PrinterBootstrapClient {
    func fetchPrinterInfo(host: String, port: UInt16) async throws -> PrinterInfo {
        PrinterInfo(
            typeName: "FlashForge Adventurer 5M Pro",
            name: "Desk Printer",
            firmwareVersion: "3.1.2",
            serialNumber: "SN-TEST"
        )
    }
}

private final class RecordingBootstrapClient: PrinterBootstrapClient, @unchecked Sendable {
    var requestedHosts: [String] = []
    var requestedPorts: [UInt16] = []
    let infosByHost: [String: PrinterInfo]
    let failingHosts: Set<String>

    init(
        infosByHost: [String: PrinterInfo],
        failingHosts: Set<String> = []
    ) {
        self.infosByHost = infosByHost
        self.failingHosts = failingHosts
    }

    func fetchPrinterInfo(host: String, port: UInt16) async throws -> PrinterInfo {
        requestedHosts.append(host)
        requestedPorts.append(port)

        if failingHosts.contains(host) {
            throw URLError(.cannotConnectToHost)
        }

        return infosByHost[host] ?? PrinterInfo(
            typeName: "FlashForge Adventurer 5M",
            name: host,
            firmwareVersion: "3.0.0",
            serialNumber: "SN-\(host)"
        )
    }
}

private struct FakeModernClient: ModernPrinterHTTPClient {
    func fetchStatus(host: String, port: UInt16, serialNumber: String, checkCode: String) async throws -> ModernPrinterStatus {
        ModernPrinterStatus(
            displayName: "Desk Printer",
            firmwareVersion: "3.2.0",
            pid: 38,
            isPro: false,
            isAD5X: true,
            state: .printing,
            nozzleCurrent: 221,
            nozzleTarget: 225,
            bedCurrent: 58,
            bedTarget: 60,
            printFileName: "benchy.3mf",
            printProgress: 0.25,
            estimatedTime: 3600,
            printDuration: 1200,
            filamentType: "PLA",
            cameraStreamURL: "rtsp://192.168.1.44/live",
            materialStation: MaterialStationStatus(
                connected: true,
                slots: [
                    MaterialStationSlot(
                        slotId: 1,
                        materialType: "PLA",
                        materialColor: "#ff0000",
                        isEmpty: false
                    )
                ],
                activeSlot: 1,
                overallStatus: .ready
            )
        )
    }
}

private struct FakeModernProNoCameraURLClient: ModernPrinterHTTPClient {
    func fetchStatus(host: String, port: UInt16, serialNumber: String, checkCode: String) async throws -> ModernPrinterStatus {
        ModernPrinterStatus(
            displayName: "Desk Printer",
            firmwareVersion: "3.2.0",
            pid: 36,
            isPro: true,
            isAD5X: false,
            state: .ready,
            nozzleCurrent: 31,
            nozzleTarget: 0,
            bedCurrent: 28,
            bedTarget: 0
        )
    }
}

private final class RecordingModernClient: ModernPrinterHTTPClient, @unchecked Sendable {
    var requestCount = 0
    var requestedHosts: [String] = []
    var lastHost: String?
    var lastPort: UInt16?
    var lastSerialNumber: String?
    var lastCheckCode: String?
    let status: ModernPrinterState

    init(status: ModernPrinterState) {
        self.status = status
    }

    func fetchStatus(host: String, port: UInt16, serialNumber: String, checkCode: String) async throws -> ModernPrinterStatus {
        requestCount += 1
        requestedHosts.append(host)
        lastHost = host
        lastPort = port
        lastSerialNumber = serialNumber
        lastCheckCode = checkCode

        return ModernPrinterStatus(
            displayName: "Desk Printer",
            firmwareVersion: "3.2.0",
            pid: 38,
            isPro: false,
            isAD5X: true,
            state: status,
            nozzleCurrent: 221,
            nozzleTarget: 225,
            bedCurrent: 58,
            bedTarget: 60,
            printFileName: status == .printing ? "benchy.3mf" : "",
            printProgress: status == .printing ? 0.25 : 0,
            estimatedTime: status == .printing ? 3600 : 0,
            printDuration: status == .printing ? 1200 : 0,
            filamentType: "PLA",
            cameraStreamURL: "rtsp://192.168.1.44/live"
        )
    }
}

private final class JobCommandRefreshModernClient: ModernPrinterHTTPClient, @unchecked Sendable {
    var requestCount = 0
    var lastHost: String?
    var lastPort: UInt16?
    var lastSerialNumber: String?
    var lastCheckCode: String?
    let status: ModernPrinterState

    init(status: ModernPrinterState) {
        self.status = status
    }

    func fetchStatus(host: String, port: UInt16, serialNumber: String, checkCode: String) async throws -> ModernPrinterStatus {
        requestCount += 1
        lastHost = host
        lastPort = port
        lastSerialNumber = serialNumber
        lastCheckCode = checkCode

        return ModernPrinterStatus(
            displayName: "Desk Printer",
            firmwareVersion: "3.2.0",
            pid: 38,
            isPro: false,
            isAD5X: true,
            state: status,
            nozzleCurrent: 210,
            nozzleTarget: 220,
            bedCurrent: 55,
            bedTarget: 60,
            printFileName: "benchy.3mf",
            printProgress: 0.42,
            estimatedTime: 2400,
            printDuration: 900,
            filamentType: "PLA",
            cameraStreamURL: "rtsp://192.168.1.44/live"
        )
    }
}

private final class RecordingCommandClient: ModernPrinterCommandClient, @unchecked Sendable {
    var lastCommand: PrinterJobCommand?
    var lastHost: String?
    var lastPort: UInt16?
    var lastSerialNumber: String?
    var lastCheckCode: String?

    func sendJobCommand(
        _ command: PrinterJobCommand,
        host: String,
        port: UInt16,
        serialNumber: String,
        checkCode: String
    ) async throws {
        lastCommand = command
        lastHost = host
        lastPort = port
        lastSerialNumber = serialNumber
        lastCheckCode = checkCode
    }
}

private final class FailingCommandClient: ModernPrinterCommandClient, @unchecked Sendable {
    let error: Error

    init(error: Error) {
        self.error = error
    }

    func sendJobCommand(
        _ command: PrinterJobCommand,
        host: String,
        port: UInt16,
        serialNumber: String,
        checkCode: String
    ) async throws {
        throw error
    }
}

private final class FailingModernClient: ModernPrinterHTTPClient, @unchecked Sendable {
    var requestCount = 0
    let error: Error

    init(error: Error) {
        self.error = error
    }

    func fetchStatus(host: String, port: UInt16, serialNumber: String, checkCode: String) async throws -> ModernPrinterStatus {
        requestCount += 1
        throw error
    }
}

private final class FlakyModernClient: ModernPrinterHTTPClient, @unchecked Sendable {
    var requestCount = 0
    let failuresBeforeSuccess: Int
    let status: ModernPrinterState

    init(failuresBeforeSuccess: Int, status: ModernPrinterState) {
        self.failuresBeforeSuccess = failuresBeforeSuccess
        self.status = status
    }

    func fetchStatus(host: String, port: UInt16, serialNumber: String, checkCode: String) async throws -> ModernPrinterStatus {
        requestCount += 1

        if requestCount <= failuresBeforeSuccess {
            throw URLError(.cannotConnectToHost)
        }

        return ModernPrinterStatus(
            displayName: "Desk Printer",
            firmwareVersion: "3.2.0",
            pid: 38,
            isPro: false,
            isAD5X: true,
            state: status,
            nozzleCurrent: 221,
            nozzleTarget: 225,
            bedCurrent: 58,
            bedTarget: 60,
            printFileName: status == .printing ? "benchy.3mf" : "",
            printProgress: status == .printing ? 0.25 : 0,
            estimatedTime: status == .printing ? 3600 : 0,
            printDuration: status == .printing ? 1200 : 0,
            filamentType: "PLA",
            cameraStreamURL: "rtsp://192.168.1.44/live"
        )
    }
}

private final class RecordingUploadClient: ModernPrinterUploadClient, @unchecked Sendable {
    var lastRequest: PrinterUploadRequest?
    var lastHost: String?
    var lastPort: UInt16?
    var lastSerialNumber: String?
    var lastCheckCode: String?

    func upload(
        _ uploadRequest: PrinterUploadRequest,
        host: String,
        port: UInt16,
        serialNumber: String,
        checkCode: String
    ) async throws {
        lastRequest = uploadRequest
        lastHost = host
        lastPort = port
        lastSerialNumber = serialNumber
        lastCheckCode = checkCode
    }
}

private final class FailingUploadClient: ModernPrinterUploadClient, @unchecked Sendable {
    let error: Error

    init(error: Error) {
        self.error = error
    }

    func upload(
        _ uploadRequest: PrinterUploadRequest,
        host: String,
        port: UInt16,
        serialNumber: String,
        checkCode: String
    ) async throws {
        throw error
    }
}

private struct EmptyPrinterService: PrinterService {
    func discoverPrinters() async throws -> [PrinterSnapshot] {
        []
    }
}

private struct FailingPrinterService: PrinterService {
    func discoverPrinters() async throws -> [PrinterSnapshot] {
        throw URLError(.notConnectedToInternet)
    }
}

private struct SinglePrinterService: PrinterService {
    var printer: PrinterSnapshot

    func discoverPrinters() async throws -> [PrinterSnapshot] {
        [printer]
    }
}

private final class RecordingPrinterService: PrinterService, @unchecked Sendable {
    var requestCount = 0

    func discoverPrinters() async throws -> [PrinterSnapshot] {
        requestCount += 1
        return []
    }
}

private final class RecordingProfileStore: PrinterProfileStore, @unchecked Sendable {
    var document: PrinterProfileDocument

    init(document: PrinterProfileDocument = PrinterProfileDocument()) {
        self.document = document
    }

    func loadDocument() throws -> PrinterProfileDocument {
        document
    }

    func saveDocument(_ document: PrinterProfileDocument) throws {
        self.document = document
    }
}
