import SwiftUI

public struct AddPrinterFormView: View {
    @State private var printerName = ""
    @State private var printerAddress = ""
    @State private var checkCode = ""
    @State private var validationMessage: String?
    @Bindable private var model: AppModel
    private let finishTitle: String
    private let onFinish: () -> Void

    public init(
        model: AppModel,
        finishTitle: String = "Done",
        onFinish: @escaping () -> Void = {}
    ) {
        self.model = model
        self.finishTitle = finishTitle
        self.onFinish = onFinish
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Name", text: $printerName)
                .textFieldStyle(.roundedBorder)

            VStack(alignment: .leading, spacing: 4) {
                TextField("Address or URL", text: $printerAddress)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: printerAddress) {
                        validationMessage = model.manualPrinterAddressValidationMessage(for: printerAddress)
                    }

                if let validationMessage {
                    Text(validationMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                } else if let addressPreview = model.manualPrinterAddressPreview(for: printerAddress) {
                    Text(addressPreview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                SecureField("Check code", text: $checkCode)
                    .textFieldStyle(.roundedBorder)

                Text(AppModel.manualPrinterCheckCodeHelpMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Add Printer") {
                    addPrinter(clearOnSuccess: true)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSubmitPrinter)

                Spacer()

                Button(finishTitle) {
                    if printerAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        onFinish()
                    } else {
                        addPrinter(clearOnSuccess: false)
                    }
                }
                .disabled(!canSubmitPrinter && !trimmedAddress.isEmpty)
            }
        }
        .padding(.vertical, 4)
    }

    private var trimmedAddress: String {
        printerAddress.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmitPrinter: Bool {
        model.canSubmitManualPrinterAddress(printerAddress)
    }

    private func addPrinter(clearOnSuccess: Bool) {
        let didAdd = model.addManualPrinter(
            name: printerName,
            address: printerAddress,
            checkCode: checkCode
        )

        if didAdd {
            validationMessage = nil
            if clearOnSuccess {
                printerName = ""
                printerAddress = ""
                checkCode = ""
            } else {
                onFinish()
            }
        } else {
            validationMessage = model.connectionMessage ?? "Enter the printer address."
        }
    }
}
