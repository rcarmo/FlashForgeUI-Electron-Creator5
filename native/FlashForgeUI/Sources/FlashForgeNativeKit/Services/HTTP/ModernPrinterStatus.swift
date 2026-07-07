import Foundation

public struct ModernPrinterStatus: Equatable, Sendable {
    public var displayName: String
    public var firmwareVersion: String
    public var pid: Int?
    public var isPro: Bool
    public var isAD5X: Bool
    public var state: ModernPrinterState
    public var nozzleCurrent: Double
    public var nozzleTarget: Double
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
        firmwareVersion: String,
        pid: Int? = nil,
        isPro: Bool,
        isAD5X: Bool,
        state: ModernPrinterState,
        nozzleCurrent: Double,
        nozzleTarget: Double,
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
        self.firmwareVersion = firmwareVersion
        self.pid = pid
        self.isPro = isPro
        self.isAD5X = isAD5X
        self.state = state
        self.nozzleCurrent = nozzleCurrent
        self.nozzleTarget = nozzleTarget
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
        switch rawDetailStatus.lowercased() {
        case "ready":
            self = .ready
        case "busy":
            self = .busy
        case "calibrate_doing":
            self = .calibrating
        case "error":
            self = .error
        case "heating":
            self = .heating
        case "printing":
            self = .printing
        case "pausing":
            self = .pausing
        case "paused":
            self = .paused
        case "cancel":
            self = .cancelled
        case "completed":
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
