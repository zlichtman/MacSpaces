import AppKit
import ImageIO
import QuickLookThumbnailing
import SwiftUI

/// The Folio page's full-size viewer, like Folio's: the selection big inside the page, over the
/// sidebar and grid. ← and → page through the place showing, Z switches Fit and Fill (as does a
/// double-click), L likes it, Space is Quick Look, and Escape or Return goes back to the grid.
/// The grid's thumbnail shows at once; a sharper picture is made off the main thread and
/// dropped if you've paged on. Paging slides a little, or only fades with Reduce Motion.
struct FolioViewer: View {
    let entries: [FolioEntry]
    let index: Int
    /// Shows the file `offset` places along (−1 back, 1 on).
    let page: (Int) -> Void
    let close: () -> Void
    @ObservedObject private var library = FolioIndex.shared
    @ObservedObject private var theme = ThemeStore.shared
    @State private var fill = false
    @State private var sharp: (id: UUID, image: NSImage)?
    @State private var forward = true

    var body: some View {
        let entry = entries[index]
        let preview = entry.store.previews[entry.id]
        let info = entry.store.info[entry.id]
        // The sharp picture made for this file (or kept from before), else the grid's thumbnail.
        let made = sharp?.id == entry.id ? sharp?.image : FolioViewerImages.cached(for: entry.item.url, modified: info?.modified)
        let picture = made ?? (preview?.isContent == true ? preview?.image : nil)
        VStack(spacing: 6) {
            bar(entry)
            GeometryReader { proxy in
                ZStack {
                    Group {
                        if let picture {
                            Image(nsImage: picture).resizable().interpolation(.high)
                                .aspectRatio(contentMode: fill ? .fill : .fit)
                                .frame(width: proxy.size.width, height: proxy.size.height)
                                .clipShape(RoundedRectangle(cornerRadius: fill ? 8 : 6, style: .continuous))
                        } else {
                            card(entry, icon: preview?.image)
                        }
                    }
                    .id(entry.id)
                    .transition(slide)
                    arrows
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { toggleFill() }
            }
        }
        .padding(8)
        .background(theme.notch.surface)
        .background(FolioViewerKeys(handle: key))
        .task(id: entry.id) {
            guard made == nil, !entry.store.offlineIDs.contains(entry.id), info?.isDirectory != true,
                  let image = await FolioViewerImages.image(for: entry.item.url, modified: info?.modified, isImage: info?.isImage == true),
                  !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.15)) { sharp = (entry.id, image) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Viewing \(entry.item.name), \(index + 1) of \(entries.count)")
    }

    /// The name and place in the list, then like, Fit or Fill, Quick Look and close.
    private func bar(_ entry: FolioEntry) -> some View {
        let liked = library.isLiked(entry.item.url)
        return HStack(spacing: 6) {
            Text(entry.item.displayName).font(.system(size: 12, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                .help(entry.item.name)
            Text("\(index + 1) of \(entries.count)").font(.system(size: 10, weight: .medium)).monospacedDigit()
                .foregroundStyle(.secondary).lineLimit(1).fixedSize()
            Spacer(minLength: 6)
            barButton(liked ? "Unlike (L)" : "Like (L)", liked ? "heart.fill" : "heart", tint: liked ? .pink : nil) {
                library.toggleLike([entry.item.url])
            }
            Button(fill ? "Fill" : "Fit") { toggleFill() }
                .buttonStyle(WidgetChipStyle(height: 24))
                .help("Fit the whole picture, or Fill the space (Z)")
            barButton("Quick Look (Space)", "eye") { quickLook(entry) }
            barButton("Back to the grid (Escape)", "xmark") { close() }
        }
        .frame(height: 24)
    }

    private func barButton(_ title: String, _ symbol: String, tint: Color? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint.map(AnyShapeStyle.init) ?? AnyShapeStyle(.secondary))
                .frame(width: 26, height: 24)
                .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(PremiumPressButtonStyle())
        .help(title)
        .accessibilityLabel(title)
    }

    /// A file without a picture of its content: its icon, name and kind, big.
    private func card(_ entry: FolioEntry, icon: NSImage?) -> some View {
        VStack(spacing: 8) {
            if let icon {
                Image(nsImage: icon).resizable().interpolation(.high).scaledToFit().frame(width: 72, height: 72)
            } else {
                Image(systemName: "doc").font(.system(size: 44, weight: .light)).foregroundStyle(.tertiary)
            }
            Text(entry.item.name).font(.system(size: 13, weight: .semibold)).lineLimit(2).multilineTextAlignment(.center)
            Text(entry.store.info[entry.id]?.details ?? "").font(.system(size: 10)).foregroundStyle(.secondary)
            Text("Space opens it in Quick Look").font(.system(size: 10)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    /// Round arrows at the sides, each hidden at its end of the list.
    private var arrows: some View {
        HStack {
            arrow("chevron.left", "Previous (←)", shown: index > 0) { go(-1) }
            Spacer()
            arrow("chevron.right", "Next (→)", shown: index < entries.count - 1) { go(1) }
        }
        .padding(.horizontal, 8)
    }

    private func arrow(_ symbol: String, _ title: String, shown: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Color.black.opacity(0.42), in: Circle())
                .overlay(Circle().strokeBorder(Color.white.opacity(0.22), lineWidth: 0.5))
                .contentShape(Circle())
        }
        .buttonStyle(PremiumPressButtonStyle())
        .help(title)
        .accessibilityLabel(title)
        .opacity(shown ? 1 : 0)
        .disabled(!shown)
    }

    /// The next picture slides in a little from the side it comes from; Reduce Motion fades.
    private var slide: AnyTransition {
        guard !theme.reduceMotion else { return .opacity }
        return .asymmetric(insertion: .opacity.combined(with: .offset(x: forward ? 22 : -22)), removal: .opacity)
    }

    private func go(_ offset: Int) {
        guard entries.indices.contains(index + offset) else { NSSound.beep(); return }
        forward = offset > 0
        withAnimation(theme.reduceMotion ? .easeOut(duration: 0.12) : .easeOut(duration: 0.22)) { page(offset) }
    }

    private func toggleFill() {
        withAnimation(theme.reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.32, dampingFraction: 0.88)) { fill.toggle() }
    }

    private func quickLook(_ entry: FolioEntry) {
        entry.store.select(entry.item)
        entry.store.quickLook()
    }

    private func key(_ event: NSEvent) -> Bool {
        let plain = event.modifierFlags.intersection([.command, .control, .option]).isEmpty
        switch event.keyCode {
        case 123, 126: go(-1)
        case 124, 125: go(1)
        case 53, 36, 76: close()
        case 49: quickLook(entries[index])
        default:
            guard plain, let key = event.charactersIgnoringModifiers?.lowercased() else { return false }
            switch key {
            case "z": toggleFill()
            case "l": library.toggleLike([entries[index].item.url])
            default: return false
            }
        }
        return true
    }
}

/// Takes the keys while the viewer shows, and hands them back to whatever had them before.
struct FolioViewerKeys: NSViewRepresentable {
    let handle: (NSEvent) -> Bool

    func makeNSView(context: Context) -> KeyView { KeyView() }
    func updateNSView(_ view: KeyView, context: Context) { view.handle = handle }

    final class KeyView: NSView {
        var handle: ((NSEvent) -> Bool)?
        private weak var previous: NSResponder?
        override var acceptsFirstResponder: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            DispatchQueue.main.async { [weak self, weak window] in
                guard let self, let window, self.window === window, window.firstResponder !== self else { return }
                self.previous = window.firstResponder
                window.makeFirstResponder(self)
            }
        }

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            if newWindow == nil, let window, window.firstResponder === self {
                if let view = previous as? NSView, view.window === window { window.makeFirstResponder(view) }
                else { window.makeFirstResponder(nil) }
            }
            super.viewWillMove(toWindow: newWindow)
        }

        override func keyDown(with event: NSEvent) {
            if handle?(event) != true { super.keyDown(with: event) }
        }
    }
}

/// Sharper pictures for the viewer: an image read through ImageIO at most `pixels` on its long
/// side (never decoded whole), anything else Quick Look's thumbnail at that size. Made off the
/// main thread, and the last few kept (at most six, 48 MB).
enum FolioViewerImages {
    static let pixels: CGFloat = 1800

    private final class Box: @unchecked Sendable { let image: NSImage; init(_ image: NSImage) { self.image = image } }
    private static let cache: NSCache<NSString, Box> = {
        let cache = NSCache<NSString, Box>()
        cache.countLimit = 6
        cache.totalCostLimit = 48 << 20
        return cache
    }()

    private static func key(_ url: URL, _ modified: Date?) -> NSString {
        (url.standardizedFileURL.path + "|" + String(modified?.timeIntervalSinceReferenceDate ?? 0)) as NSString
    }

    /// A picture already made for this file at this modification date.
    static func cached(for url: URL, modified: Date?) -> NSImage? { cache.object(forKey: key(url, modified))?.image }

    @MainActor
    static func image(for url: URL, modified: Date?, isImage: Bool) async -> NSImage? {
        let key = key(url, modified)
        if let hit = cache.object(forKey: key) { return hit.image }
        let made: Box?
        if isImage {
            made = await Task.detached(priority: .userInitiated) { () -> Box? in
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                      let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                          kCGImageSourceCreateThumbnailFromImageAlways: true,
                          kCGImageSourceCreateThumbnailWithTransform: true,
                          kCGImageSourceThumbnailMaxPixelSize: pixels,
                      ] as CFDictionary) else { return nil }
                return Box(NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height)))
            }.value
        } else {
            let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: pixels / 2, height: pixels / 2), scale: 2,
                                                       representationTypes: .thumbnail)
            made = (try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)).map { Box($0.nsImage) }
        }
        // Spelled out: CI's Swift 6.3 crashes on `guard let made` here.
        guard let box = made, !Task.isCancelled else { return nil }
        let area = box.image.representations.first.map { $0.pixelsWide * $0.pixelsHigh } ?? 0
        cache.setObject(box, forKey: key, cost: max(area, 1) * 4)
        return box.image
    }
}
