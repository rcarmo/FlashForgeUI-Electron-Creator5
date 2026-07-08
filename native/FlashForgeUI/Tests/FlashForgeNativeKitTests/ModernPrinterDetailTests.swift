import Foundation
import FlashForgeNativeKit
import Testing

@Test func decodesModernDetailUsingPidForModelCapabilities() throws {
    let json = """
    {
      "name": "User Renamed Printer",
      "firmwareVersion": "3.2.0",
      "pid": 38,
      "status": "printing",
      "platTemp": 59,
      "platTargetTemp": 60,
      "rightTemp": 221,
      "rightTargetTemp": 225,
      "printFileName": "benchy.3mf",
      "printProgress": 0.5,
      "estimatedTime": 1800,
      "printDuration": 1200,
      "rightFilamentType": "PLA",
      "cameraStreamUrl": "rtsp://printer/live",
      "matlStationInfo": {
        "currentSlot": 2,
        "slotCnt": 4,
        "slotInfos": [
          {
            "slotId": 1,
            "hasFilament": true,
            "materialName": "PLA",
            "materialColor": "#ff0000"
          },
          {
            "slotId": 2,
            "hasFilament": false,
            "materialName": "",
            "materialColor": ""
          }
        ],
        "stateAction": 0,
        "stateStep": 0
      }
    }
    """.data(using: .utf8)!

    let detail = try JSONDecoder().decode(ModernPrinterDetail.self, from: json)
    let status = detail.status

    #expect(status.displayName == "User Renamed Printer")
    #expect(status.modelName == "AD5X")
    #expect(status.isAD5X == true)
    #expect(status.state == .printing)
    #expect(status.nozzleCurrent == 221)
    #expect(status.toolheadTemperatures == [
        ToolheadTemperature(
            id: "nozzle",
            label: "Nozzle",
            reading: TemperatureReading(current: 221, target: 225)
        )
    ])
    #expect(status.bedTarget == 60)
    #expect(status.jobSnapshot?.fileName == "benchy.3mf")
    #expect(status.materialStation?.activeSlot == 2)
    #expect(status.materialStation?.overallStatus == .ready)
    #expect(status.materialStation?.slots.count == 4)
    #expect(status.materialStation?.slots.map(\.slotId) == [1, 2, 3, 4])
    #expect(status.materialStation?.slots.first?.materialType == "PLA")
    #expect(status.materialStation?.slots.first?.materialColor == "#ff0000")
    #expect(status.materialStation?.slots.last?.isEmpty == true)
}

@Test func decodesMultipleToolheadTemperatures() throws {
    let json = """
    {
      "name": "Creator 5 Pro",
      "pid": 36,
      "status": "ready",
      "platTemp": "52",
      "platTargetTemp": "60",
      "leftTemp": "31",
      "leftTargetTemp": "0",
      "rightTemp": 216,
      "rightTargetTemp": 220,
      "tool3Temp": 42,
      "tool3TargetTemp": 0,
      "tool4Temp": 43,
      "tool4TargetTemp": 0
    }
    """.data(using: .utf8)!

    let detail = try JSONDecoder().decode(ModernPrinterDetail.self, from: json)
    let status = detail.status

    #expect(status.bedCurrent == 52)
    #expect(status.bedTarget == 60)
    #expect(status.toolheadTemperatures == [
        ToolheadTemperature(id: "left", label: "Left Toolhead", reading: TemperatureReading(current: 31)),
        ToolheadTemperature(id: "right", label: "Right Toolhead", reading: TemperatureReading(current: 216, target: 220)),
        ToolheadTemperature(id: "toolhead-3", label: "Toolhead 3", reading: TemperatureReading(current: 42)),
        ToolheadTemperature(id: "toolhead-4", label: "Toolhead 4", reading: TemperatureReading(current: 43))
    ])
}

@Test func decodesCreator5ProCharacteristicsFromDetailPayload() throws {
    let json = """
    {
      "name": "Creator 5 Pro",
      "model": "Creator 5 Pro",
      "pid": 41,
      "firmwareVersion": "1.9.4",
      "status": "ready",
      "camera": 1,
      "cameraStreamUrl": "http://192.168.1.161:8080/?action=stream",
      "matlStationInfo": {
        "currentSlot": 0,
        "slotCnt": 4,
        "slotInfos": [
          { "slotId": 1, "hasFilament": true, "materialName": "PLA", "materialColor": "#7BD9F0" },
          { "slotId": 2, "hasFilament": true, "materialName": "PLA", "materialColor": "#FFF245" },
          { "slotId": 3, "hasFilament": true, "materialName": "PLA", "materialColor": "#F435F6" },
          { "slotId": 4, "hasFilament": true, "materialName": "PLA", "materialColor": "#FFFFFF" }
        ],
        "stateAction": 0,
        "stateStep": 0
      },
      "nozzleCnt": 4,
      "nozzleTargetTemps": [0, 0, 0, 0],
      "nozzleTemps": [25, 26, 26, 27],
      "platTargetTemp": 0,
      "platTemp": 25,
      "rightTargetTemp": 0,
      "rightTemp": 25
    }
    """.data(using: .utf8)!

    let detail = try JSONDecoder().decode(ModernPrinterDetail.self, from: json)
    let status = detail.status

    #expect(status.modelName == "Creator 5 Pro")
    #expect(status.reportedModel == "Creator 5 Pro")
    #expect(status.pid == 41)
    #expect(status.isCreator5Pro == true)
    #expect(status.isAD5X == false)
    #expect(status.nozzleCount == 4)
    #expect(status.hasCamera == true)
    #expect(status.cameraStreamURL == "http://192.168.1.161:8080/?action=stream")
    #expect(status.toolheadTemperatures == [
        ToolheadTemperature(id: "toolhead-1", label: "Toolhead 1", reading: TemperatureReading(current: 25)),
        ToolheadTemperature(id: "toolhead-2", label: "Toolhead 2", reading: TemperatureReading(current: 26)),
        ToolheadTemperature(id: "toolhead-3", label: "Toolhead 3", reading: TemperatureReading(current: 26)),
        ToolheadTemperature(id: "toolhead-4", label: "Toolhead 4", reading: TemperatureReading(current: 27))
    ])
    #expect(status.materialStation?.slots.count == 4)
}

@Test func decodesZeroBasedFourToolheadTemperatures() throws {
    let json = """
    {
      "name": "Creator 5 Pro",
      "pid": 36,
      "status": "ready",
      "temp0": 26,
      "temp0Target": 0,
      "temp1": 25,
      "temp1Target": 0,
      "temp2": 24,
      "temp2Target": 0,
      "temp3": 23,
      "temp3Target": 0
    }
    """.data(using: .utf8)!

    let detail = try JSONDecoder().decode(ModernPrinterDetail.self, from: json)
    let status = detail.status

    #expect(status.toolheadTemperatures == [
        ToolheadTemperature(id: "toolhead-1", label: "Toolhead 1", reading: TemperatureReading(current: 26)),
        ToolheadTemperature(id: "toolhead-2", label: "Toolhead 2", reading: TemperatureReading(current: 25)),
        ToolheadTemperature(id: "toolhead-3", label: "Toolhead 3", reading: TemperatureReading(current: 24)),
        ToolheadTemperature(id: "toolhead-4", label: "Toolhead 4", reading: TemperatureReading(current: 23))
    ])
}

@Test func fallsBackToMaterialStationWhenPidMissing() throws {
    let json = """
    {
      "name": "Shop Printer",
      "firmwareVersion": "3.2.0",
      "status": "ready",
      "matlStationInfo": { "slotCnt": 4, "slotInfos": [] }
    }
    """.data(using: .utf8)!

    let detail = try JSONDecoder().decode(ModernPrinterDetail.self, from: json)

    #expect(detail.status.modelName == "AD5X")
    #expect(detail.status.state == .ready)
}

@Test func modernPrinterStateAcceptsCommonFirmwareStatusAliases() {
    #expect(ModernPrinterState(rawDetailStatus: "idle") == .ready)
    #expect(ModernPrinterState(rawDetailStatus: "print") == .printing)
    #expect(ModernPrinterState(rawDetailStatus: "building") == .printing)
    #expect(ModernPrinterState(rawDetailStatus: "pause") == .paused)
    #expect(ModernPrinterState(rawDetailStatus: "canceled") == .cancelled)
    #expect(ModernPrinterState(rawDetailStatus: "finished") == .completed)
    #expect(ModernPrinterState(rawDetailStatus: "Calibrate Doing") == .calibrating)
    #expect(ModernPrinterState(rawDetailStatus: "disconnected") == .busy)
}

@Test func decodesCapitalizedMaterialStationPayload() throws {
    let json = """
    {
      "Name": "Capitalized Payload",
      "status": "ready",
      "HasMatlStation": true,
      "MatlStationInfo": {
        "CurrentSlot": "4",
        "SlotCnt": "4",
        "SlotInfos": [
          {
            "SlotId": "4",
            "HasFilament": 1,
            "MaterialName": "ABS",
            "MaterialColor": "ffffff"
          }
        ],
        "StateAction": "1",
        "StateStep": 0
      }
    }
    """.data(using: .utf8)!

    let detail = try JSONDecoder().decode(ModernPrinterDetail.self, from: json)
    let station = detail.status.materialStation

    #expect(station?.activeSlot == 4)
    #expect(station?.overallStatus == .warming)
    #expect(station?.slots == [
        MaterialStationSlot(slotId: 1, isEmpty: true),
        MaterialStationSlot(slotId: 2, isEmpty: true),
        MaterialStationSlot(slotId: 3, isEmpty: true),
        MaterialStationSlot(
            slotId: 4,
            materialType: "ABS",
            materialColor: "ffffff",
            isEmpty: false
        )
    ])
}

@Test func materialStationSummariesExplainCurrentState() {
    let readyStation = MaterialStationStatus(
        connected: true,
        slots: [
            MaterialStationSlot(slotId: 3, materialType: "PETG", materialColor: "#00ff00", isEmpty: false),
            MaterialStationSlot(slotId: 1, materialType: "PLA", materialColor: "#ff0000", isEmpty: false),
            MaterialStationSlot(slotId: 2, isEmpty: true)
        ],
        activeSlot: 1,
        overallStatus: .ready
    )

    #expect(readyStation.occupiedSlotCount == 2)
    #expect(readyStation.displaySlots.map(\.slotId) == [1, 2, 3])
    #expect(readyStation.statusSummary == "2 of 3 slots loaded.")
    #expect(readyStation.activeSlotSummary == "Slot 1 active: PLA.")

    let changingStation = MaterialStationStatus(
        connected: true,
        slots: [MaterialStationSlot(slotId: 4, materialType: "ABS", materialColor: "ffffff", isEmpty: false)],
        activeSlot: 4,
        overallStatus: .warming
    )

    #expect(changingStation.statusSummary == "Changing material. 1 of 1 slot loaded.")

    let disconnectedStation = MaterialStationStatus(
        connected: false,
        slots: [],
        overallStatus: .disconnected
    )

    #expect(disconnectedStation.statusSummary == "Station disconnected.")

    let erroredStation = MaterialStationStatus(
        connected: true,
        slots: [],
        activeSlot: 2,
        overallStatus: .error,
        errorMessage: "Filament path blocked."
    )

    #expect(erroredStation.statusSummary == "Filament path blocked.")
    #expect(erroredStation.activeSlotSummary == "Slot 2 selected.")
}
