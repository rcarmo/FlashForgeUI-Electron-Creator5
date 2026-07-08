import Foundation

public struct PrinterSnapshot: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var name: String
    public var model: String
    public var address: String
    public var serialNumber: String?
    public var commandPort: Int?
    public var eventPort: Int?
    public var protocolFormat: DiscoveryProtocolFormat?
    public var status: PrinterStatus
    public var nozzleTemperature: TemperatureReading
    public var bedTemperature: TemperatureReading
    public var toolheadTemperatures: [ToolheadTemperature]
    public var activeJob: PrintJobSnapshot?
    public var material: MaterialSnapshot?
    public var materialStation: MaterialStationStatus?
    public var cameraState: CameraState

    public init(
        id: UUID = UUID(),
        name: String,
        model: String,
        address: String,
        serialNumber: String? = nil,
        commandPort: Int? = nil,
        eventPort: Int? = nil,
        protocolFormat: DiscoveryProtocolFormat? = nil,
        status: PrinterStatus,
        nozzleTemperature: TemperatureReading,
        bedTemperature: TemperatureReading,
        toolheadTemperatures: [ToolheadTemperature]? = nil,
        activeJob: PrintJobSnapshot? = nil,
        material: MaterialSnapshot? = nil,
        materialStation: MaterialStationStatus? = nil,
        cameraState: CameraState = .unavailable
    ) {
        self.id = id
        self.name = name
        self.model = model
        self.address = address
        self.serialNumber = serialNumber
        self.commandPort = commandPort
        self.eventPort = eventPort
        self.protocolFormat = protocolFormat
        self.status = status
        self.nozzleTemperature = nozzleTemperature
        self.bedTemperature = bedTemperature
        self.toolheadTemperatures = toolheadTemperatures ?? [
            ToolheadTemperature(id: "nozzle", label: "Nozzle", reading: nozzleTemperature)
        ]
        self.activeJob = activeJob
        self.material = material
        self.materialStation = materialStation
        self.cameraState = cameraState
    }
}

extension PrinterSnapshot {
    var searchableFields: [String] {
        [
            name,
            model,
            address,
            serialNumber ?? "",
            status.rawValue
        ]
    }
}

public enum PrinterStatus: String, Codable, Sendable {
    case ready = "Ready"
    case busy = "Busy"
    case printing = "Printing"
    case paused = "Paused"
    case offline = "Offline"
    case needsAttention = "Needs Attention"

    public var isActionable: Bool {
        self == .needsAttention || self == .paused
    }
}

public struct TemperatureReading: Hashable, Codable, Sendable {
    public var current: Double
    public var target: Double?

    public init(current: Double, target: Double? = nil) {
        self.current = current
        self.target = target
    }
}

public struct ToolheadTemperature: Identifiable, Hashable, Codable, Sendable {
    public var id: String
    public var label: String
    public var reading: TemperatureReading

    public init(id: String, label: String, reading: TemperatureReading) {
        self.id = id
        self.label = label
        self.reading = reading
    }
}

public struct TemperatureHistoryPoint: Identifiable, Hashable, Sendable {
    public var id: Date { timestamp }
    public var timestamp: Date
    public var current: Double
    public var target: Double?

    public init(timestamp: Date, current: Double, target: Double? = nil) {
        self.timestamp = timestamp
        self.current = current
        self.target = target
    }
}

public struct TemperatureTelemetryItem: Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var reading: TemperatureReading
    public var history: [TemperatureHistoryPoint]

    public init(
        id: String,
        title: String,
        reading: TemperatureReading,
        history: [TemperatureHistoryPoint] = []
    ) {
        self.id = id
        self.title = title
        self.reading = reading
        self.history = history
    }
}

public struct PrintJobSnapshot: Hashable, Codable, Sendable {
    public var fileName: String
    public var progress: Double
    public var timeRemaining: TimeInterval?

    public init(fileName: String, progress: Double, timeRemaining: TimeInterval? = nil) {
        self.fileName = fileName
        self.progress = progress
        self.timeRemaining = timeRemaining
    }
}

public struct MaterialSnapshot: Hashable, Codable, Sendable {
    public var name: String
    public var colorHex: String
    public var remainingGrams: Double?

    public init(name: String, colorHex: String, remainingGrams: Double? = nil) {
        self.name = name
        self.colorHex = colorHex
        self.remainingGrams = remainingGrams
    }
}

public enum CameraState: String, Codable, Sendable {
    case available = "Available"
    case unavailable = "Unavailable"
    case reconnecting = "Reconnecting"
}

public struct MaterialStationStatus: Hashable, Codable, Sendable {
    public var connected: Bool
    public var slots: [MaterialStationSlot]
    public var activeSlot: Int?
    public var loadingSlot: Int?
    public var overallStatus: MaterialStationOverallStatus
    public var errorMessage: String?

    public init(
        connected: Bool,
        slots: [MaterialStationSlot],
        activeSlot: Int? = nil,
        loadingSlot: Int? = nil,
        overallStatus: MaterialStationOverallStatus,
        errorMessage: String? = nil
    ) {
        self.connected = connected
        self.slots = slots
        self.activeSlot = activeSlot
        self.loadingSlot = loadingSlot
        self.overallStatus = overallStatus
        self.errorMessage = errorMessage
    }

    public var occupiedSlotCount: Int {
        slots.filter { !$0.isEmpty }.count
    }

    public var displaySlots: [MaterialStationSlot] {
        slots.sorted { lhs, rhs in
            lhs.slotId < rhs.slotId
        }
    }

    public var statusSummary: String {
        if let errorMessage, !errorMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return errorMessage
        }

        if !connected || overallStatus == .disconnected {
            return "Station disconnected."
        }

        guard !slots.isEmpty else {
            return "No material slots reported."
        }

        let slotNoun = slots.count == 1 ? "slot" : "slots"
        let occupancy = "\(occupiedSlotCount) of \(slots.count) \(slotNoun) loaded."

        switch overallStatus {
        case .ready:
            return occupancy
        case .warming:
            return "Changing material. \(occupancy)"
        case .error:
            return "Station needs attention. \(occupancy)"
        case .disconnected:
            return "Station disconnected."
        }
    }

    public var activeSlotSummary: String? {
        guard let activeSlot else {
            return nil
        }

        guard let slot = slots.first(where: { $0.slotId == activeSlot }) else {
            return "Slot \(activeSlot) selected."
        }

        if slot.isEmpty {
            return "Slot \(activeSlot) selected, but no material is reported."
        }

        return "Slot \(activeSlot) active: \(slot.materialType ?? "Unknown material")."
    }
}

public struct MaterialStationSlot: Identifiable, Hashable, Codable, Sendable {
    public var id: Int { slotId }
    public var slotId: Int
    public var materialType: String?
    public var materialColor: String?
    public var isEmpty: Bool

    public init(
        slotId: Int,
        materialType: String? = nil,
        materialColor: String? = nil,
        isEmpty: Bool
    ) {
        self.slotId = slotId
        self.materialType = materialType
        self.materialColor = materialColor
        self.isEmpty = isEmpty
    }
}

public enum MaterialStationOverallStatus: String, Codable, Sendable {
    case ready
    case warming
    case error
    case disconnected
}
