import Foundation
import Network

public enum TCPPrinterBootstrapError: Error, Sendable {
    case invalidPort
    case connectionFailed
    case timedOut
    case emptyResponse
    case invalidPrinterInfo
}

public final class TCPPrinterBootstrapClient: PrinterBootstrapClient {
    private let parser: PrinterInfoParser
    private let timeout: TimeInterval

    public init(parser: PrinterInfoParser = PrinterInfoParser(), timeout: TimeInterval = 5) {
        self.parser = parser
        self.timeout = timeout
    }

    public func fetchPrinterInfo(host: String, port: UInt16) async throws -> PrinterInfo {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw TCPPrinterBootstrapError.invalidPort
        }

        let response = try await sendCommand(host: host, port: nwPort, command: "~M115\n")
        guard let info = parser.parse(response) else {
            throw TCPPrinterBootstrapError.invalidPrinterInfo
        }
        return info
    }

    private func sendCommand(host: String, port: NWEndpoint.Port, command: String) async throws -> String {
        let connection = NWConnection(host: NWEndpoint.Host(host), port: port, using: .tcp)
        let queue = DispatchQueue(label: "FlashForgeNative.TCPPrinterBootstrapClient")

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let state = ConnectionState(continuation: continuation, connection: connection, parser: parser)
                let timeoutWorkItem = DispatchWorkItem {
                    state.finish(.failure(TCPPrinterBootstrapError.timedOut))
                }

                connection.stateUpdateHandler = { newState in
                    switch newState {
                    case .ready:
                        timeoutWorkItem.cancel()
                        self.send(command: command, on: connection, state: state)
                    case .failed:
                        timeoutWorkItem.cancel()
                        state.finish(.failure(TCPPrinterBootstrapError.connectionFailed))
                    case .cancelled:
                        timeoutWorkItem.cancel()
                    default:
                        break
                    }
                }

                queue.asyncAfter(deadline: .now() + timeout, execute: timeoutWorkItem)
                connection.start(queue: queue)
            }
        } onCancel: {
            connection.cancel()
        }
    }

    private func send(command: String, on connection: NWConnection, state: ConnectionState) {
        let data = Data(command.utf8)
        connection.send(content: data, completion: .contentProcessed { error in
            if error != nil {
                state.finish(.failure(TCPPrinterBootstrapError.connectionFailed))
                return
            }
            self.receive(on: connection, state: state)
        })
    }

    private func receive(on connection: NWConnection, state: ConnectionState) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, isComplete, error in
            if error != nil {
                state.finish(.failure(TCPPrinterBootstrapError.connectionFailed))
                return
            }

            if let data, !data.isEmpty {
                state.append(data)
                if state.responseContainsTerminator {
                    state.finish(.success(state.responseText))
                    return
                }
            }

            if isComplete {
                if state.responseText.isEmpty {
                    state.finish(.failure(TCPPrinterBootstrapError.emptyResponse))
                } else {
                    state.finish(.success(state.responseText))
                }
                return
            }

            self.receive(on: connection, state: state)
        }
    }
}

private final class ConnectionState: @unchecked Sendable {
    private let lock = NSLock()
    private var completed = false
    private var response = Data()
    private let continuation: CheckedContinuation<String, Error>
    private let connection: NWConnection
    private let parser: PrinterInfoParser

    init(continuation: CheckedContinuation<String, Error>, connection: NWConnection, parser: PrinterInfoParser) {
        self.continuation = continuation
        self.connection = connection
        self.parser = parser
    }

    var responseText: String {
        lock.lock()
        defer { lock.unlock() }
        return String(data: response, encoding: .utf8) ?? ""
    }

    var responseContainsTerminator: Bool {
        responseText.contains("ok")
    }

    func append(_ data: Data) {
        lock.lock()
        response.append(data)
        lock.unlock()
    }

    func finish(_ result: Result<String, Error>) {
        lock.lock()
        guard !completed else {
            lock.unlock()
            return
        }
        completed = true
        lock.unlock()

        connection.cancel()

        switch result {
        case .success(let value):
            continuation.resume(returning: value)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }
}
