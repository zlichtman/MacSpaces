import SwiftUI
import AppKit

/// Screen color sampler. Click the eyedropper to pick any pixel on screen;
/// the hex value is copied and kept in a small swatch history.
struct ColorPickerWidget: View {
    @StateObject private var model = ColorPickerModel()

    var body: some View {
        VStack(spacing: 6) {
            Button {
                model.pick()
            } label: {
                Image(systemName: "eyedropper.halffull")
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 34, height: 34)
                    .background(.primary.opacity(0.08), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Pick a color from the screen")

            if model.history.isEmpty {
                Text("Pick a color")
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 4) {
                    ForEach(model.history.prefix(4), id: \.self) { hex in
                        Button {
                            model.copy(hex)
                        } label: {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color(hex: hex) ?? .gray)
                                .frame(width: 12, height: 12)
                                .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(.primary.opacity(0.25)))
                        }
                        .buttonStyle(.plain)
                        .help("Copy \(hex)")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

@MainActor
private final class ColorPickerModel: ObservableObject {
    @Published private(set) var history: [String]

    private let defaultsKey = "colorPickerHistory"
    // Retained for the duration of the pick interaction.
    private let sampler = NSColorSampler()

    init() {
        history = UserDefaults.standard.stringArray(forKey: defaultsKey) ?? []
    }

    func pick() {
        sampler.show { [weak self] color in
            guard let self, let color else { return }
            let hex = color.hexString
            Task { @MainActor in
                self.history.removeAll { $0 == hex }
                self.history.insert(hex, at: 0)
                if self.history.count > 8 {
                    self.history.removeLast(self.history.count - 8)
                }
                UserDefaults.standard.set(self.history, forKey: self.defaultsKey)
                self.copy(hex)
            }
        }
    }

    func copy(_ hex: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(hex, forType: .string)
    }
}

private extension NSColor {
    var hexString: String {
        let rgb = usingColorSpace(.sRGB) ?? self
        let r = Int(round(rgb.redComponent * 255))
        let g = Int(round(rgb.greenComponent * 255))
        let b = Int(round(rgb.blueComponent * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

extension Color {
    /// Parses "#RRGGBB".
    init?(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6, let number = UInt64(value, radix: 16) else { return nil }
        self.init(red: Double((number >> 16) & 0xFF) / 255,
                  green: Double((number >> 8) & 0xFF) / 255,
                  blue: Double(number & 0xFF) / 255)
    }
}
