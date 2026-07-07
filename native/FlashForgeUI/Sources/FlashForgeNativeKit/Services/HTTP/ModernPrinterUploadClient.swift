import Foundation

public struct PrinterUploadRequest: Equatable, Sendable {
    public var fileURL: URL
    public var startPrint: Bool
    public var levelingBeforePrint: Bool
    public var firmwareVersion: String?

    public init(
        fileURL: URL,
        startPrint: Bool,
        levelingBeforePrint: Bool,
        firmwareVersion: String? = nil
    ) {
        self.fileURL = fileURL
        self.startPrint = startPrint
        self.levelingBeforePrint = levelingBeforePrint
        self.firmwareVersion = firmwareVersion
    }
}

public protocol ModernPrinterUploadClient: Sendable {
    func upload(
        _ uploadRequest: PrinterUploadRequest,
        host: String,
        port: UInt16,
        serialNumber: String,
        checkCode: String
    ) async throws
}

public struct URLSessionModernPrinterUploadClient: ModernPrinterUploadClient {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func upload(
        _ uploadRequest: PrinterUploadRequest,
        host: String,
        port: UInt16 = 8898,
        serialNumber: String,
        checkCode: String
    ) async throws {
        guard FileManager.default.fileExists(atPath: uploadRequest.fileURL.path) else {
            throw ModernPrinterUploadError.fileNotFound
        }

        let fileData = try Data(contentsOf: uploadRequest.fileURL)
        let requestBody = try ModernPrinterUploadBody(
            fileURL: uploadRequest.fileURL,
            fileData: fileData,
            startPrint: uploadRequest.startPrint,
            levelingBeforePrint: uploadRequest.levelingBeforePrint,
            firmwareVersion: uploadRequest.firmwareVersion,
            serialNumber: serialNumber,
            checkCode: checkCode
        )

        let url = URL(string: "http://\(host):\(port)/uploadGcode")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = requestBody.body
        requestBody.headers.forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ModernPrinterUploadError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw ModernPrinterUploadError.httpStatus(
                httpResponse.statusCode,
                Self.failureMessage(from: data)
            )
        }

        let apiResponse: ModernPrinterUploadResponse
        do {
            apiResponse = try JSONDecoder().decode(ModernPrinterUploadResponse.self, from: data)
        } catch {
            throw ModernPrinterUploadError.invalidResponse
        }

        guard apiResponse.isSuccess else {
            throw ModernPrinterUploadError.rejected(apiResponse.message)
        }
    }

    private static func failureMessage(from data: Data) -> String? {
        if let apiResponse = try? JSONDecoder().decode(ModernPrinterUploadResponse.self, from: data) {
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

public struct ModernPrinterUploadBody: Sendable {
    public var headers: [String: String]
    public var body: Data

    public init(
        fileURL: URL,
        fileData: Data,
        startPrint: Bool,
        levelingBeforePrint: Bool,
        firmwareVersion: String?,
        serialNumber: String,
        checkCode: String,
        boundary: String = "FlashForgeNativeBoundary-\(UUID().uuidString)"
    ) throws {
        let fileName = fileURL.lastPathComponent
        guard !fileName.isEmpty else {
            throw ModernPrinterUploadError.invalidFileName
        }

        var body = Data()
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"gcodeFile\"; filename=\"\(fileName)\"\r\n")
        body.append("Content-Type: application/octet-stream\r\n\r\n")
        body.append(fileData)
        body.append("\r\n--\(boundary)--\r\n")

        var headers = [
            "serialNumber": serialNumber,
            "checkCode": checkCode,
            "fileSize": "\(fileData.count)",
            "printNow": startPrint.wireValue,
            "levelingBeforePrint": levelingBeforePrint.wireValue,
            "Expect": "100-continue",
            "Content-Type": "multipart/form-data; boundary=\(boundary)"
        ]

        if Self.isNewFirmwareVersion(firmwareVersion) {
            headers["flowCalibration"] = "false"
            headers["useMatlStation"] = "false"
            headers["gcodeToolCnt"] = "0"
            headers["materialMappings"] = "W10="
        }

        self.headers = headers
        self.body = body
    }

    public static func isNewFirmwareVersion(_ firmwareVersion: String?) -> Bool {
        guard let firmwareVersion else {
            return false
        }

        let currentVersion = firmwareVersion
            .split(separator: ".")
            .prefix(3)
            .map { Int($0) ?? 0 }
        let minimumVersion = [3, 1, 3]

        for index in 0..<minimumVersion.count {
            let current = index < currentVersion.count ? currentVersion[index] : 0
            if current > minimumVersion[index] {
                return true
            }
            if current < minimumVersion[index] {
                return false
            }
        }

        return true
    }
}

public enum ModernPrinterUploadError: Error, Equatable {
    case fileNotFound
    case invalidFileName
    case transportFailed
    case httpStatus(Int, String?)
    case invalidResponse
    case rejected(String)
}

private struct ModernPrinterUploadResponse: Decodable {
    var code: Int
    var message: String

    var isSuccess: Bool {
        code == 0 && message.caseInsensitiveCompare("Success") == .orderedSame
    }
}

private extension Bool {
    var wireValue: String {
        self ? "true" : "false"
    }
}

private extension Data {
    mutating func append(_ string: String) {
        append(Data(string.utf8))
    }
}
