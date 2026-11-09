#!/usr/bin/env swift

import AppKit

let projectRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let outputPath = CommandLine.arguments.dropFirst().first
    ?? "Sources/Resources/MacSpacesIcon-master.png"
let outputURL = URL(fileURLWithPath: outputPath, relativeTo: projectRoot)
let canvas = NSSize(width: 1024, height: 1024)

/// The notch moon: a solid disc with the notch cut out of its top, in the manner
/// of 1970s symbol marks. Flat white only. Drawn on a 100-unit grid (y down)
/// and placed in the middle of the canvas.
func drawMark() {
    NSColor.white.setFill()
    let scale: CGFloat = 5.6, origin = NSPoint(x: 512 - 50 * scale, y: 512 + 50 * scale)
    func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: origin.x + x * scale, y: origin.y - y * scale) }
    // The notch is 32 wide and 28 deep; its sides meet the disc where x = 34 and 66.
    let (notchLeft, notchRight, floor, corner): (CGFloat, CGFloat, CGFloat, CGFloat) = (34, 66, 28, 8)
    let rim: CGFloat = 50 - CGFloat(2500 - 16 * 16).squareRoot()
    let angle = atan2(50 - rim, notchLeft - 50) * 180 / .pi
    let moon = NSBezierPath()
    moon.move(to: p(notchLeft, rim))
    moon.appendArc(withCenter: p(50, 50), radius: 50 * scale, startAngle: angle, endAngle: 180 - angle, clockwise: false)
    moon.line(to: p(notchRight, floor - corner))
    moon.curve(to: p(notchRight - corner, floor), controlPoint1: p(notchRight, floor - corner * 0.45), controlPoint2: p(notchRight - corner * 0.45, floor))
    moon.line(to: p(notchLeft + corner, floor))
    moon.curve(to: p(notchLeft, floor - corner), controlPoint1: p(notchLeft + corner * 0.45, floor), controlPoint2: p(notchLeft, floor - corner * 0.45))
    moon.close()
    moon.fill()
}

func bitmap() -> NSBitmapImageRep {
    NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    )!
}

func render(to url: URL, black: Bool, mark: Bool) throws {
    let rep = bitmap()
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.shouldAntialias = true
    if black {
        NSColor.black.setFill()
        NSRect(origin: .zero, size: canvas).fill()
    }
    if mark { drawMark() }
    NSGraphicsContext.restoreGraphicsState()
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try rep.representation(using: .png, properties: [:])!.write(to: url, options: .atomic)
    print(url.path)
}

// Full-bleed black art for MacSpacesIcon-master.png (Settings rounds it).
try render(to: outputURL, black: true, mark: true)

// The app icon itself is Sources/Resources/AppIcon.icon: an Icon Composer file
// whose layers are the mark over a black image. The black is an image layer,
// not the icon fill, because macOS 26 lightens a solid fill to dark grey.
// macOS 26 draws the file natively; Xcode generates the rounded icon that
// macOS 13–15 use.
let assets = URL(fileURLWithPath: "Sources/Resources/AppIcon.icon/Assets", relativeTo: projectRoot)
try render(to: assets.appendingPathComponent("mark.png"), black: false, mark: true)
try render(to: assets.appendingPathComponent("black.png"), black: true, mark: false)
