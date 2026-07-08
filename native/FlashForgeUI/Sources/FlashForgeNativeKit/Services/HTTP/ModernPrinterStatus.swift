import Foundation

public struct ModernPrinterStatus: Equatable, Sendable {
    public var displayName: String
    public var reportedModel: String
    public var firmwareVersion: String
    public var pid: Int?
    public var isPro: Bool
    public var isAD5X: Bool
    public var isCreator5Pro: Bool
    public var nozzleCount: Int
    public var hasCamera: Bool
    public var state: ModernPrinterState
    public var nozzleCurrent: Double
    public var nozzleTarget: Double
    public var toolheadTemperatures: [ToolheadTemperature]
    public var bedCurrent: Double
    public var bedTarget: Double
    public var printFileName: String
    public var printProgress: Double
    public var estimatedTime: TimeInterval
    public var printDuration: TimeInterval
    public var filamentType: String
    public var cameraStreamURL: String
    public var materialStation: MaterialStationStatus?

    public init(
        displayName: String,
        reportedModel: String = "",
        firmwareVersion: String,
        pid: Int? = nil,
        isPro: Bool,
        isAD5X: Bool,
        isCreator5Pro: Bool = false,
        nozzleCount: Int = 1,
        hasCamera: Bool = false,
        state: ModernPrinterState,
        nozzleCurrent: Double,
        nozzleTarget: Double,
        toolheadTemperatures: [ToolheadTemperature]? = nil,
        bedCurrent: Double,
        bedTarget: Double,
        printFileName: String = "",
        printProgress: Double = 0,
        estimatedTime: TimeInterval = 0,
        printDuration: TimeInterval = 0,
        filamentType: String = "",
        cameraStreamURL: String = "",
        materialStation: MaterialStationStatus? = nil
    ) {
        self.displayName = displayName
        self.reportedModel = reportedModel
        self.firmwareVersion = firmwareVersion
        self.pid = pid
        self.isPro = isPro
        self.isAD5X = isAD5X
        self.isCreator5Pro = isCreator5Pro
        self.nozzleCount = nozzleCount
        self.hasCamera = hasCamera
        self.state = state
        self.nozzleCurrent = nozzleCurrent
        self.nozzleTarget = nozzleTarget
        self.toolheadTemperatures = toolheadTemperatures ?? [
            ToolheadTemperature(
                id: "nozzle",
                label: "Nozzle",
                reading: TemperatureReading(current: nozzleCurrent, target: nozzleTarget)
            )
        ]
        self.bedCurrent = bedCurrent
        self.bedTarget = bedTarget
        self.printFileName = printFileName
        self.printProgress = printProgress
        self.estimatedTime = estimatedTime
        self.printDuration = printDuration
        self.filamentType = filamentType
        self.cameraStreamURL = cameraStreamURL
        self.materialStation = materialStation
    }

    public var modelName: String {
        if !reportedModel.isEmpty {
            return reportedModel
        }
        if isCreator5Pro {
            return "Creator 5 Pro"
        }
        if isAD5X {
            return "AD5X"
        }
        if isPro {
            return "Adventurer 5M Pro"
        }
        return "Adventurer 5M"
    }

    public var jobSnapshot: PrintJobSnapshot? {
        guard !printFileName.isEmpty else {
            return nil
        }
        return PrintJobSnapshot(
            fileName: printFileName,
            progress: printProgress,
            timeRemaining: estimatedTime
        )
    }

    public var materialSnapshot: MaterialSnapshot? {
        guard !filamentType.isEmpty else {
            return nil
        }
        return MaterialSnapshot(name: filamentType, colorHex: "#6E6E73")
    }
}

public enum ModernPrinterState: String, Sendable {
    case ready = "Ready"
    case busy = "Busy"
    case calibrating = "Calibrating"
    case error = "Error"
    case heating = "Heating"
    case printing = "Printing"
    case pausing = "Pausing"
    case paused = "Paused"
    case cancelled = "Cancelled"
    case completed = "Completed"
    case unknown = "Unknown"

    public init(rawDetailStatus: String) {
        let normalizedStatus = rawDetailStatus
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")

        switch normalizedStatus {
        case "idle", "ready":
            self = .ready
        case "busy", "unknown", "offline", "disconnected":
            self = .busy
        case "calibrate", "calibrating", "calibrate_doing", "leveling":
            self = .calibrating
        case "error":
            self = .error
        case "heating":
            self = .heating
        case "print", "printing", "build", "building":
            self = .printing
        case "pausing":
            self = .pausing
        case "pause", "paused":
            self = .paused
        case "cancel", "canceled", "cancelled":
            self = .cancelled
        case "complete", "completed", "finished":
            self = .completed
        default:
            self = .unknown
        }
    }

    public var printerStatus: PrinterStatus {
        switch self {
        case .ready, .completed:
            .ready
        case .printing, .heating, .calibrating:
            .printing
        case .paused, .pausing:
            .paused
        case .busy:
            .busy
        case .error:
            .needsAttention
        case .cancelled, .unknown:
            .offline
        }
    }
}
