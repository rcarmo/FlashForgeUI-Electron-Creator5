import SwiftUI

public struct ContentView: View {
    #if os(macOS)
    @Environment(\.openSettings) private var openSettings
    #endif
    @AppStorage("discoverOnLaunch") private var discoverOnLaunch = true
    @State private var showsSettings = false
    @Binding private var showsAddPrinter: Bool
    @Bindable private var model: AppModel

    public init(model: AppModel, showsAddPrinter: Binding<Bool>) {
        self.model = model
        self._showsAddPrinter = showsAddPrinter
    }

    public var body: some View {
        NavigationSplitView {
            SidebarView(model: model) {
                showsAddPrinter = true
            } onShowSettings: {
                showSettings()
            }
        } detail: {
            DetailView(model: model) {
                showsAddPrinter = true
            } onShowSettings: {
                showSettings()
            }
        }
        .task {
            await model.start(discoverOnLaunch: discoverOnLaunch)
        }
        .sheet(isPresented: $showsAddPrinter) {
            AddPrinterSheetView(model: model)
        }
        .sheet(isPresented: $showsSettings) {
            SettingsSheetView(model: model)
        }
        .onOpenURL { fileURL in
            model.openJobFile(fileURL)
        }
    }

    private func showSettings() {
        #if os(macOS)
        openSettings()
        #else
        showsSettings = true
        #endif
    }
}

private struct AddPrinterSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable private var model: AppModel

    init(model: AppModel) {
        self.model = model
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Printer")
                .font(.title2.weight(.semibold))

            AddPrinterFormView(model: model) {
                dismiss()
            }
        }
        .padding(20)
        .addPrinterSheetSizing()
    }
}

private struct SettingsSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable private var model: AppModel

    init(model: AppModel) {
        self.model = model
    }

    var body: some View {
        NavigationStack {
            SettingsView(model: model)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") {
                            dismiss()
                        }
                    }
                }
        }
    }
}

private extension View {
    @ViewBuilder
    func addPrinterSheetSizing() -> some View {
        #if os(macOS)
        self.frame(minWidth: 420, maxWidth: 420, minHeight: 300)
        #else
        self
        #endif
    }
}
