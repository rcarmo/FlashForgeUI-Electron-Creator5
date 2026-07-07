import Foundation

public struct PrinterProfileDocument: Codable, Equatable, Sendable {
    public var version: Int
    public var profiles: [PrinterProfile]
    public var selectedPrinterID: UUID?

    public init(
        version: Int = 1,
        profiles: [PrinterProfile] = [],
        selectedPrinterID: UUID? = nil
    ) {
        self.version = version
        self.profiles = profiles
        self.selectedPrinterID = selectedPrinterID
    }
}

public struct PrinterProfile: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var model: String
    public var address: String
    public var serialNumber: String?
    public var commandPort: Int?
    public var eventPort: Int?
    public var protocolFormat: DiscoveryProtocolFormat?
    public var checkCode: String?
    public var cameraUserConfig: CameraUserConfig?
    public var recentUploadFileURLs: [URL]

    public init(
        id: UUID = UUID(),
        name: String,
        model: String,
        address: String,
        serialNumber: String? = nil,
        commandPort: Int? = nil,
        eventPort: Int? = nil,
        protocolFormat: DiscoveryProtocolFormat? = nil,
        checkCode: String? = nil,
        cameraUserConfig: CameraUserConfig? = nil,
        recentUploadFileURLs: [URL] = []
    ) {
        self.id = id
        self.name = name
        self.model = model
        self.address = address
        self.serialNumber = serialNumber
        self.commandPort = commandPort
        self.eventPort = eventPort
        self.protocolFormat = protocolFormat
        self.checkCode = checkCode
        self.cameraUserConfig = cameraUserConfig
        self.recentUploadFileURLs = recentUploadFileURLs
    }

    public init(
        snapshot: PrinterSnapshot,
        checkCode: String? = nil,
        cameraUserConfig: CameraUserConfig? = nil,
        recentUploadFileURLs: [URL] = []
    ) {
        self.init(
            id: snapshot.id,
            name: snapshot.name,
            model: snapshot.model,
            address: snapshot.address,
            serialNumber: snapshot.serialNumber,
            commandPort: snapshot.commandPort,
            eventPort: snapshot.eventPort,
            protocolFormat: snapshot.protocolFormat,
            checkCode: checkCode,
            cameraUserConfig: cameraUserConfig,
            recentUploadFileURLs: recentUploadFileURLs
        )
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        model = try container.decode(String.self, forKey: .model)
        address = try container.decode(String.self, forKey: .address)
        serialNumber = try container.decodeIfPresent(String.self, forKey: .serialNumber)
        commandPort = try container.decodeIfPresent(Int.self, forKey: .commandPort)
        eventPort = try container.decodeIfPresent(Int.self, forKey: .eventPort)
        protocolFormat = try container.decodeIfPresent(DiscoveryProtocolFormat.self, forKey: .protocolFormat)
        checkCode = try container.decodeIfPresent(String.self, forKey: .checkCode)
        cameraUserConfig = try container.decodeIfPresent(CameraUserConfig.self, forKey: .cameraUserConfig)
        recentUploadFileURLs = try container.decodeIfPresent([URL].self, forKey: .recentUploadFileURLs) ?? []
    }

    public func snapshot(status: PrinterStatus = .offline) -> PrinterSnapshot {
        PrinterSnapshot(
            id: id,
            name: name,
            model: model,
            address: address,
            serialNumber: serialNumber,
            commandPort: commandPort,
            eventPort: eventPort,
            protocolFormat: protocolFormat,
            status: status,
            nozzleTemperature: TemperatureReading(current: 0),
            bedTemperature: TemperatureReading(current: 0),
            cameraState: .unavailable
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case model
        case address
        case serialNumber
        case commandPort
        case eventPort
        case protocolFormat
        case checkCode
        case cameraUserConfig
        case recentUploadFileURLs
    }
}

public protocol PrinterProfileStore: Sendable {
    func loadDocument() throws -> PrinterProfileDocument
    func saveDocument(_ document: PrinterProfileDocument) throws
}

public final class FilePrinterProfileStore: PrinterProfileStore, @unchecked Sendable {
    private let fileURL: URL
    private let fileManager: FileManager
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    public init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    public static func defaultStore(appName: String = "FlashForgeUI") -> FilePrinterProfileStore {
        let baseURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory

        return FilePrinterProfileStore(
            fileURL: baseURL
                .appendingPathComponent(appName, isDirectory: true)
                .appendingPathComponent("PrinterProfiles.json")
        )
    }

    public func loadDocument() throws -> PrinterProfileDocument {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return PrinterProfileDocument()
        }

        let data = try Data(contentsOf: fileURL)
        return try decoder.decode(PrinterProfileDocument.self, from: data)
    }

    public func saveDocument(_ document: PrinterProfileDocument) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        let data = try encoder.encode(document)
        try data.write(to: fileURL, options: [.atomic])
    }
}
