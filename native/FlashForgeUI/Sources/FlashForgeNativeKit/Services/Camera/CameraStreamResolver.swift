import Foundation

public enum CameraStreamType: String, Codable, Sendable {
    case mjpeg
    case rtsp
}

public enum CameraSourceType: String, Codable, Sendable {
    case custom
    case oem
    case intelligentFallback
    case none
}

public struct CameraUserConfig: Codable, Equatable, Sendable {
    public var customCameraEnabled: Bool
    public var customCameraURL: String?

    public init(customCameraEnabled: Bool = false, customCameraURL: String? = nil) {
        self.customCameraEnabled = customCameraEnabled
        self.customCameraURL = customCameraURL
    }
}

public struct CameraFeatureConfig: Equatable, Sendable {
    public var oemStreamURL: String
    public var fallbackStreamURL: String

    public init(oemStreamURL: String = "", fallbackStreamURL: String = "") {
        self.oemStreamURL = oemStreamURL
        self.fallbackStreamURL = fallbackStreamURL
    }
}

public struct CameraStreamConfig: Equatable, Sendable {
    public var sourceType: CameraSourceType
    public var streamType: CameraStreamType?
    public var streamURL: URL?
    public var isAvailable: Bool
    public var unavailableReason: String?

    public init(
        sourceType: CameraSourceType,
        streamType: CameraStreamType? = nil,
        streamURL: URL? = nil,
        isAvailable: Bool,
        unavailableReason: String? = nil
    ) {
        self.sourceType = sourceType
        self.streamType = streamType
        self.streamURL = streamURL
        self.isAvailable = isAvailable
        self.unavailableReason = unavailableReason
    }
}

public enum CameraStreamValidationError: Error, Equatable, CustomStringConvertible, Sendable {
    case empty
    case invalidFormat
    case unsupportedProtocol
    case invalidHostname

    public var description: String {
        switch self {
        case .empty:
            "URL is empty or not provided"
        case .invalidFormat:
            "Invalid URL format"
        case .unsupportedProtocol:
            "Unsupported protocol. Use http://, https://, or rtsp://"
        case .invalidHostname:
            "Invalid hostname in URL"
        }
    }
}

public enum CameraStreamResolver {
    public static func flashForgeMJPEGURL(ipAddress: String) -> String {
        "http://\(ipAddress):8080/?action=stream"
    }

    public static func resolve(
        userConfig: CameraUserConfig,
        cameraFeatures: CameraFeatureConfig
    ) -> CameraStreamConfig {
        if userConfig.customCameraEnabled {
            let normalizedURL = userConfig.customCameraURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            switch validateCameraURL(normalizedURL) {
            case .success(let url):
                return CameraStreamConfig(
                    sourceType: .custom,
                    streamType: detectStreamType(url),
                    streamURL: url,
                    isAvailable: true
                )
            case .failure(let error):
                return CameraStreamConfig(
                    sourceType: .custom,
                    isAvailable: false,
                    unavailableReason: "Custom camera URL is invalid: \(error.description)"
                )
            }
        }

        if let oemURL = validTrimmedURL(cameraFeatures.oemStreamURL) {
            return CameraStreamConfig(
                sourceType: .oem,
                streamType: detectStreamType(oemURL),
                streamURL: oemURL,
                isAvailable: true
            )
        }

        if let fallbackURL = validTrimmedURL(cameraFeatures.fallbackStreamURL) {
            return CameraStreamConfig(
                sourceType: .intelligentFallback,
                streamType: .mjpeg,
                streamURL: fallbackURL,
                isAvailable: true
            )
        }

        return CameraStreamConfig(
            sourceType: .none,
            isAvailable: false,
            unavailableReason: "Printer is not reporting an OEM camera stream and no custom camera URL is configured"
        )
    }

    public static func detectStreamType(_ url: URL) -> CameraStreamType {
        url.scheme?.lowercased() == "rtsp" ? .rtsp : .mjpeg
    }

    public static func validateCameraURL(_ urlString: String) -> Result<URL, CameraStreamValidationError> {
        guard !urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure(.empty)
        }

        guard let url = URL(string: urlString) else {
            return .failure(.invalidFormat)
        }

        guard let scheme = url.scheme?.lowercased(),
              ["http", "https", "rtsp"].contains(scheme) else {
            return .failure(.unsupportedProtocol)
        }

        guard let host = url.host, !host.isEmpty else {
            return .failure(.invalidHostname)
        }

        return .success(url)
    }

    private static func validTrimmedURL(_ urlString: String) -> URL? {
        let trimmedURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard case .success(let url) = validateCameraURL(trimmedURL) else {
            return nil
        }
        return url
    }
}
