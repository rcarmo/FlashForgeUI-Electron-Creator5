import FlashForgeNativeKit
import Foundation
import Testing

@Test func uploadBodyMatchesFlashForgeMultipartShape() throws {
    let body = try ModernPrinterUploadBody(
        fileURL: URL(fileURLWithPath: "/tmp/part.gcode"),
        fileData: Data("G1 X10".utf8),
        startPrint: true,
        levelingBeforePrint: false,
        firmwareVersion: "3.1.2",
        serialNumber: "SN-TEST",
        checkCode: "123456",
        boundary: "Boundary"
    )
    let bodyText = String(decoding: body.body, as: UTF8.self)

    #expect(body.headers["serialNumber"] == "SN-TEST")
    #expect(body.headers["checkCode"] == "123456")
    #expect(body.headers["fileSize"] == "6")
    #expect(body.headers["printNow"] == "true")
    #expect(body.headers["levelingBeforePrint"] == "false")
    #expect(body.headers["Expect"] == "100-continue")
    #expect(body.headers["Content-Type"] == "multipart/form-data; boundary=Boundary")
    #expect(body.headers["materialMappings"] == nil)
    #expect(bodyText.contains("name=\"gcodeFile\"; filename=\"part.gcode\""))
    #expect(bodyText.contains("Content-Type: application/octet-stream"))
    #expect(bodyText.contains("G1 X10"))
}

@Test func uploadBodyAddsNewFirmwareHeaders() throws {
    let body = try ModernPrinterUploadBody(
        fileURL: URL(fileURLWithPath: "/tmp/part.3mf"),
        fileData: Data("PK".utf8),
        startPrint: false,
        levelingBeforePrint: true,
        firmwareVersion: "3.1.3",
        serialNumber: "SN-TEST",
        checkCode: "123456",
        boundary: "Boundary"
    )

    #expect(body.headers["flowCalibration"] == "false")
    #expect(body.headers["useMatlStation"] == "false")
    #expect(body.headers["gcodeToolCnt"] == "0")
    #expect(body.headers["materialMappings"] == "W10=")
}

@Test func firmwareVersionComparisonMatchesFFAPIThreshold() {
    #expect(ModernPrinterUploadBody.isNewFirmwareVersion(nil) == false)
    #expect(ModernPrinterUploadBody.isNewFirmwareVersion("3.1.2") == false)
    #expect(ModernPrinterUploadBody.isNewFirmwareVersion("3.1.3") == true)
    #expect(ModernPrinterUploadBody.isNewFirmwareVersion("3.2.0") == true)
    #expect(ModernPrinterUploadBody.isNewFirmwareVersion("4.0.0") == true)
}
