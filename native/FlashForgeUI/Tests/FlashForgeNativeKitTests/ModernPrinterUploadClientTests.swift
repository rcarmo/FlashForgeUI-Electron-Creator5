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

@Test func uploadClientReportsHTTPStatusAndPrinterMessage() async throws {
    let directoryURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("FlashForgeNativeTests-\(UUID().uuidString)", isDirectory: true)
    let fileURL = directoryURL.appendingPathComponent("part.gcode")
    defer {
        try? FileManager.default.removeItem(at: directoryURL)
        UploadMockURLProtocol.handler = nil
    }
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    try Data("G1 X10".utf8).write(to: fileURL)

    UploadMockURLProtocol.handler = { request in
        #expect(request.url?.absoluteString == "http://192.168.1.44:8898/uploadGcode")
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 403,
            httpVersion: nil,
            headerFields: nil
        )!
        let body = Data(#"{"code":1,"message":"Check code is invalid"}"#.utf8)
        return (response, body)
    }

    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [UploadMockURLProtocol.self]
    let client = URLSessionModernPrinterUploadClient(session: URLSession(configuration: configuration))

    do {
        try await client.upload(
            PrinterUploadRequest(fileURL: fileURL, startPrint: true, levelingBeforePrint: true),
            host: "192.168.1.44",
            port: 8898,
            serialNumber: "SN-TEST",
            checkCode: "123456"
        )
        Issue.record("Expected upload to fail")
    } catch let error as ModernPrinterUploadError {
        #expect(error == .httpStatus(403, "Check code is invalid"))
    }
}

@Test func uploadClientReportsTransportFailure() async throws {
    let directoryURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("FlashForgeNativeTests-\(UUID().uuidString)", isDirectory: true)
    let fileURL = directoryURL.appendingPathComponent("part.gcode")
    defer {
        try? FileManager.default.removeItem(at: directoryURL)
        UploadTransportFailureMockURLProtocol.handler = nil
    }
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    try Data("G1 X10".utf8).write(to: fileURL)

    UploadTransportFailureMockURLProtocol.handler = { _ in
        throw URLError(.cannotConnectToHost)
    }

    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [UploadTransportFailureMockURLProtocol.self]
    let client = URLSessionModernPrinterUploadClient(session: URLSession(configuration: configuration))

    do {
        try await client.upload(
            PrinterUploadRequest(fileURL: fileURL, startPrint: true, levelingBeforePrint: true),
            host: "192.168.1.44",
            port: 8898,
            serialNumber: "SN-TEST",
            checkCode: "123456"
        )
        Issue.record("Expected upload to fail")
    } catch let error as ModernPrinterUploadError {
        #expect(error == .transportFailed)
    }
}

private final class UploadMockURLProtocol: URLProtocol, @unchecked Sendable {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private final class UploadTransportFailureMockURLProtocol: URLProtocol, @unchecked Sendable {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
