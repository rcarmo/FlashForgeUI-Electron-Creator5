import SwiftUI

public struct SettingsView: View {
    @AppStorage("discoverOnLaunch") private var discoverOnLaunch = true
    @AppStorage("statusRefreshIntervalSeconds") private var statusRefreshIntervalSeconds = 15
    @State private var showsForgetPrinterConfirmation = false
    @Bindable private var model: AppModel

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        TabView {
            generalSettings
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            printerSettings
                .tabItem {
                    Label("Printers", systemImage: "printer")
                }
        }
        .settingsViewSizing()
        .scenePadding()
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
    }

    private var generalSettings: some View {
        Form {
            Section {
                Toggle("Discover printers on launch", isOn: $discoverOnLaunch)
                Picker("Status refresh", selection: $statusRefreshIntervalSeconds) {
                    Text("Off").tag(0)
                    Text("Every 15 seconds").tag(15)
                    Text("Every 30 seconds").tag(30)
                    Text("Every minute").tag(60)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var printerSettings: some View {
        Form {
            Section("Selected Printer") {
                Picker("Printer", selection: $model.selection) {
                    Text("Overview")
                        .tag(AppSelection?.some(.dashboard))

                    ForEach(model.printers) { printer in
                        Text(printer.name)
                            .tag(AppSelection?.some(.printer(printer.id)))
                    }
                }

                if let printer = model.selectedPrinter {
                    LabeledContent("Address", value: printer.address)
                    LabeledContent("Model", value: printer.model)

                    Button("Forget Selected Printer", role: .destructive) {
                        showsForgetPrinterConfirmation = true
                    }
                    .disabled(!model.canRemoveSelectedPrinter)

                    if let profileReadinessMessage = model.selectedPrinterProfileChangeReadinessMessage {
                        Label(profileReadinessMessage, systemImage: "info.circle")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Select a printer to edit its profile.")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Add Printer") {
                AddPrinterFormView(model: model, showsFinishButton: false)
                    .frame(minHeight: 220)
            }

            if model.selectedPrinter != nil {
                Section("Connection") {
                    SecureField("Check code", text: $model.checkCode)
                        .textFieldStyle(.roundedBorder)
                        .disabled(model.selectedPrinterProfileChangeReadinessMessage != nil)

                    Button("Forget Check Code") {
                        model.clearSelectedPrinterCheckCode()
                    }
                    .disabled(!model.canClearSelectedPrinterCheckCode)

                    if let checkCodeStatusMessage = model.selectedPrinterCheckCodeStatusMessage {
                        Label(
                            checkCodeStatusMessage,
                            systemImage: model.hasSelectedPrinterCheckCode ? "checkmark.circle" : "info.circle"
                        )
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    }
                }

                Section("Camera") {
                    Toggle("Use custom camera URL", isOn: $model.customCameraEnabled)
                        .disabled(model.selectedPrinterProfileChangeReadinessMessage != nil)

                    TextField("Camera URL", text: $model.customCameraURL)
                        .textFieldStyle(.roundedBorder)
                        .disabled(!model.customCameraEnabled || model.selectedPrinterProfileChangeReadinessMessage != nil)

                    if let validationMessage = customCameraValidationMessage {
                        Label(validationMessage, systemImage: "exclamationmark.triangle")
                            .font(.callout)
                            .foregroundStyle(.orange)
                    }

                    Button("Reset Camera Settings") {
                        model.resetSelectedCameraSettings()
                    }
                    .disabled(!model.canResetSelectedCameraSettings)

                    LabeledContent("Resolved stream") {
                        Text(resolvedCameraDescription)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var resolvedCameraDescription: String {
        let config = model.selectedCameraStreamConfig
        if let streamURL = config.streamURL {
            return streamURL.absoluteString
        }
        return config.unavailableReason ?? "Unavailable"
    }

    private var customCameraValidationMessage: String? {
        let config = model.selectedCameraStreamConfig
        guard model.customCameraEnabled,
              config.sourceType == .custom,
              !config.isAvailable else {
            return nil
        }
        return config.unavailableReason
    }

}

private extension View {
    @ViewBuilder
    func settingsViewSizing() -> some View {
        #if os(macOS)
        self.frame(width: 560, height: 460)
        #else
        self
        #endif
    }
}
