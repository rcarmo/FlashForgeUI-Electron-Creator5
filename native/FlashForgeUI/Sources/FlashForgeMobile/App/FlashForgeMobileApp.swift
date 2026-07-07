import FlashForgeNativeKit
import SwiftUI

@main
struct FlashForgeMobileApp: App {
    @State private var showsAddPrinter = false
    @State private var model = AppModel(
        service: NativePrinterDiscoveryService(),
        profileStore: FilePrinterProfileStore.defaultStore()
    )

    var body: some Scene {
        WindowGroup {
            ContentView(model: model, showsAddPrinter: $showsAddPrinter)
        }
    }
}
