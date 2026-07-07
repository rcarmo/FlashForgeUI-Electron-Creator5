import FlashForgeNativeKit
import Foundation
import Testing

@Test func jobFileMenuTitleIncludesParentFolder() {
    let fileURL = URL(fileURLWithPath: "/Users/flashforge/Models/benchy.gcode")

    #expect(NativeFormatters.jobFileMenuTitle(fileURL) == "benchy.gcode - Models")
}

@Test func jobFileLocationShowsContainingFolderPath() {
    let fileURL = URL(fileURLWithPath: "/Users/flashforge/Models/plate.3mf")

    #expect(NativeFormatters.jobFileLocation(fileURL) == "/Users/flashforge/Models")
}
