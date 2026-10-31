#!/usr/bin/env swift
// Writes a small JPEG of each theme photo for the Settings theme cards:
// Sources/Resources/ThemeCards/<asset>-card.jpg, 360 pixels wide (a card at 2x).
// Decoding a full 1586-pixel HEIC per card took about 40 ms on the owner's Mac (over a
// second for a drawer); a card JPEG decodes in about half a millisecond.
//
//   swift Scripts/build-theme-cards.swift
import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let assets = root.appendingPathComponent("Sources/Resources/Assets.xcassets")
let output = root.appendingPathComponent("Sources/Resources/ThemeCards")
try? FileManager.default.removeItem(at: output)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
var total = 0
for folder in try FileManager.default.contentsOfDirectory(atPath: assets.path).sorted()
where folder.hasPrefix("Theme") && folder.hasSuffix(".imageset") {
    let name = String(folder.dropLast(".imageset".count))
    let set = assets.appendingPathComponent(folder)
    guard let file = try FileManager.default.contentsOfDirectory(atPath: set.path).first(where: { $0 != "Contents.json" }),
          let source = CGImageSourceCreateWithURL(set.appendingPathComponent(file) as CFURL, nil),
          let full = CGImageSourceCreateImageAtIndex(source, 0, nil) else { continue }
    let width = 360, height = Int((Double(width) * Double(full.height) / Double(full.width)).rounded())
    guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { continue }
    context.interpolationQuality = .high
    context.draw(full, in: CGRect(x: 0, y: 0, width: width, height: height))
    let url = output.appendingPathComponent("\(name)-card.jpg")
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, [kCGImageDestinationLossyCompressionQuality: 0.72] as CFDictionary)
    CGImageDestinationFinalize(destination)
    total += (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
}
print("Theme cards: \(total / 1024) KB in \(output.path)")
