#!/usr/bin/env swift

import AppKit

let projectRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let outputPath = CommandLine.arguments.dropFirst().first
    ?? "Sources/Resources/MacSpacesIcon-master.png"
let outputURL = URL(fileURLWithPath: outputPath, relativeTo: projectRoot)
let canvas = NSSize(width: 1024, height: 1024)

let image = NSImage(size: canvas)
image.lockFocus()
guard let context = NSGraphicsContext.current?.cgContext else {
    fatalError("Could not create icon context")
}
context.setAllowsAntialiasing(true)
context.setShouldAntialias(true)

// Full-bleed black art for MacSpacesIcon-master.png (Settings rounds it).
// The app icon itself is Sources/Resources/AppIcon.icon: an Icon Composer
// file whose layers (written below) are the slashes over a black image. The
// black is an image layer, not the icon fill, because macOS 26 lightens a
// solid fill to dark grey. macOS 26 draws the file natively; Xcode generates
// the rounded icon macOS 15 uses.
NSColor.black.setFill()
NSRect(origin: .zero, size: canvas).fill()

// A direct monochrome "//" mark. There are no
// gradients, shadows, highlights, or faux-device details.
NSColor.white.setStroke()
for centerX in [397.0, 627.0] {
    let slash = NSBezierPath()
    slash.lineWidth = 100
    slash.lineCapStyle = .round
    slash.move(to: NSPoint(x: centerX - 96, y: 290))
    slash.line(to: NSPoint(x: centerX + 96, y: 734))
    slash.stroke()
}

image.unlockFocus()

guard
    let tiff = image.tiffRepresentation,
    let bitmap = NSBitmapImageRep(data: tiff),
    let png = bitmap.representation(using: .png, properties: [:])
else {
    fatalError("Could not encode app icon")
}

try FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)
try png.write(to: outputURL, options: .atomic)
print(outputURL.path)

// The Icon Composer layer: the same slashes on a transparent canvas.
let layer = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8,
    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
    bytesPerRow: 0, bitsPerPixel: 0
)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: layer)
NSColor.white.setStroke()
for centerX in [397.0, 627.0] {
    let slash = NSBezierPath()
    slash.lineWidth = 100
    slash.lineCapStyle = .round
    slash.move(to: NSPoint(x: centerX - 96, y: 290))
    slash.line(to: NSPoint(x: centerX + 96, y: 734))
    slash.stroke()
}
NSGraphicsContext.restoreGraphicsState()
let layerURL = URL(fileURLWithPath: "Sources/Resources/AppIcon.icon/Assets/slashes.png", relativeTo: projectRoot)
try FileManager.default.createDirectory(at: layerURL.deletingLastPathComponent(), withIntermediateDirectories: true)
try layer.representation(using: .png, properties: [:])!.write(to: layerURL, options: .atomic)
print(layerURL.path)

let background = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8,
    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
    bytesPerRow: 0, bitsPerPixel: 0
)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: background)
NSColor.black.setFill()
NSRect(origin: .zero, size: canvas).fill()
NSGraphicsContext.restoreGraphicsState()
let backgroundURL = layerURL.deletingLastPathComponent().appendingPathComponent("black.png")
try background.representation(using: .png, properties: [:])!.write(to: backgroundURL, options: .atomic)
print(backgroundURL.path)
