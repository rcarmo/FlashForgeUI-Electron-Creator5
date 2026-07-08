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
            CommandGroup(after: .newItem) {
                Button("Open Job File...") {
                    chooseJobFile()
                }
                .keyboardShortcut("o", modifiers: [.command])
                .disabled(!model.canOpenJobFile)
            }

            CommandMenu("Printer") {
                Button("Add Printer...") {
                    showsAddPrinter = true
                }
                .keyboardShortcut("n", modifiers: [.command])

                Button("Forget Selected Printer...") {
                    confirmForgetSelectedPrinter()
                }
                .disabled(!model.canRemoveSelectedPrinter)

                Divider()

                Button("Discover Printers") {
                    Task { await model.discoverPrinters() }
                }
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(!model.canDiscoverPrinters)

                Button("Connect Selected Printer") {
                    Task { await model.connectSelectedPrinter() }
                }
                .keyboardShortcut("k", modifiers: [.command])
                .disabled(!model.canConnectSelectedPrinter)

                Button("Forget Saved Check Code") {
                    model.clearSelectedPrinterCheckCode()
                }
                .disabled(!model.canClearSelectedPrinterCheckCode)

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

                Button("Reset Camera Settings") {
                    model.resetSelectedCameraSettings()
                }
                .disabled(!model.canResetSelectedCameraSettings)

                Button("Choose Job File...") {
                    chooseJobFile()
                }
                .disabled(!model.canOpenJobFile)

                Menu("Recent Job Files") {
                    if model.recentUploadFileSummaries.isEmpty {
                        Text("No Recent Job Files")
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
                    }
                }
                .disabled(!model.canChangeSelectedUploadFile || model.recentUploadFileSummaries.isEmpty)

                Button("Clear Job File") {
                    model.clearSelectedUploadFile()
                }
                .disabled(!model.canClearSelectedUploadFile)

                Button("Clear Recent Job Files") {
                    model.clearRecentUploadFiles()
                }
                .disabled(!model.canClearRecentUploadFiles)

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
            model.openJobFile(fileURL)
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

    private func confirmForgetSelectedPrinter() {
        let alert = NSAlert()
        alert.messageText = model.selectedPrinterRemovalConfirmationTitle
        alert.informativeText = model.selectedPrinterRemovalConfirmationMessage
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Forget Printer")
        alert.addButton(withTitle: "Keep Printer")

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        model.removeSelectedPrinter()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
