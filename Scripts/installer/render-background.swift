#!/usr/bin/env swift
import AppKit

// Draw at 1x and 2x in one TIFF. Finder chooses the native backing scale.
let output = URL(fileURLWithPath: CommandLine.arguments[1])
let mark = NSImage(contentsOfFile: CommandLine.arguments[2])!
let size = NSSize(width: 720, height: 460)
let image = NSImage(size: size)
func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor {
    NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: 1)
}
for scale in [1, 2] {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 720 * scale, pixelsHigh: 460 * scale,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
        NSRect(x: x, y: 460 - y - h, width: w, height: h)
    }
    func text(_ value: String, x: CGFloat, y: CGFloat, font: NSFont, ink: NSColor) {
        (value as NSString).draw(at: NSPoint(x: x, y: 460 - y - font.ascender), withAttributes: [.font: font, .foregroundColor: ink])
    }
    NSColor.white.setFill(); NSBezierPath(rect: rect(0, 0, 720, 460)).fill()
    mark.draw(in: rect(42, 30, 34, 34))
    text("MacSpaces", x: 86, y: 37, font: .systemFont(ofSize: 17, weight: .semibold), ink: color(24, 28, 36))
    text("Install MacSpaces.", x: 44, y: 98, font: .systemFont(ofSize: 36, weight: .bold), ink: color(21, 25, 34))
    text("Drag the app into Applications to get started.", x: 46, y: 151, font: .systemFont(ofSize: 15), ink: color(100, 108, 123))
    for x: CGFloat in [116, 436] {
        color(246, 248, 252).setFill()
        NSBezierPath(roundedRect: rect(x, 213, 168, 151), xRadius: 22, yRadius: 22).fill()
        color(231, 235, 243).setStroke()
        let outline = NSBezierPath(roundedRect: rect(x, 213, 168, 151), xRadius: 22, yRadius: 22)
        outline.lineWidth = 1; outline.stroke()
    }
    color(56, 113, 221).setStroke()
    let arrow = NSBezierPath(); arrow.lineWidth = 2.5; arrow.lineCapStyle = .round; arrow.lineJoinStyle = .round
    arrow.move(to: NSPoint(x: 337, y: 460 - 273)); arrow.line(to: NSPoint(x: 383, y: 460 - 273))
    arrow.move(to: NSPoint(x: 374, y: 460 - 264)); arrow.line(to: NSPoint(x: 383, y: 460 - 273)); arrow.line(to: NSPoint(x: 374, y: 460 - 282)); arrow.stroke()
    color(235, 237, 242).setFill(); NSBezierPath(rect: rect(44, 392, 632, 1)).fill()
    text("Then open MacSpaces from Applications.", x: 45, y: 409, font: .systemFont(ofSize: 13, weight: .medium), ink: color(59, 67, 82))
    text("Eject this installer when you’re done.", x: 45, y: 432, font: .systemFont(ofSize: 11), ink: color(121, 130, 145))
    NSGraphicsContext.restoreGraphicsState()
    image.addRepresentation(rep)
    if scale == 1 { try rep.representation(using: .png, properties: [:])!.write(to: output.deletingPathExtension().appendingPathExtension("png")) }
}
try image.tiffRepresentation!.write(to: output)
