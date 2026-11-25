import AppKit
import SwiftUI

/// One colour, opened from a dot: a hex field, a colour wheel with a brightness slider, and
/// Reset once it has been changed. Every change shows at once.
struct ThemeColourEditor: View {
    let title: String
    /// The colour now, as six hex digits.
    let current: () -> String?
    let apply: (String) -> Void
    var isEdited: () -> Bool = { false }
    var reset: () -> Void = {}
    @ObservedObject private var library = GhosttyLibrary.shared
    @ObservedObject private var theme = ThemeStore.shared
    @State private var hex = ""
    @State private var hue: CGFloat = 0
    @State private var saturation: CGFloat = 0
    @State private var brightness: CGFloat = 1
    @State private var invalid = false

    /// One colour of a theme in the list.
    init(item: TerminalThemeItem, slot: ThemeColourSlot) {
        title = slot.title
        current = { GhosttyLibrary.shared.current(item).map { slot.hex(in: $0) } }
        apply = { GhosttyLibrary.shared.recolour(item, slot, hex: $0) }
        isEdited = { GhosttyLibrary.shared.isEdited(item) }
        reset = { GhosttyLibrary.shared.resetColours(item) }
    }

    init(title: String, current: @escaping () -> String?, apply: @escaping (String) -> Void) {
        self.title = title
        self.current = current
        self.apply = apply
    }

    private static let wheel: CGFloat = 132
    private static let knob: CGFloat = 12

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(.system(size: 12, weight: .semibold))
                Spacer(minLength: 8)
                if isEdited() {
                    Button("Reset") { reset(); load() }
                        .buttonStyle(.settings(.quiet))
                }
            }
            colourWheel
            Slider(value: Binding(get: { brightness }, set: { brightness = $0; applyWheel() }), in: 0...1)
                .accessibilityLabel("Brightness")
            TextField("Hex", text: $hex)
                .settingsTextField()
                .font(.system(size: 12, design: .monospaced))
                .onSubmit(applyHex)
                .onChange(of: hex) { _ in applyHex() }
                .accessibilityLabel("\(title) hex colour")
            if invalid {
                Text("Enter six hex digits").font(.caption).foregroundStyle(.orange)
            }
        }
        .padding(12)
        .frame(width: Self.wheel + 24)
        .foregroundStyle(theme.settingsForeground)
        .tint(theme.settings.accent)
        .background(theme.settings.tile.padding(-80))
        .onAppear(perform: load)
    }

    private var colourWheel: some View {
        let side = Self.wheel
        return ZStack {
            Circle().fill(AngularGradient(colors: stride(from: 0.0, through: 1.0, by: 1.0 / 12).map {
                Color(hue: $0, saturation: 1, brightness: 1)
            }, center: .center))
            Circle().fill(RadialGradient(colors: [.white, .white.opacity(0)], center: .center, startRadius: 0, endRadius: side / 2))
            Circle().fill(Color.black.opacity(1 - brightness))
            Circle()
                .strokeBorder(Color.white, lineWidth: 2)
                .background(Circle().fill(Color(hue: hue, saturation: saturation, brightness: brightness)))
                .frame(width: Self.knob, height: Self.knob)
                .offset(x: cos(hue * 2 * .pi) * saturation * side / 2, y: sin(hue * 2 * .pi) * saturation * side / 2)
                .allowsHitTesting(false)
        }
        .frame(width: side, height: side)
        .contentShape(Circle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
            let x = drag.location.x - side / 2, y = drag.location.y - side / 2
            var angle = atan2(y, x) / (2 * .pi)
            if angle < 0 { angle += 1 }
            hue = angle
            saturation = min(1, hypot(x, y) / (side / 2))
            applyWheel()
        })
        .accessibilityLabel("Colour wheel")
    }

    private func load() {
        guard let value = current() else { return }
        hex = "#" + value
        adopt(value)
        invalid = false
    }

    /// The wheel follows a typed colour.
    private func adopt(_ value: String) {
        guard let colour = TerminalPillColours.colour(value).flatMap({ NSColor(cgColor: $0)?.usingColorSpace(.sRGB) }) else { return }
        hue = colour.hueComponent
        saturation = colour.saturationComponent
        brightness = colour.brightnessComponent
    }

    private func applyWheel() {
        let colour = NSColor(hue: hue, saturation: saturation, brightness: brightness, alpha: 1).usingColorSpace(.sRGB) ?? .white
        let value = String(format: "%02X%02X%02X", Int((colour.redComponent * 255).rounded()),
                           Int((colour.greenComponent * 255).rounded()), Int((colour.blueComponent * 255).rounded()))
        hex = "#" + value
        apply(value)
    }

    private func applyHex() {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# ")).uppercased()
        guard cleaned.count == 6, UInt64(cleaned, radix: 16) != nil else { invalid = hex.count > 7; return }
        invalid = false
        guard current() != cleaned else { return }
        apply(cleaned)
        adopt(cleaned)
    }
}
