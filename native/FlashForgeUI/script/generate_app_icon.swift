#!/usr/bin/env swift

import AppKit
import Foundation

let outputPath = CommandLine.arguments.dropFirst().first ?? ""
guard !outputPath.isEmpty else {
    fputs("usage: generate_app_icon.swift /path/to/AppIcon.icns\n", stderr)
    exit(2)
}

let outputURL = URL(fileURLWithPath: outputPath)
let iconEntries: [(type: String, pixels: Int)] = [
    ("icp4", 16),
    ("icp5", 32),
    ("icp6", 64),
    ("ic07", 128),
    ("ic08", 256),
    ("ic09", 512),
    ("ic10", 1024)
]

func drawIcon(size: Int) throws -> Data {
    let imageSize = NSSize(width: size, height: size)
    guard let representation = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw NSError(domain: "FlashForgeUI.Icon", code: 1)
    }

    representation.size = imageSize
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: representation)

    let bounds = NSRect(origin: .zero, size: imageSize)
    NSColor.clear.setFill()
    bounds.fill()

    let cornerRadius = CGFloat(size) * 0.22
    let backgroundPath = NSBezierPath(roundedRect: bounds.insetBy(dx: CGFloat(size) * 0.06, dy: CGFloat(size) * 0.06), xRadius: cornerRadius, yRadius: cornerRadius)
    NSGradient(colors: [
        NSColor(calibratedRed: 0.12, green: 0.47, blue: 0.78, alpha: 1),
        NSColor(calibratedRed: 0.05, green: 0.18, blue: 0.28, alpha: 1)
    ])?.draw(in: backgroundPath, angle: 315)

    let plateRect = NSRect(
        x: CGFloat(size) * 0.18,
        y: CGFloat(size) * 0.21,
        width: CGFloat(size) * 0.64,
        height: CGFloat(size) * 0.20
    )
    let platePath = NSBezierPath(roundedRect: plateRect, xRadius: CGFloat(size) * 0.04, yRadius: CGFloat(size) * 0.04)
    NSColor(calibratedWhite: 1, alpha: 0.84).setFill()
    platePath.fill()

    let frameRect = NSRect(
        x: CGFloat(size) * 0.26,
        y: CGFloat(size) * 0.40,
        width: CGFloat(size) * 0.48,
        height: CGFloat(size) * 0.38
    )
    let framePath = NSBezierPath(roundedRect: frameRect, xRadius: CGFloat(size) * 0.05, yRadius: CGFloat(size) * 0.05)
    framePath.lineWidth = max(2, CGFloat(size) * 0.035)
    NSColor(calibratedWhite: 1, alpha: 0.92).setStroke()
    framePath.stroke()

    let headRect = NSRect(
        x: CGFloat(size) * 0.43,
        y: CGFloat(size) * 0.49,
        width: CGFloat(size) * 0.14,
        height: CGFloat(size) * 0.15
    )
    let headPath = NSBezierPath(roundedRect: headRect, xRadius: CGFloat(size) * 0.025, yRadius: CGFloat(size) * 0.025)
    NSColor(calibratedRed: 1.0, green: 0.64, blue: 0.28, alpha: 1).setFill()
    headPath.fill()

    let nozzle = NSBezierPath()
    nozzle.move(to: NSPoint(x: CGFloat(size) * 0.47, y: CGFloat(size) * 0.49))
    nozzle.line(to: NSPoint(x: CGFloat(size) * 0.53, y: CGFloat(size) * 0.49))
    nozzle.line(to: NSPoint(x: CGFloat(size) * 0.50, y: CGFloat(size) * 0.43))
    nozzle.close()
    NSColor(calibratedRed: 1.0, green: 0.78, blue: 0.42, alpha: 1).setFill()
    nozzle.fill()

    let filamentPath = NSBezierPath()
    filamentPath.lineWidth = max(2, CGFloat(size) * 0.03)
    filamentPath.move(to: NSPoint(x: CGFloat(size) * 0.50, y: CGFloat(size) * 0.78))
    filamentPath.line(to: NSPoint(x: CGFloat(size) * 0.50, y: CGFloat(size) * 0.64))
    NSColor(calibratedWhite: 1, alpha: 0.92).setStroke()
    filamentPath.stroke()

    NSGraphicsContext.restoreGraphicsState()

    guard let png = representation.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "FlashForgeUI.Icon", code: 2)
    }
    return png
}

func appendFourCharacterCode(_ code: String, to data: inout Data) {
    data.append(code.data(using: .ascii)!)
}

func appendBigEndianUInt32(_ value: UInt32, to data: inout Data) {
    var bigEndianValue = value.bigEndian
    withUnsafeBytes(of: &bigEndianValue) { bytes in
        data.append(contentsOf: bytes)
    }
}

let pngEntries = try iconEntries.map { entry in
    (type: entry.type, png: try drawIcon(size: entry.pixels))
}

let totalLength = pngEntries.reduce(8) { total, entry in
    total + 8 + entry.png.count
}

var icnsData = Data()
appendFourCharacterCode("icns", to: &icnsData)
appendBigEndianUInt32(UInt32(totalLength), to: &icnsData)

for entry in iconEntries {
    guard let pngEntry = pngEntries.first(where: { $0.type == entry.type }) else {
        continue
    }

    appendFourCharacterCode(entry.type, to: &icnsData)
    appendBigEndianUInt32(UInt32(8 + pngEntry.png.count), to: &icnsData)
    icnsData.append(pngEntry.png)
}

try icnsData.write(to: outputURL, options: .atomic)
