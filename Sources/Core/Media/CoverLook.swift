import AppKit

/// A cover reduced to an 8×8 colour thumbnail, to tell whether two images are the
/// same picture. Covers arrive more than once per song (Spotify's 300 px copy, then
/// its 640 px one; a player's own copy after a downloaded one), and an album played
/// in order repeats its cover on every skip; those should swap in place, not fade.
struct CoverLook: Equatable {
    static let side = 8
    /// Drawn at this size first, then averaged in blocks: one large step down aliases
    /// on detailed covers, so the same picture at two sizes could look different.
    static let drawn = 64
    /// Mean difference per colour channel (of 255) still counted as the same picture.
    /// Real covers at 300 and 640 px differ by under 1; different covers by 40 or more.
    static let tolerance = 6.0

    let samples: [UInt8]

    init?(_ image: NSImage) {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        self.init(cg)
    }

    init?(_ image: CGImage) {
        let drawn = Self.drawn, side = Self.side, block = drawn / side
        var pixels = [UInt8](repeating: 0, count: drawn * drawn * 4)
        let ok: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: drawn, height: drawn, bitsPerComponent: 8,
                                          bytesPerRow: drawn * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: drawn, height: drawn))
            return true
        }
        guard ok else { return nil }
        var samples = [UInt8]()
        samples.reserveCapacity(side * side * 3)
        for y in 0..<side {
            for x in 0..<side {
                for channel in 0..<3 {
                    var total = 0
                    for row in y * block..<(y + 1) * block {
                        for column in x * block..<(x + 1) * block { total += Int(pixels[(row * drawn + column) * 4 + channel]) }
                    }
                    samples.append(UInt8(total / (block * block)))
                }
            }
        }
        self.samples = samples
    }

    func matches(_ other: CoverLook) -> Bool {
        guard samples.count == other.samples.count else { return false }
        let total = zip(samples, other.samples).reduce(0) { $0 + abs(Int($1.0) - Int($1.1)) }
        return Double(total) / Double(samples.count) <= Self.tolerance
    }

    /// Whether two covers show the same picture (the same object always does).
    static func same(_ a: NSImage?, _ b: NSImage?) -> Bool {
        guard let a, let b else { return a == nil && b == nil }
        if a === b { return true }
        guard let first = look(of: a), let second = look(of: b) else { return false }
        return first.matches(second)
    }

    /// Each cover is reduced once, however many views compare it.
    static func look(of image: NSImage) -> CoverLook? {
        if let known = looks.object(forKey: image) { return known.look }
        let look = CoverLook(image)
        looks.setObject(Known(look), forKey: image)
        return look
    }

    private final class Known {
        let look: CoverLook?
        init(_ look: CoverLook?) { self.look = look }
    }

    private static let looks: NSCache<NSImage, Known> = {
        let cache = NSCache<NSImage, Known>()
        cache.countLimit = 16
        return cache
    }()
}
