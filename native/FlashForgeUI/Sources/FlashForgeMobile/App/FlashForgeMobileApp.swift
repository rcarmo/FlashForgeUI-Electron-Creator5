import FlashForgeNativeKit
import SwiftUI

@main
struct FlashForgeMobileApp: App {
    @State private var model = AppModel(
        service: NativePrinterDiscoveryService(),
        profileStore: FilePrinterProfileStore.defaultStore()
    )

    var body: some Scene {
        WindowGroup {
            MobileContentView(model: model)
        }
    }
}
