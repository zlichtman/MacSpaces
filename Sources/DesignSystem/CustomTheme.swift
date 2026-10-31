import SwiftUI
import AppKit
import ImageIO
import UniformTypeIdentifiers

/// How the Custom theme fills the Nook.
enum CustomThemeStyle: String, CaseIterable, Identifiable {
    case solid, twoTone, glass, image
    var id: String { rawValue }
    var title: String {
        switch self {
        case .solid: return "Solid"
        case .twoTone: return "Two-tone"
        case .glass: return "Glass"
        case .image: return "Picture"
        }
    }
    var symbol: String {
        switch self {
        case .solid: return "square.fill"
        case .twoTone: return "square.lefthalf.filled"
        case .glass: return "square.on.square.dashed"
        case .image: return "photo"
        }
    }
}

/// The one Custom theme: a background and an accent (`CustomThemeColors`, the same keys
/// Custom always used), plus a style that defaults to Solid, so a saved Custom looks as it did.
/// Each style keeps its own background and accent (`savedKey`): switching style stores the
/// one you leave and brings back the one you return to, and a style nobody has set up yet
/// starts on its default (`Defaults`), which Reset returns to.
/// Two-tone adds a second colour that the background fades into; Glass turns the
/// background into a tint over the desktop with a strength and an optional blur;
/// Picture shows your own image, copied into Application Support, with colours taken from it.
enum CustomTheme {
    static let styleKey = "theme.custom.style"
    static let secondKey = "theme.custom.second"
    static let imageKey = "theme.custom.image"
    static let defaultSecond = Defaults.twoTone.second!
    /// From fully clear (0, the old Clear) to nearly solid.
    static let strengthRange = 0.0...0.85

    static var style: CustomThemeStyle {
        UserDefaults.standard.string(forKey: styleKey).flatMap(CustomThemeStyle.init(rawValue:)) ?? .solid
    }
    static var second: String {
        CustomThemeColors.clean(UserDefaults.standard.string(forKey: secondKey)) ?? defaultSecond
    }
    static let strengthKey = "theme.custom.strength"
    static let blurKey = "theme.custom.blur"
    static let defaultStrength = Defaults.glass.strength!
    static var glassStrength: Double {
        let saved = UserDefaults.standard.object(forKey: strengthKey) as? Double ?? defaultStrength
        return min(max(saved, strengthRange.lowerBound), strengthRange.upperBound)
    }
    static var glassBlurs: Bool { UserDefaults.standard.object(forKey: blurKey) as? Bool ?? Defaults.glass.blurs! }
    /// Where each style that has been set up keeps its background and accent while another
    /// style shows ("BACKGROUND|ACCENT"). No entry means the style starts on its default.
    static let savedSolidKey = "theme.custom.saved.solid"
    static let savedTwoToneKey = "theme.custom.saved.twoTone"
    static let savedGlassKey = "theme.custom.saved.glass"
    static let savedImageKey = "theme.custom.saved.image"
    static func savedKey(_ style: CustomThemeStyle) -> String {
        switch style {
        case .solid: return savedSolidKey
        case .twoTone: return savedTwoToneKey
        case .glass: return savedGlassKey
        case .image: return savedImageKey
        }
    }
    static func saved(_ style: CustomThemeStyle, in defaults: UserDefaults = .standard) -> (background: String, accent: String)? {
        let parts = (defaults.string(forKey: savedKey(style)) ?? "").components(separatedBy: "|")
        guard parts.count == 2, let background = CustomThemeColors.clean(parts[0]),
              let accent = CustomThemeColors.clean(parts[1]) else { return nil }
        return (background, accent)
    }
    static func save(_ style: CustomThemeStyle, background: String, accent: String, in defaults: UserDefaults = .standard) {
        defaults.set(background + "|" + accent, forKey: savedKey(style))
    }

    /// Each style's starting look. Solid is ink blue with an apricot accent; Two-tone a deep
    /// plum fading to dusk rose with a warm gold; Glass exactly the old Smoke preset (its
    /// tint, accent, 50% strength and blur); Picture starts as Solid until a picture
    /// gives it colours.
    struct Defaults {
        let background: String
        let accent: String
        var second: String? = nil
        var strength: Double? = nil
        var blurs: Bool? = nil
        static let solid = Defaults(background: "121A2B", accent: "FFB077")
        static let twoTone = Defaults(background: "22122E", accent: "FFC07A", second: "7A3558")
        static let glass = Defaults(background: "0B0B0D", accent: "B9BCC6", strength: 0.50, blurs: true)
        static func of(_ style: CustomThemeStyle) -> Defaults {
            switch style {
            case .solid, .image: return solid
            case .twoTone: return twoTone
            case .glass: return glass
            }
        }
    }

    /// The fallbacks 3.35 and 3.36 used for unset keys, before each style had a default.
    enum Legacy {
        static let background = "1B2230", accent = "7C9CFF", second = "3A2A4F"
        static let strength = 0.35, blurs = true
    }

    /// Once, for anyone who has used Custom before the per-style defaults: writes the
    /// values they see now for every unset key (so the new fallbacks never reach them), and
    /// records their colours for the style in use and every style they had set up (a second
    /// colour for Two-tone, a strength or blur for Glass, a picture), so each opens exactly
    /// as it did. Runs while no style has saved colours; nobody who never used Custom is touched.
    static func migrateStyleDefaults(_ defaults: UserDefaults, family: String?) {
        guard CustomThemeStyle.allCases.allSatisfy({ defaults.object(forKey: savedKey($0)) == nil }) else { return }
        let keys = [CustomThemeColors.backgroundKey, CustomThemeColors.accentKey, styleKey, secondKey, strengthKey, blurKey, imageKey]
        guard family == "custom" || keys.contains(where: { defaults.object(forKey: $0) != nil }) else { return }
        let background = CustomThemeColors.clean(defaults.string(forKey: CustomThemeColors.backgroundKey)) ?? Legacy.background
        let accent = CustomThemeColors.clean(defaults.string(forKey: CustomThemeColors.accentKey)) ?? Legacy.accent
        var setUp: Set<CustomThemeStyle> = [defaults.string(forKey: styleKey).flatMap(CustomThemeStyle.init(rawValue:)) ?? .solid]
        if defaults.object(forKey: secondKey) != nil { setUp.insert(.twoTone) }
        if defaults.object(forKey: strengthKey) != nil || defaults.object(forKey: blurKey) != nil { setUp.insert(.glass) }
        if defaults.object(forKey: imageKey) != nil { setUp.insert(.image) }
        defaults.set(background, forKey: CustomThemeColors.backgroundKey)
        defaults.set(accent, forKey: CustomThemeColors.accentKey)
        if CustomThemeColors.clean(defaults.string(forKey: secondKey)) == nil { defaults.set(Legacy.second, forKey: secondKey) }
        if !(defaults.object(forKey: strengthKey) is Double) { defaults.set(Legacy.strength, forKey: strengthKey) }
        if !(defaults.object(forKey: blurKey) is Bool) { defaults.set(Legacy.blurs, forKey: blurKey) }
        for style in setUp { save(style, background: background, accent: accent, in: defaults) }
    }

    /// Deletes the copied picture (the app's own copy in `imageFolder`; never the original).
    static func removeImageFiles() {
        let folder = imageFolder
        DispatchQueue.global(qos: .utility).async {
            for file in (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [] {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    /// The picture's file name inside `imageFolder`, if one was chosen.
    static var imageName: String? { UserDefaults.standard.string(forKey: imageKey) }
    static var imageURL: URL? { imageName.map { imageFolder.appendingPathComponent($0) } }

    /// Application Support/<bundle id>/Backgrounds: the app's own copy, so the original
    /// can move or go and nothing needs a bookmark or a permission later.
    static var imageFolder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent(Bundle.main.bundleIdentifier ?? "dev.opensource.MacSpaces", isDirectory: true)
            .appendingPathComponent("Backgrounds", isDirectory: true)
    }

    /// Copies the chosen picture into `imageFolder` as a JPEG at most 2400 pixels wide
    /// and reads a background and an accent from it. Runs off the main thread; nil when
    /// the file isn't an image.
    static func importImage(from source: URL) -> (name: String, background: String, accent: String)? {
        guard let input = CGImageSourceCreateWithURL(source as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(input, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: 2400,
              ] as CFDictionary) else { return nil }
        let folder = imageFolder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = "background-\(UUID().uuidString.prefix(8)).jpg"
        let url = folder.appendingPathComponent(name)
        guard let output = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(output, image, [kCGImageDestinationLossyCompressionQuality: 0.86] as CFDictionary)
        guard CGImageDestinationFinalize(output) else { return nil }
        // Only the newest copy is kept.
        for old in (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        where old.lastPathComponent != name { try? FileManager.default.removeItem(at: old) }
        let colours = palette(from: image)
        return (name, colours.background, colours.accent)
    }

    /// A dark background in the picture's overall hue (the Nook is always dark) and its
    /// strongest colour as the accent, lifted until it reads at 3:1 on that background.
    static func palette(from image: CGImage) -> (background: String, accent: String) {
        let side = 32
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drew: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8,
                                          bytesPerRow: side * 4, space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drew else { return (CustomThemeColors.defaultBackground, CustomThemeColors.defaultAccent) }
        var sum = (0.0, 0.0, 0.0)
        var bins = [(weight: Double, r: Double, g: Double, b: Double)](repeating: (0, 0, 0, 0), count: 12)
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let r = Double(pixels[i]) / 255, g = Double(pixels[i + 1]) / 255, b = Double(pixels[i + 2]) / 255
            sum.0 += r; sum.1 += g; sum.2 += b
            let maxC = max(r, g, b), minC = min(r, g, b), delta = maxC - minC
            guard maxC > 0.2, delta / max(maxC, 0.001) > 0.25 else { continue }
            var hue: Double
            if maxC == r { hue = (g - b) / delta } else if maxC == g { hue = (b - r) / delta + 2 } else { hue = (r - g) / delta + 4 }
            hue = (hue / 6).truncatingRemainder(dividingBy: 1); if hue < 0 { hue += 1 }
            let weight = (delta / maxC) * maxC
            let bin = min(11, Int(hue * 12))
            bins[bin].weight += weight; bins[bin].r += r * weight; bins[bin].g += g * weight; bins[bin].b += b * weight
        }
        let count = Double(side * side)
        let average = hex(sum.0 / count, sum.1 / count, sum.2 / count)
        // Darken the average toward black until it sits where the built-in dark themes do.
        var background = average
        var step = 0.0
        while CustomThemeColors.luminance(background) > 0.018, step < 1 {
            step += 0.05
            background = mix(average, "000000", step)
        }
        var accent = "E8E8E8"
        if let best = bins.max(by: { $0.weight < $1.weight }), best.weight > 1 {
            let base = hex(best.r / best.weight, best.g / best.weight, best.b / best.weight)
            accent = base
            var lift = 0.0
            while CustomThemeColors.contrast(accent, background) < 3, lift < 1 {
                lift += 0.05
                accent = mix(base, "FFFFFF", lift)
            }
        }
        return (background, accent)
    }

    private static func hex(_ r: Double, _ g: Double, _ b: Double) -> String {
        String(format: "%02X%02X%02X", Int((min(1, max(0, r)) * 255).rounded()),
               Int((min(1, max(0, g)) * 255).rounded()), Int((min(1, max(0, b)) * 255).rounded()))
    }

    private static func mix(_ a: String, _ b: String, _ t: Double) -> String {
        func parts(_ hex: String) -> (Double, Double, Double) {
            let v = UInt32(hex, radix: 16) ?? 0
            return (Double((v >> 16) & 255) / 255, Double((v >> 8) & 255) / 255, Double(v & 255) / 255)
        }
        let x = parts(a), y = parts(b)
        return hex(x.0 + (y.0 - x.0) * t, x.1 + (y.1 - x.1) * t, x.2 + (y.2 - x.2) * t)
    }
}

/// The Custom picture, decoded once off the main thread at most 1800 pixels wide, like
/// the scene photos; superseded loads are dropped.
@MainActor
final class CustomBackgroundImage: ObservableObject {
    static let shared = CustomBackgroundImage()
    @Published private(set) var image: CGImage?
    private var loaded: String?
    private let queue = DispatchQueue(label: "dev.opensource.MacSpaces.custom-background", qos: .userInitiated)

    /// Loads the current picture when it changed; cheap to call from a view's task.
    func prepare() {
        let name = CustomTheme.imageName
        guard name != loaded else { return }
        loaded = name
        image = nil
        guard let name, let url = CustomTheme.imageURL else { return }
        queue.async { [weak self] in
            let decoded: CGImage? = autoreleasepool {
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
                return CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: 1800,
                    kCGImageSourceShouldCacheImmediately: true,
                ] as CFDictionary)
            }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.loaded == name else { return }
                self.image = decoded
            }
        }
    }
}

/// What Custom adds over its background inside the Nook: Two-tone's second colour
/// fading in from the top corner, or the picture, quiet in the middle like the scene
/// photos. Solid and Glass add nothing.
struct CustomBackdropLayer: View {
    @ObservedObject private var theme = ThemeStore.shared
    @ObservedObject private var picture = CustomBackgroundImage.shared

    var body: some View {
        Group {
            switch theme.customStyle {
            case .twoTone:
                LinearGradient(colors: [Color(themeHex: theme.customThemeSecond) ?? .clear, .clear],
                               startPoint: .topTrailing, endPoint: .bottomLeading)
            case .image:
                if let image = picture.image {
                    Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: .fill)
                        .opacity(0.62)
                        .mask(EllipticalGradient(colors: [.black.opacity(0.45), .black], center: .center,
                                                 startRadiusFraction: 0.05, endRadiusFraction: 0.75))
                }
            case .solid, .glass:
                EmptyView()
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: theme.customImageName) { picture.prepare() }
    }
}
