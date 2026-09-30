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

// Full-bleed black art. macOS 26 applies its own continuous-corner mask to
// icons that fill the canvas; art with its own rounded plate and a
// transparent margin is treated as legacy and boxed inside a grey tile.
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
