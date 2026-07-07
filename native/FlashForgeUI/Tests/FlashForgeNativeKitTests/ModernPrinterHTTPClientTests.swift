import FlashForgeNativeKit
import Foundation
import Testing

@Test func statusClientReportsHTTPStatusAndPrinterMessage() async throws {
    defer {
        DetailHTTPStatusMockURLProtocol.handler = nil
    }

    DetailHTTPStatusMockURLProtocol.handler = { request in
        #expect(request.url?.absoluteString == "http://192.168.1.44:8898/detail")
        #expect(request.httpMethod == "POST")

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
    configuration.protocolClasses = [DetailHTTPStatusMockURLProtocol.self]
    let client = URLSessionModernPrinterHTTPClient(session: URLSession(configuration: configuration))

    do {
        _ = try await client.fetchStatus(
            host: "192.168.1.44",
            port: 8898,
            serialNumber: "SN-TEST",
            checkCode: "123456"
        )
        Issue.record("Expected status refresh to fail")
    } catch let error as ModernPrinterHTTPError {
        #expect(error == .httpStatus(403, "Check code is invalid"))
    }
}

@Test func statusClientReportsPrinterRejectionMessage() async throws {
    defer {
        DetailRejectedMockURLProtocol.handler = nil
    }

    DetailRejectedMockURLProtocol.handler = { request in
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        let body = Data(#"{"code":1,"message":"Check code is invalid"}"#.utf8)
        return (response, body)
    }

    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [DetailRejectedMockURLProtocol.self]
    let client = URLSessionModernPrinterHTTPClient(session: URLSession(configuration: configuration))

    do {
        _ = try await client.fetchStatus(
            host: "192.168.1.44",
            port: 8898,
            serialNumber: "SN-TEST",
            checkCode: "123456"
        )
        Issue.record("Expected status refresh to fail")
    } catch let error as ModernPrinterHTTPError {
        #expect(error == .printerRejectedRequest("Check code is invalid"))
    }
}

private final class DetailHTTPStatusMockURLProtocol: URLProtocol, @unchecked Sendable {
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

private final class DetailRejectedMockURLProtocol: URLProtocol, @unchecked Sendable {
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
