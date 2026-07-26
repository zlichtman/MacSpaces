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

// A flat, full-bleed black plate. The transparent outer margin keeps the icon
// clean in Finder without the square image edge that the previous artwork had.
let plate = NSBezierPath(
    roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896),
    xRadius: 206,
    yRadius: 206
)
NSColor.black.setFill()
plate.fill()

// Two surfaces, reduced to a direct monochrome "//" mark. There are no
// gradients, shadows, highlights, or faux-device details.
NSColor.white.setStroke()
for centerX in [402.0, 622.0] {
    let slash = NSBezierPath()
    slash.lineWidth = 96
    slash.lineCapStyle = .round
    slash.move(to: NSPoint(x: centerX - 92, y: 292))
    slash.line(to: NSPoint(x: centerX + 92, y: 732))
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
