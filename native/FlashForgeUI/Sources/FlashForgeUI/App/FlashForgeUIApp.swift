import AppKit
import FlashForgeNativeKit
import SwiftUI
import UniformTypeIdentifiers

@main
struct FlashForgeUIApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var showsAddPrinter = false
    @State private var model = AppModel(
        service: NativePrinterDiscoveryService(),
        profileStore: FilePrinterProfileStore.defaultStore()
    )

    var body: some Scene {
        WindowGroup("FlashForgeUI", id: "main") {
            ContentView(model: model, showsAddPrinter: $showsAddPrinter)
                .frame(minWidth: 900, minHeight: 600)
        }
        .commands {
            SidebarCommands()
            CommandMenu("Printer") {
                Button("Add Printer...") {
                    showsAddPrinter = true
                }
                .keyboardShortcut("n", modifiers: [.command])

                Button("Discover Printers") {
                    Task { await model.discoverPrinters() }
                }
                .keyboardShortcut("r", modifiers: [.command])

                Button("Connect Selected Printer") {
                    Task { await model.connectSelectedPrinter() }
                }
                .keyboardShortcut("k", modifiers: [.command])
                .disabled(!model.canConnectSelectedPrinter)

                Button("Identify All Printers") {
                    Task { await model.connectKnownPrinters() }
                }
                .keyboardShortcut("k", modifiers: [.command, .option])
                .disabled(!model.canConnectKnownPrinters)

                Button("Refresh Status") {
                    Task { await model.refreshSelectedPrinterStatus() }
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(!model.canRefreshSelectedPrinterStatus)

                Button("Refresh All Statuses") {
                    Task { await model.refreshKnownPrinterStatuses() }
                }
                .keyboardShortcut("r", modifiers: [.command, .option])
                .disabled(!model.canRefreshKnownPrinterStatuses)

                Divider()

                Button("Open Camera") {
                    if let streamURL = model.selectedCameraStreamURL {
                        NSWorkspace.shared.open(streamURL)
                        model.acknowledgeCameraOpen()
                    }
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(!model.canOpenSelectedCamera)

                Button("Choose Job File...") {
                    chooseJobFile()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
                .disabled(model.selectedPrinter == nil)

                Button("Upload Selected Job") {
                    Task { await model.uploadSelectedJob() }
                }
                .keyboardShortcut("u", modifiers: [.command])
                .disabled(!model.canUploadSelectedJob)

                Divider()

                Button("Pause Print") {
                    Task { await model.sendSelectedPrinterJobCommand(.pause) }
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .disabled(!model.canSendSelectedPrinterJobCommand(.pause))

                Button("Resume Print") {
                    Task { await model.sendSelectedPrinterJobCommand(.resume) }
                }
                .keyboardShortcut("p", modifiers: [.command, .option])
                .disabled(!model.canSendSelectedPrinterJobCommand(.resume))

                Button("Cancel Print...") {
                    confirmCancelPrint()
                }
                .keyboardShortcut(.delete, modifiers: [.command])
                .disabled(!model.canSendSelectedPrinterJobCommand(.cancel))
            }
        }

        Settings {
            SettingsView(model: model)
        }
    }

    private func chooseJobFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = AppModel.supportedUploadFileExtensions.compactMap {
            UTType(filenameExtension: $0)
        }

        if panel.runModal() == .OK, let fileURL = panel.url {
            model.selectUploadFile(fileURL)
        }
    }

    private func confirmCancelPrint() {
        let alert = NSAlert()
        alert.messageText = "Cancel the current print?"
        alert.informativeText = "This stops the active job on the selected printer."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Cancel Print")
        alert.addButton(withTitle: "Keep Printing")

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        Task { await model.sendSelectedPrinterJobCommand(.cancel) }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
