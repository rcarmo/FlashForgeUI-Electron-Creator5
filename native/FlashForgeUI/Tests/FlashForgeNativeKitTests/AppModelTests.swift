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
    #expect(model.customCameraEnabled == true)
    #expect(model.customCameraURL == "http://camera.local:8080/?action=stream")
    #expect(model.selectedCameraStreamConfig.sourceType == .custom)
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

    await model.connectSelectedPrinter()

    #expect(model.lastPrinterInfo?.typeName == "FlashForge Adventurer 5M Pro")
    #expect(model.connectionMessage == "Desk Printer reports FlashForge Adventurer 5M Pro.")
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
    #expect(model.connectionMessage == "Identified 1 printer.")
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

    await model.refreshSelectedPrinterStatus()

    #expect(model.selectedPrinter?.model == "AD5X")
    #expect(model.selectedPrinter?.status == .printing)
    #expect(model.selectedPrinter?.nozzleTemperature.current == 221)
    #expect(model.selectedPrinter?.activeJob?.fileName == "benchy.3mf")
    #expect(model.selectedPrinter?.materialStation?.activeSlot == 1)
    #expect(model.selectedPrinter?.materialStation?.slots.first?.materialType == "PLA")
    #expect(model.selectedCameraStreamConfig.sourceType == .oem)
    #expect(model.selectedCameraStreamConfig.streamURL?.absoluteString == "rtsp://192.168.1.44/live")
    #expect(model.connectionMessage == "Desk Printer status is Printing.")
    #expect(model.isRefreshingStatus == false)
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

    #expect(model.connectionMessage == "Camera stream ready: http://192.168.1.44:8080/?action=stream")
}

@MainActor
@Test func selectedJobCommandReadinessExplainsMissingSelection() async {
    let model = AppModel(service: EmptyPrinterService(), bootstrapClient: FakeBootstrapClient())

    #expect(model.selectedPrinterJobCommandReadinessMessage(for: .pause) == "Select a printer first.")
    #expect(model.canSendSelectedPrinterJobCommand(.pause) == false)

    await model.sendSelectedPrinterJobCommand(.pause)

    #expect(model.connectionMessage == "Select a printer first.")
}

@MainActor
@Test func pauseSelectedPrintSendsModernCommandAndUpdatesState() async {
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
    model.checkCode = "123456"

    #expect(model.selectedPrinterJobCommandReadinessMessage(for: .pause) == nil)
    #expect(model.canSendSelectedPrinterJobCommand(.pause) == true)

    await model.sendSelectedPrinterJobCommand(.pause)

    #expect(commandClient.lastCommand == .pause)
    #expect(commandClient.lastHost == "192.168.1.44")
    #expect(commandClient.lastSerialNumber == "SN-TEST")
    #expect(commandClient.lastCheckCode == "123456")
    #expect(model.selectedPrinter?.status == .paused)
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
    #expect(model.selectedPrinter?.status == .printing)
    #expect(model.selectedPrinter?.activeJob?.fileName == "benchy.gcode")
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
    #expect(model.selectedUploadReadinessMessage == "Enter the printer check code to upload a job.")
    #expect(model.canUploadSelectedJob == false)

    model.selection = .printer(secondPrinter.id)
    #expect(model.selectedUploadFileURL == nil)
    #expect(model.selectedUploadFileName == "No file selected")
    #expect(model.selectedUploadReadinessMessage == "Choose a job file first.")
    #expect(model.canUploadSelectedJob == false)

    model.selectUploadFile(secondFileURL)
    model.selection = .printer(firstPrinter.id)
    #expect(model.selectedUploadFileURL == firstFileURL)

    model.clearSelectedUploadFile()
    #expect(model.selectedUploadFileURL == nil)
    #expect(model.selectedUploadFileName == "No file selected")
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

    model.selection = .printer(secondPrinter.id)
    #expect(model.recentUploadFileURLs.isEmpty)

    model.selectUploadFile(thirdFileURL)
    #expect(model.recentUploadFileURLs == [thirdFileURL])

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

    model.selectUploadFile(newFileURL)

    #expect(model.recentUploadFileURLs == [newFileURL, savedFileURL])
    #expect(store.document.profiles.first?.recentUploadFileURLs == [newFileURL, savedFileURL])

    model.clearRecentUploadFiles()

    #expect(model.recentUploadFileURLs.isEmpty)
    #expect(store.document.profiles.first?.recentUploadFileURLs == [])
    #expect(model.connectionMessage == "Recent job files cleared.")
}

@MainActor
@Test func openJobFileRequiresSelectedPrinter() async {
    let model = AppModel(service: EmptyPrinterService(), bootstrapClient: FakeBootstrapClient())

    let didOpen = model.openJobFile(URL(fileURLWithPath: "/tmp/benchy.gcode"))

    #expect(didOpen == false)
    #expect(model.selectedUploadFileURL == nil)
    #expect(model.connectionMessage == "Select a printer first.")
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
    #expect(model.selection == .dashboard)
    #expect(model.selectedUploadFileURL == nil)
    #expect(model.connectionMessage == "Select a printer first.")
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
