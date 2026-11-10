import AppKit
import ImageIO
import SwiftUI

/// The Folio page's Colors: swatches saved from pasted hex codes, the colour picker or a
/// picture's dominant colours (Save Colors). Kept in `folio-swatches.json` beside the marks,
/// written on `ShelfDisk.queue` a second after the last change; never UserDefaults.
@MainActor
final class FolioSwatches: ObservableObject {
    static let shared = FolioSwatches()
    @Published private(set) var book = FolioSwatchBook()
    /// The Undo bar's text while the last removal can be undone.
    @Published private(set) var undoText: String?
    /// Pictures whose colours are being read.
    @Published private(set) var reading: Set<URL> = []
    private var removed: [(index: Int, item: FolioSwatch)] = []
    private var undoWork: DispatchWorkItem?
    private var saveWork: DispatchWorkItem?
    private var loaded = false
    private var savesDisabled = false
    private let file = FolioStorage.url("folio-swatches.json")
    /// One picture at a time, at utility priority.
    nonisolated private static let worker = DispatchQueue(label: "dev.opensource.MacSpaces.folio-palette", qos: .utility)

    init() {
        let file = self.file
        ShelfDisk.queue.async {
            let saved = FolioStorage.read(FolioSwatchBook.self, from: file)
            Task { @MainActor [weak self, saved] in
                guard let self else { return }
                // Colours saved while the file loaded stay in front.
                var book = saved ?? FolioSwatchBook()
                for swatch in self.book.swatches.reversed() { book.add([swatch.hex], source: swatch.source, now: swatch.added) }
                self.book = book
                self.loaded = true
            }
        }
    }

    /// Saves colours at the front. Returns how many.
    @discardableResult
    func add(_ hexes: [String], source: String) -> Int {
        let count = book.add(hexes, source: source, now: Date())
        if count > 0 { scheduleSave() }
        return count
    }

    /// A colour from the colour picker (or any app that copies one).
    @discardableResult
    func add(_ color: NSColor, source: String = "Color picker") -> Int {
        guard let hex = Self.hex(of: color) else { return 0 }
        return add([hex], source: source)
    }

    nonisolated static func hex(of color: NSColor) -> String? {
        guard let srgb = color.usingColorSpace(.sRGB) else { return nil }
        return FolioHex.hex(red: Double(srgb.redComponent), green: Double(srgb.greenComponent), blue: Double(srgb.blueComponent))
    }

    func remove(_ ids: Set<UUID>) {
        let gone = book.remove(ids)
        guard !gone.isEmpty else { return }
        removed = gone
        undoText = gone.count == 1 ? "Removed \(gone[0].item.hex)" : "Removed \(gone.count) colors"
        undoWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            withAnimation(Design.spring()) { self?.undoText = nil }
            self?.removed = []
        }
        undoWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + ShelfStore.undoSeconds, execute: work)
        scheduleSave()
    }

    func removeAll() { remove(Set(book.swatches.map(\.id))) }

    func undo() {
        guard !removed.isEmpty else { return }
        book.restore(removed)
        removed = []
        undoWork?.cancel(); undoText = nil
        scheduleSave()
    }

    func copy(_ swatch: FolioSwatch, asRGB: Bool = false) {
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(asRGB ? FolioHex.rgbText(swatch.hex) : swatch.hex, forType: .string)
    }

    /// Save Colors: a picture's dominant colours, read off the main thread (a 96-pixel
    /// thumbnail on one utility worker), saved as swatches named for it. Returns how many.
    func saveColors(from url: URL) async -> Int {
        guard !reading.contains(url) else { return 0 }
        reading.insert(url)
        defer { reading.remove(url) }
        let hexes = await withCheckedContinuation { (continuation: CheckedContinuation<[String], Never>) in
            Self.worker.async { continuation.resume(returning: Self.dominantColors(url)) }
        }
        return add(hexes, source: TrayFiles.displayName(url.lastPathComponent))
    }

    nonisolated static func dominantColors(_ url: URL) -> [String] {
        let options = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 96,
                       kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return [] }
        let width = image.width, height = image.height
        guard width > 0, height > 0, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return [] }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { memory -> Bool in
            guard let context = CGContext(data: memory.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? FolioPalette.dominant(rgba: pixels) : []
    }

    private func scheduleSave() {
        guard !savesDisabled else { return }
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.save() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    private func save() {
        guard loaded else { scheduleSave(); return }
        guard !savesDisabled else { return }
        let book = self.book, file = self.file
        ShelfDisk.queue.async { FolioStorage.write(book, to: file) }
    }

#if DEBUG
    /// Check renders: these swatches, never saved.
    func setPreview(_ swatches: [(hex: String, source: String)]) {
        savesDisabled = true
        saveWork?.cancel()
        var book = FolioSwatchBook()
        for swatch in swatches.reversed() { book.add([swatch.hex], source: swatch.source, now: Date()) }
        self.book = book
        loaded = true
    }
#endif
}

/// The Colors place: every swatch, newest first. A click copies the hex; the menu copies RGB or
/// removes it.
struct FolioColorsGrid: View {
    let terms: [String]
    @ObservedObject var swatches = FolioSwatches.shared
    @Binding var isDropTargeted: Bool
    let drop: ([NSItemProvider]) -> Bool
    @ObservedObject var theme = ThemeStore.shared

    var body: some View {
        let shown = swatches.book.matching(terms)
        Group {
            if swatches.book.swatches.isEmpty {
                FolioQuietEmpty(symbol: "paintpalette", title: "No colors yet",
                                detail: "Paste hex codes like #2E5E4E or a palette, drop a color from the color picker, or right-click a picture for Save Colors.")
            } else if shown.isEmpty {
                FolioQuietEmpty(symbol: "magnifyingglass", title: "No matching colors", detail: "Search reads hex codes, color names and where each came from.")
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 62, maximum: 92), spacing: 8)], alignment: .leading, spacing: 8) {
                        ForEach(shown) { swatch in
                            FolioSwatchTile(swatch: swatch)
                        }
                    }
                    .padding(2)
                    .padding(.bottom, 12)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(theme.notch.accent, lineWidth: 2).opacity(isDropTargeted ? 1 : 0)
        }
        .onDrop(of: FolioDrops.types, isTargeted: $isDropTargeted, perform: drop)
    }
}

private struct FolioSwatchTile: View {
    let swatch: FolioSwatch
    @ObservedObject private var theme = ThemeStore.shared
    @State private var hovering = false
    @State private var copied = false

    var body: some View {
        let rgb = FolioHex.rgb(swatch.hex) ?? (red: 0, green: 0, blue: 0)
        let light = FolioHex.isLight(swatch.hex)
        let corner = RoundedRectangle(cornerRadius: 9, style: .continuous)
        VStack(spacing: 4) {
            corner
                .fill(Color(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue, opacity: 1))
                .overlay { corner.strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5) }
                .overlay {
                    if copied {
                        Label("Copied", systemImage: "checkmark").font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(light ? Color.black : Color.white)
                            .transition(.opacity)
                    }
                }
                .frame(height: 46)
                .scaleEffect(hovering && !theme.reduceMotion ? 1.03 : 1)
            Text(swatch.hex).font(.system(size: 9.5, weight: .semibold, design: .monospaced)).lineLimit(1)
            Text(swatch.source).font(.system(size: 8.5)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
        }
        .overlay(alignment: .topTrailing) {
            if hovering {
                Button { withAnimation(Design.spring()) { FolioSwatches.shared.remove([swatch.id]) } } label: {
                    Image(systemName: "xmark").font(.system(size: 7, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 15, height: 15)
                        .background(Color.black.opacity(0.6), in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Remove this color")
                .padding(3)
            }
        }
        .animation(Design.hoverAnimation, value: hovering)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { copy(asRGB: false) }
        .contextMenu {
            Button("Copy \(swatch.hex)") { copy(asRGB: false) }
            Button("Copy \(FolioHex.rgbText(swatch.hex))") { copy(asRGB: true) }
            Divider()
            Button("Remove", role: .destructive) { FolioSwatches.shared.remove([swatch.id]) }
        }
        .help("\(swatch.hex) · \(FolioHex.rgbText(swatch.hex)) · from \(swatch.source). Click to copy.")
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("\(FolioHex.name(swatch.hex)) \(swatch.hex)")
    }

    private func copy(asRGB: Bool) {
        FolioSwatches.shared.copy(swatch, asRGB: asRGB)
        withAnimation(.easeOut(duration: 0.15)) { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { withAnimation { copied = false } }
    }
}
