import Foundation

public protocol ModernPrinterHTTPClient {
    func fetchStatus(host: String, port: UInt16, serialNumber: String, checkCode: String) async throws -> ModernPrinterStatus
}

public enum ModernPrinterHTTPError: Error, Equatable, Sendable {
    case invalidURL
    case transportFailed
    case invalidResponse
    case httpStatus(Int, String?)
    case printerRejectedRequest(String)
    case missingDetail
}

public final class URLSessionModernPrinterHTTPClient: ModernPrinterHTTPClient {
    private let session: URLSession
    private let decoder: JSONDecoder

    public init(session: URLSession = .shared, decoder: JSONDecoder = JSONDecoder()) {
        self.session = session
        self.decoder = decoder
    }

    public func fetchStatus(
        host: String,
        port: UInt16,
        serialNumber: String,
        checkCode: String
    ) async throws -> ModernPrinterStatus {
        guard let url = URL(string: "http://\(host):\(port)/detail") else {
            throw ModernPrinterHTTPError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 5
        request.httpBody = try JSONEncoder().encode(DetailRequest(serialNumber: serialNumber, checkCode: checkCode))

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ModernPrinterHTTPError.transportFailed
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ModernPrinterHTTPError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw ModernPrinterHTTPError.httpStatus(
                httpResponse.statusCode,
                Self.failureMessage(from: data, decoder: decoder)
            )
        }

        let detailResponse: DetailResponse
        do {
            detailResponse = try decoder.decode(DetailResponse.self, from: data)
        } catch {
            throw ModernPrinterHTTPError.invalidResponse
        }

        guard detailResponse.code == 0, detailResponse.message == "Success" else {
            throw ModernPrinterHTTPError.printerRejectedRequest(detailResponse.message)
        }
        guard let detail = detailResponse.detail else {
            throw ModernPrinterHTTPError.missingDetail
        }
        return detail.status
    }

    private static func failureMessage(from data: Data, decoder: JSONDecoder) -> String? {
        if let detailResponse = try? decoder.decode(DetailResponse.self, from: data) {
            let trimmedMessage = detailResponse.message.trimmingCharacters(in: .whitespacesAndNewlines)
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

private struct DetailRequest: Encodable {
    var serialNumber: String
    var checkCode: String
}

private struct DetailResponse: Decodable {
    var code: Int
    var message: String
    var detail: ModernPrinterDetail?
}

public struct ModernPrinterDetail: Decodable, Equatable, Sendable {
    private static let pid5M = 35
    private static let pid5MPro = 36
    private static let pidAD5X = 38

    public var name: String?
    public var firmwareVersion: String?
    public var pid: Int?
    public var rawStatus: String?
    public var platTemp: Double?
    public var platTargetTemp: Double?
    public var rightTemp: Double?
    public var rightTargetTemp: Double?
    public var printFileName: String?
    public var printProgress: Double?
    public var estimatedTime: Double?
    public var printDuration: Double?
    public var rightFilamentType: String?
    public var cameraStreamUrl: String?
    public var hasMatlStation: Bool?
    public var matlStationInfo: MaterialStationInfo?

    enum CodingKeys: String, CodingKey {
        case name
        case firmwareVersion
        case pid
        case rawStatus = "status"
        case platTemp
        case platTargetTemp
        case rightTemp
        case rightTargetTemp
        case printFileName
        case printProgress
        case estimatedTime
        case printDuration
        case rightFilamentType
        case cameraStreamUrl
        case hasMatlStation
        case matlStationInfo
        case Name
        case FirmwareVersion
        case Pid
        case HasMatlStation
        case MatlStationInfo
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decodeIfPresent(String.self, forKey: .name)
            ?? container.decodeIfPresent(String.self, forKey: .Name)
        self.firmwareVersion = try container.decodeIfPresent(String.self, forKey: .firmwareVersion)
            ?? container.decodeIfPresent(String.self, forKey: .FirmwareVersion)
        self.pid = try container.decodeIfPresent(Int.self, forKey: .pid)
            ?? container.decodeIfPresent(Int.self, forKey: .Pid)
        self.rawStatus = try container.decodeIfPresent(String.self, forKey: .rawStatus)
        self.platTemp = try container.decodeIfPresent(Double.self, forKey: .platTemp)
        self.platTargetTemp = try container.decodeIfPresent(Double.self, forKey: .platTargetTemp)
        self.rightTemp = try container.decodeIfPresent(Double.self, forKey: .rightTemp)
        self.rightTargetTemp = try container.decodeIfPresent(Double.self, forKey: .rightTargetTemp)
        self.printFileName = try container.decodeIfPresent(String.self, forKey: .printFileName)
        self.printProgress = try container.decodeIfPresent(Double.self, forKey: .printProgress)
        self.estimatedTime = try container.decodeIfPresent(Double.self, forKey: .estimatedTime)
        self.printDuration = try container.decodeIfPresent(Double.self, forKey: .printDuration)
        self.rightFilamentType = try container.decodeIfPresent(String.self, forKey: .rightFilamentType)
        self.cameraStreamUrl = try container.decodeIfPresent(String.self, forKey: .cameraStreamUrl)
        self.hasMatlStation = try container.decodeIfPresent(Bool.self, forKey: .hasMatlStation)
            ?? container.decodeIfPresent(Bool.self, forKey: .HasMatlStation)
        self.matlStationInfo = try container.decodeIfPresent(MaterialStationInfo.self, forKey: .matlStationInfo)
            ?? container.decodeIfPresent(MaterialStationInfo.self, forKey: .MatlStationInfo)
    }

    public var status: ModernPrinterStatus {
        let hasMaterialStation = hasMatlStation == true || (matlStationInfo?.slotCnt ?? 0) > 0 || !(matlStationInfo?.slotInfos ?? []).isEmpty
        let isAD5X: Bool
        let isPro: Bool

        if let pid, [Self.pid5M, Self.pid5MPro, Self.pidAD5X].contains(pid) {
            isAD5X = pid == Self.pidAD5X
            isPro = pid == Self.pid5MPro
        } else {
            isAD5X = name == "AD5X" || hasMaterialStation
            isPro = (name ?? "").contains("Pro") && !isAD5X
        }

        return ModernPrinterStatus(
            displayName: name ?? "Unknown Printer",
            firmwareVersion: firmwareVersion ?? "",
            pid: pid,
            isPro: isPro,
            isAD5X: isAD5X,
            state: ModernPrinterState(rawDetailStatus: rawStatus ?? ""),
            nozzleCurrent: rightTemp ?? 0,
            nozzleTarget: rightTargetTemp ?? 0,
            bedCurrent: platTemp ?? 0,
            bedTarget: platTargetTemp ?? 0,
            printFileName: printFileName ?? "",
            printProgress: printProgress ?? 0,
            estimatedTime: estimatedTime ?? 0,
            printDuration: printDuration ?? 0,
            filamentType: rightFilamentType ?? "",
            cameraStreamURL: cameraStreamUrl ?? "",
            materialStation: matlStationInfo?.status
        )
    }
}

public struct MaterialStationInfo: Decodable, Equatable, Sendable {
    public var currentLoadSlot: Int
    public var currentSlot: Int
    public var slotCnt: Int
    public var slotInfos: [MaterialSlotInfo]
    public var stateAction: Int
    public var stateStep: Int

    enum CodingKeys: String, CodingKey {
        case currentLoadSlot
        case currentSlot
        case slotCnt
        case slotInfos
        case stateAction
        case stateStep
        case CurrentLoadSlot
        case CurrentSlot
        case SlotCnt
        case SlotInfos
        case StateAction
        case StateStep
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.slotInfos = try container.decodeFlexibleArray(
            for: .slotInfos,
            alternative: .SlotInfos,
            defaultValue: []
        )
        self.currentLoadSlot = try container.decodeFlexibleInt(
            for: .currentLoadSlot,
            alternative: .CurrentLoadSlot,
            defaultValue: 0
        )
        self.currentSlot = try container.decodeFlexibleInt(
            for: .currentSlot,
            alternative: .CurrentSlot,
            defaultValue: 0
        )
        self.slotCnt = try container.decodeFlexibleInt(
            for: .slotCnt,
            alternative: .SlotCnt,
            defaultValue: slotInfos.count
        )
        self.stateAction = try container.decodeFlexibleInt(
            for: .stateAction,
            alternative: .StateAction,
            defaultValue: 0
        )
        self.stateStep = try container.decodeFlexibleInt(
            for: .stateStep,
            alternative: .StateStep,
            defaultValue: 0
        )
    }

    public var status: MaterialStationStatus {
        MaterialStationStatus(
            connected: true,
            slots: slotInfos.map { $0.slotStatus },
            activeSlot: currentSlot == 0 ? nil : currentSlot,
            overallStatus: stateAction > 0 ? .warming : .ready
        )
    }
}

public struct MaterialSlotInfo: Decodable, Equatable, Sendable {
    public var slotId: Int
    public var hasFilament: Bool
    public var materialName: String
    public var materialColor: String

    enum CodingKeys: String, CodingKey {
        case slotId
        case hasFilament
        case materialName
        case materialColor
        case SlotId
        case HasFilament
        case MaterialName
        case MaterialColor
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.slotId = try container.decodeFlexibleInt(
            for: .slotId,
            alternative: .SlotId,
            defaultValue: 0
        )
        self.hasFilament = try container.decodeFlexibleBool(
            for: .hasFilament,
            alternative: .HasFilament,
            defaultValue: false
        )
        self.materialName = try container.decodeFlexibleString(
            for: .materialName,
            alternative: .MaterialName,
            defaultValue: ""
        )
        self.materialColor = try container.decodeFlexibleString(
            for: .materialColor,
            alternative: .MaterialColor,
            defaultValue: ""
        )
    }

    public var slotStatus: MaterialStationSlot {
        MaterialStationSlot(
            slotId: slotId,
            materialType: hasFilament && !materialName.isEmpty ? materialName : nil,
            materialColor: hasFilament && !materialColor.isEmpty ? materialColor : nil,
            isEmpty: !hasFilament
        )
    }
}

private extension KeyedDecodingContainer {
    func decodeFlexibleInt(
        for key: Key,
        alternative: Key,
        defaultValue: Int
    ) throws -> Int {
        for candidate in [key, alternative] {
            if let value = try? decodeIfPresent(Int.self, forKey: candidate) {
                return value
            }
            if let value = try? decodeIfPresent(String.self, forKey: candidate),
               let parsed = Int(value.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return parsed
            }
        }
        return defaultValue
    }

    func decodeFlexibleBool(
        for key: Key,
        alternative: Key,
        defaultValue: Bool
    ) throws -> Bool {
        for candidate in [key, alternative] {
            if let value = try? decodeIfPresent(Bool.self, forKey: candidate) {
                return value
            }
            if let value = try? decodeIfPresent(Int.self, forKey: candidate) {
                return value != 0
            }
            if let value = try? decodeIfPresent(String.self, forKey: candidate) {
                switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
                case "1", "true", "yes", "open":
                    return true
                case "0", "false", "no", "close", "closed":
                    return false
                default:
                    break
                }
            }
        }
        return defaultValue
    }

    func decodeFlexibleString(
        for key: Key,
        alternative: Key,
        defaultValue: String
    ) throws -> String {
        for candidate in [key, alternative] {
            if let value = try? decodeIfPresent(String.self, forKey: candidate) {
                return value
            }
            if let value = try? decodeIfPresent(Int.self, forKey: candidate) {
                return String(value)
            }
        }
        return defaultValue
    }

    func decodeFlexibleArray<Element: Decodable>(
        for key: Key,
        alternative: Key,
        defaultValue: [Element]
    ) throws -> [Element] {
        for candidate in [key, alternative] {
            if let value = try decodeIfPresent([Element].self, forKey: candidate) {
                return value
            }
        }
        return defaultValue
    }
}
