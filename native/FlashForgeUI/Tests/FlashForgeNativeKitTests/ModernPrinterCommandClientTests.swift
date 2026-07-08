import FlashForgeNativeKit
import Foundation
import Testing

@Test func commandClientReportsHTTPStatusAndPrinterMessage() async throws {
    defer {
        CommandHTTPStatusMockURLProtocol.handler = nil
    }

    CommandHTTPStatusMockURLProtocol.handler = { request in
        #expect(request.url?.absoluteString == "http://192.168.1.44:8898/control")
        #expect(request.httpMethod == "POST")

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 409,
            httpVersion: nil,
            headerFields: nil
        )!
        let body = Data(#"{"code":1,"message":"Printer is not paused"}"#.utf8)
        return (response, body)
    }

    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [CommandHTTPStatusMockURLProtocol.self]
    let client = URLSessionModernPrinterCommandClient(session: URLSession(configuration: configuration))

    do {
        try await client.sendJobCommand(
            .resume,
            host: "192.168.1.44",
            port: 8898,
            serialNumber: "SN-TEST",
            checkCode: "123456"
        )
        Issue.record("Expected command to fail")
    } catch let error as ModernPrinterCommandError {
        #expect(error == .httpStatus(409, "Printer is not paused"))
    }
}

@Test func commandClientReportsUnexpectedSuccessResponse() async throws {
    defer {
        CommandInvalidResponseMockURLProtocol.handler = nil
    }

    CommandInvalidResponseMockURLProtocol.handler = { request in
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (response, Data("not json".utf8))
    }

    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [CommandInvalidResponseMockURLProtocol.self]
    let client = URLSessionModernPrinterCommandClient(session: URLSession(configuration: configuration))

    do {
        try await client.sendJobCommand(
            .pause,
            host: "192.168.1.44",
            port: 8898,
            serialNumber: "SN-TEST",
            checkCode: "123456"
        )
        Issue.record("Expected command to fail")
    } catch let error as ModernPrinterCommandError {
        #expect(error == .invalidResponse)
    }
}

@Test func commandClientReportsTransportFailure() async throws {
    defer {
        CommandTransportFailureMockURLProtocol.handler = nil
    }

    CommandTransportFailureMockURLProtocol.handler = { _ in
        throw URLError(.cannotConnectToHost)
    }

    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [CommandTransportFailureMockURLProtocol.self]
    let client = URLSessionModernPrinterCommandClient(session: URLSession(configuration: configuration))

    do {
        try await client.sendJobCommand(
            .pause,
            host: "192.168.1.44",
            port: 8898,
            serialNumber: "SN-TEST",
            checkCode: "123456"
        )
        Issue.record("Expected command to fail")
    } catch let error as ModernPrinterCommandError {
        #expect(error == .transportFailed)
    }
}

private final class CommandHTTPStatusMockURLProtocol: URLProtocol, @unchecked Sendable {
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

private final class CommandTransportFailureMockURLProtocol: URLProtocol, @unchecked Sendable {
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

private final class CommandInvalidResponseMockURLProtocol: URLProtocol, @unchecked Sendable {
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
