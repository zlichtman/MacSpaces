import Foundation

/// How a theme sits on the Nook, whatever its colours: how see-through it is, with or without
/// blur, a fade to a second colour, and a picture. Terminal themes share one, kept as you move
/// between them, and it starts empty so they look as they always have. Custom has its own, read
/// from its old style until it's first changed here.
struct ThemeLook: Codable, Equatable {
    /// 0 is solid, 1 is nothing behind the content at all.
    var seeThrough = 0.0
    var blur = true
    var fade = false
    var second = CustomTheme.defaultSecond
    var picture = false

    /// How strongly the theme's colour tints what's behind it; nil when solid.
    var tint: Double? { seeThrough > 0 ? 1 - seeThrough : nil }
    var blurs: Bool { blur && tint != nil }

    static let terminalKey = "theme.look"
    static let customKey = "theme.look.custom"

    private static var terminalCache: (data: Data?, look: ThemeLook)?
    private static var customCache: (data: Data?, look: ThemeLook?)?

    static var terminal: ThemeLook {
        get {
            let data = UserDefaults.standard.data(forKey: terminalKey)
            if let terminalCache, terminalCache.data == data { return terminalCache.look }
            let look = data.flatMap { try? JSONDecoder().decode(ThemeLook.self, from: $0) } ?? ThemeLook()
            terminalCache = (data, look)
            return look
        }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: terminalKey) }
    }

    /// Custom's: changed here it's saved; until then it's what its old style drew.
    static var custom: ThemeLook {
        get {
            let data = UserDefaults.standard.data(forKey: customKey)
            if let customCache, customCache.data == data, let look = customCache.look { return look }
            if let data, let look = try? JSONDecoder().decode(ThemeLook.self, from: data) {
                customCache = (data, look)
                return look
            }
            return fromCustomStyle()
        }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: customKey) }
    }

    /// Forgets Custom's own, so it follows its old style again (a style chosen from code).
    static func followCustomStyle() {
        UserDefaults.standard.removeObject(forKey: customKey)
        customCache = nil
    }

    /// Forgets both saved looks, for Reset: the Terminal themes' goes back to empty and Custom's
    /// follows its style again.
    static func forgetSaved() {
        UserDefaults.standard.removeObject(forKey: terminalKey)
        terminalCache = nil
        followCustomStyle()
    }

    static func fromCustomStyle() -> ThemeLook {
        var look = ThemeLook()
        look.second = CustomTheme.second
        look.blur = CustomTheme.glassBlurs
        switch CustomTheme.style {
        case .solid: break
        case .twoTone: look.fade = true
        case .glass: look.seeThrough = 1 - CustomTheme.glassStrength
        case .image: look.picture = true
        }
        return look
    }
}
