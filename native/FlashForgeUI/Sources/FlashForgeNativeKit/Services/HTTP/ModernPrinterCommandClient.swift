import Foundation

public enum PrinterJobCommand: String, CaseIterable, Codable, Sendable {
    case pause
    case resume
    case cancel

    var apiAction: String {
        switch self {
        case .pause:
            "pause"
        case .resume:
            "continue"
        case .cancel:
            "cancel"
        }
    }

    public var successMessage: String {
        switch self {
        case .pause:
            "Print paused."
        case .resume:
            "Print resumed."
        case .cancel:
            "Print cancelled."
        }
    }

    public var displayName: String {
        switch self {
        case .pause:
            "Pause"
        case .resume:
            "Resume"
        case .cancel:
            "Cancel"
        }
    }
}

public protocol ModernPrinterCommandClient: Sendable {
    func sendJobCommand(
        _ command: PrinterJobCommand,
        host: String,
        port: UInt16,
        serialNumber: String,
        checkCode: String
    ) async throws
}

public struct URLSessionModernPrinterCommandClient: ModernPrinterCommandClient {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func sendJobCommand(
        _ command: PrinterJobCommand,
        host: String,
        port: UInt16 = 8898,
        serialNumber: String,
        checkCode: String
    ) async throws {
        let url = URL(string: "http://\(host):\(port)/control")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            ModernPrinterControlRequest(
                serialNumber: serialNumber,
                checkCode: checkCode,
                payload: ModernPrinterControlPayload(
                    cmd: "jobCtl_cmd",
                    args: ModernPrinterJobControlArgs(
                        jobID: "",
                        action: command.apiAction
                    )
                )
            )
        )

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ModernPrinterCommandError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw ModernPrinterCommandError.httpStatus(
                httpResponse.statusCode,
                Self.failureMessage(from: data)
            )
        }

        let apiResponse: ModernPrinterControlResponse
        do {
            apiResponse = try JSONDecoder().decode(ModernPrinterControlResponse.self, from: data)
        } catch {
            throw ModernPrinterCommandError.invalidResponse
        }

        guard apiResponse.isSuccess else {
            throw ModernPrinterCommandError.rejected(apiResponse.message)
        }
    }

    private static func failureMessage(from data: Data) -> String? {
        if let apiResponse = try? JSONDecoder().decode(ModernPrinterControlResponse.self, from: data) {
            let trimmedMessage = apiResponse.message.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedMessage.isEmpty {
                return trimmedMessage
            }
        }

        let rawMessage = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !rawMessage.isEmpty else {
            return nil
        }

        if rawMessage.count > 160 {
            return String(rawMessage.prefix(160)) + "..."
        }

        return rawMessage
    }
}

public enum ModernPrinterCommandError: Error, Equatable {
    case transportFailed
    case httpStatus(Int, String?)
    case invalidResponse
    case rejected(String)
}

private struct ModernPrinterControlRequest: Encodable {
    var serialNumber: String
    var checkCode: String
    var payload: ModernPrinterControlPayload
}

private struct ModernPrinterControlPayload: Encodable {
    var cmd: String
    var args: ModernPrinterJobControlArgs
}

private struct ModernPrinterJobControlArgs: Encodable {
    var jobID: String
    var action: String
}

private struct ModernPrinterControlResponse: Decodable {
    var code: Int
    var message: String

    var isSuccess: Bool {
        code == 0 && message.caseInsensitiveCompare("Success") == .orderedSame
    }
}
