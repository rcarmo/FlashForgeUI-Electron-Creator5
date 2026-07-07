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
    #expect(status.bedTarget == 60)
    #expect(status.jobSnapshot?.fileName == "benchy.3mf")
    #expect(status.materialStation?.activeSlot == 2)
    #expect(status.materialStation?.overallStatus == .ready)
    #expect(status.materialStation?.slots.first?.materialType == "PLA")
    #expect(status.materialStation?.slots.first?.materialColor == "#ff0000")
    #expect(status.materialStation?.slots.last?.isEmpty == true)
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
        MaterialStationSlot(
            slotId: 4,
            materialType: "ABS",
            materialColor: "ffffff",
            isEmpty: false
        )
    ])
}
