#!/usr/bin/env swift
// Generates AppIcon.icns.
//
// Design: a blue rounded square (macOS system blue) with the `note.text`
// SF Symbol rendered in white in the middle — same shape as the menu bar
// icon, but filled in blue for the app icon.
//
// Run from the Notaty directory:
//     swift make_icon.swift

import AppKit
import UniformTypeIdentifiers

let projectRoot: String = {
    let path = CommandLine.arguments[0]
    let url = URL(fileURLWithPath: path)
    return url.deletingLastPathComponent().path
}()

let iconsetDir = (projectRoot as NSString).appendingPathComponent("build_iconset/AppIcon.iconset")
let icnsOut = (projectRoot as NSString).appendingPathComponent("AppIcon.icns")

let sizes: [(Int, String)] = [
    (16,  "icon_16x16.png"),
    (32,  "icon_16x16@2x.png"),
    (32,  "icon_32x32.png"),
    (64,  "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024,"icon_512x512@2x.png"),
]

func drawIcon(pixelSize: Int) -> NSImage {
    let s = CGFloat(pixelSize)
    let image = NSImage(size: NSSize(width: s, height: s))
    image.lockFocus()

    // Blue rounded-square background.
    let margin = s * 0.08
    let radius = s * 0.22
    let cardRect = NSRect(x: margin, y: margin, width: s - 2 * margin, height: s - 2 * margin)
    NSColor.systemBlue.setFill()
    NSBezierPath(roundedRect: cardRect, xRadius: radius, yRadius: radius).fill()

    // White `note.text` SF Symbol centered in the card.
    let symbolPointSize = s * 0.56
    let config = NSImage.SymbolConfiguration(pointSize: symbolPointSize, weight: .semibold)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    if let symbol = NSImage(systemSymbolName: "note.text", accessibilityDescription: nil)?
        .withSymbolConfiguration(config)
    {
        let symbolSize = symbol.size
        let symbolRect = NSRect(
            x: (s - symbolSize.width) / 2,
            y: (s - symbolSize.height) / 2,
            width: symbolSize.width,
            height: symbolSize.height
        )
        symbol.draw(in: symbolRect)
    }

    image.unlockFocus()
    return image
}

func pngData(from image: NSImage, pixelSize: Int) -> Data? {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    rep.size = NSSize(width: pixelSize, height: pixelSize)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(
        in: NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize),
        from: .zero,
        operation: .copy,
        fraction: 1.0
    )
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

let fm = FileManager.default
if fm.fileExists(atPath: iconsetDir) {
    try? fm.removeItem(atPath: iconsetDir)
}
try fm.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)

for (size, name) in sizes {
    let img = drawIcon(pixelSize: size)
    guard let data = pngData(from: img, pixelSize: size) else {
        FileHandle.standardError.write("Failed to render size \(size)\n".data(using: .utf8)!)
        exit(1)
    }
    let outPath = (iconsetDir as NSString).appendingPathComponent(name)
    try data.write(to: URL(fileURLWithPath: outPath))
}

let task = Process()
task.launchPath = "/usr/bin/iconutil"
task.arguments = ["-c", "icns", iconsetDir, "-o", icnsOut]
try task.run()
task.waitUntilExit()

try? fm.removeItem(atPath: (iconsetDir as NSString).deletingLastPathComponent)

print("Built \(icnsOut)")
