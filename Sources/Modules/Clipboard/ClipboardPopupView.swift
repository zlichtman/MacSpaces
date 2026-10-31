import AppKit
import ImageIO
import SwiftUI

/// The history popup: a search field, the list (numbered 1–9, pins marked) and,
/// when enabled, a preview of the selected clip. Themed like the Nook.
struct ClipboardPopupView: View {
    @ObservedObject var model: ClipboardPopupModel
    @ObservedObject private var preferences = ClipboardPreferences.shared
    @ObservedObject private var theme = ThemeStore.shared
    @FocusState private var searching: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider().opacity(0.4)
            HStack(spacing: 0) {
                list.frame(maxWidth: .infinity)
                if preferences.showsPreview {
                    Divider().opacity(0.4)
                    ClipPreview(clip: model.current, count: model.selection.count)
                        .frame(width: 240)
                }
            }
            Divider().opacity(0.4)
            footer
        }
        .foregroundStyle(theme.nookForeground)
        .tint(theme.notch.accent)
        .background {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                theme.notch.surface.opacity(0.82)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.12)))
        .preferredColorScheme(theme.notch.colorScheme)
        .onChange(of: model.focusToken) { _ in searching = true }
        .onAppear { searching = true }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(searchPrompt, text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .focused($searching)
            if preferences.paused {
                Button("Paused") { preferences.paused = false }
                    .buttonStyle(WidgetChipStyle(prominent: true, height: 22))
                    .help("Recording is paused. Click to resume.")
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
    }

    private var searchPrompt: String {
        switch preferences.searchMode {
        case .exact: return "Search clipboard"
        case .fuzzy: return "Search clipboard (fuzzy)"
        case .regex: return "Search clipboard (regular expression)"
        case .mixed: return "Search, or @image, @link, @app, #collection"
        }
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 2) {
                    ForEach(Array(model.items.enumerated()), id: \.element.id) { index, clip in
                        ClipRow(clip: clip, number: index < 9 ? index + 1 : nil, pinKey: model.pinKey(for: clip), query: model.query,
                                selected: model.selection.contains(clip.id), showsIcon: preferences.showsAppIcons)
                            .id(clip.id)
                            .contentShape(Rectangle())
                            .onDrag { ClipboardActions.dragItem(clip) }
                            .contextMenu {
                                if let monitor = model.monitor {
                                    ClipMenu(clip: clip, monitor: monitor) { clip, plain in
                                        model.setCursor(index)
                                        ClipboardPopup.shared.paste(plain: plain)
                                    }
                                }
                            }
                            .onTapGesture {
                                model.setCursor(index, extend: NSEvent.modifierFlags.contains(.shift))
                                guard !NSEvent.modifierFlags.contains(.shift) else { return }
                                let option = NSEvent.modifierFlags.contains(.option)
                                if option != preferences.pasteOnSelect { ClipboardPopup.shared.paste(plain: preferences.plainTextByDefault) }
                                else { ClipboardPopup.shared.copySelection() }
                            }
                    }
                }
                .padding(6)
            }
            .overlay {
                if model.items.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "doc.on.clipboard").font(.system(size: 20)).foregroundStyle(.secondary)
                        Text(model.query.isEmpty ? "Copied text, links and images appear here." : "No matching clips.")
                            .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                    }
                }
            }
            .onChange(of: model.cursor) { cursor in
                guard let cursor, model.items.indices.contains(cursor) else { return }
                proxy.scrollTo(model.items[cursor].id)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if let notice = model.notice {
                Text(notice).lineLimit(1).truncationMode(.tail).foregroundStyle(theme.notch.accent)
            } else {
                hint(preferences.pasteOnSelect ? "↩" : "⌥↩", "Paste")
                hint(preferences.pasteOnSelect ? "⌥↩" : "↩", "Copy")
                hint("⌥⇧↩", preferences.plainTextByDefault ? "With formatting" : "Plain text")
                hint("⌥P", "Pin")
                hint("⌥⌫", "Delete")
            }
            Spacer(minLength: 0)
            Menu {
                Toggle("Pause recording", isOn: $preferences.paused)
                Button("Ignore next copy") { preferences.ignoresNextCopy = true }
                Divider()
                Button("New Snippet") {
                    ClipboardPopup.shared.hide()
                    if let monitor = model.monitor { ClipboardActions.newSnippet(monitor) }
                }
                Button("Pick Colour from Screen") {
                    ClipboardPopup.shared.hide()
                    model.monitor?.pickColor()
                }
                Divider()
                Button("Clear History") { model.monitor?.clear(keepingFavorites: true); model.refresh() }
                Button("Clear History and Pins", role: .destructive) { model.monitor?.clear(); model.refresh() }
                Divider()
                Button("Clipboard Settings") {
                    ClipboardPopup.shared.hide()
                    SettingsWindowController.shared.show(.clipboard)
                }
            } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .accessibilityLabel("Clipboard options")
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14).padding(.vertical, 8)
    }

    private func hint(_ keys: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(keys).font(.system(size: 10, weight: .semibold, design: .rounded))
                .padding(.horizontal, 4).padding(.vertical, 1)
                .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
            Text(label)
        }
    }
}

/// Clip images at the size they're shown, made once per clip: rows are redrawn on every
/// arrow key, and each redraw decoded the full copied image again. Each is at least
/// `covering` (pixels: the frame at 3x) in both directions, so it never looks softer.
@MainActor enum ClipThumbnails {
    private static let cache: NSCache<NSString, NSImage> = { let cache = NSCache<NSString, NSImage>(); cache.countLimit = 120; return cache }()

    static func image(for clip: ClipboardEntry, covering size: CGSize) -> NSImage? {
        guard let data = clip.imageData else { return nil }
        let key = "\(clip.id.uuidString)-\(data.count)-\(Int(size.width))x\(Int(size.height))" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber).map({ CGFloat($0.doubleValue) }),
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber).map({ CGFloat($0.doubleValue) }),
              width > 0, height > 0 else {
            return NSImage(data: data)
        }
        let scale = min(1, max(size.width / width, size.height / height))
        let options = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                       kCGImageSourceThumbnailMaxPixelSize: Int((max(width, height) * scale).rounded(.up))] as CFDictionary
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return NSImage(data: data) }
        let image = NSImage(cgImage: thumbnail, size: NSSize(width: thumbnail.width, height: thumbnail.height))
        cache.setObject(image, forKey: key)
        return image
    }
}

/// One clip: its number, the app it came from, a thumbnail or colour swatch,
/// the text with the search match in bold, and a pin.
private struct ClipRow: View {
    let clip: ClipboardEntry
    let number: Int?
    var pinKey: Character?
    let query: String
    let selected: Bool
    let showsIcon: Bool
    @ObservedObject private var theme = ThemeStore.shared

    var body: some View {
        HStack(spacing: 8) {
            if showsIcon { AppIcon(bundleID: clip.sourceBundleID).frame(width: 16, height: 16) }
            if let image = ClipThumbnails.image(for: clip, covering: CGSize(width: 34 * 3, height: 22 * 3)) {
                Image(nsImage: image).resizable().scaledToFill()
                    .frame(width: 34, height: 22).clipShape(RoundedRectangle(cornerRadius: 4))
            } else if let color = clip.hexColor {
                RoundedRectangle(cornerRadius: 4).fill(Color(red: color.red, green: color.green, blue: color.blue))
                    .frame(width: 16, height: 16)
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.primary.opacity(0.2)))
            }
            Text(highlighted)
                .font(.system(size: 12))
                .lineLimit(1).truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            if clip.isFavorite {
                Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(selected ? Color.black.opacity(0.7) : theme.notch.accent)
            }
            if let pinKey {
                Text("⌃\(String(pinKey).uppercased())").font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(selected ? Color.black.opacity(0.6) : .secondary)
            } else if let number {
                Text("⌘\(number)").font(.system(size: 10, weight: .medium, design: .rounded)).monospacedDigit()
                    .foregroundStyle(selected ? Color.black.opacity(0.6) : .secondary)
            }
        }
        .padding(.horizontal, 9).padding(.vertical, 6)
        .foregroundStyle(selected ? Color.black.opacity(0.85) : theme.nookForeground)
        .background(selected ? theme.notch.accent : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .help(clip.preview)
    }

    /// The first line, with spaces and line breaks shown compactly and the exact match in bold.
    private var highlighted: AttributedString {
        let line = clip.text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ⏎ ").replacingOccurrences(of: "\t", with: " ⇥ ")
        var text = AttributedString(String(line.prefix(200)))
        let needle = query.trimmingCharacters(in: .whitespaces)
        if !needle.isEmpty, let range = text.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) {
            text[range].font = .system(size: 12, weight: .bold)
        }
        return text
    }
}

/// The selected clip in full, with where and when it was copied.
private struct ClipPreview: View {
    let clip: ClipboardEntry?
    let count: Int

    var body: some View {
        if count > 1 {
            placeholder("\(count) clips selected", detail: "Copy or paste them together, one per line.")
        } else if let clip {
            VStack(alignment: .leading, spacing: 10) {
                ScrollView {
                    if let image = ClipThumbnails.image(for: clip, covering: CGSize(width: 240 * 3, height: 0)) {
                        Image(nsImage: image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 8))
                    } else if !clip.fileURLs.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(clip.fileURLs, id: \.self) { url in
                                Label(url.lastPathComponent, systemImage: "doc").font(.system(size: 12)).lineLimit(1)
                            }
                        }
                    } else {
                        Text(clip.text).font(.system(size: 12)).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if !clip.recognizedText.isEmpty {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Text in image").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                            Text(clip.recognizedText).font(.system(size: 11)).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.top, 6)
                    }
                }
                VStack(alignment: .leading, spacing: 3) {
                    if !clip.sourceName.isEmpty { detail("From", clip.sourceName) }
                    if !clip.tags.isEmpty { detail("In", clip.tags.joined(separator: ", ")) }
                    detail("Copied", clip.date.formatted(date: .abbreviated, time: .shortened))
                    if clip.copyCount > 1 {
                        detail("First", clip.firstDate.formatted(date: .abbreviated, time: .shortened))
                        detail("Times", "\(clip.copyCount)")
                    }
                    detail("Size", ByteCountFormatter.string(fromByteCount: Int64(clip.byteCount), countStyle: .memory))
                }
                .font(.system(size: 10))
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            placeholder("Nothing selected", detail: "")
        }
    }

    private func detail(_ label: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(label).foregroundStyle(.secondary).frame(width: 40, alignment: .leading)
            Text(value).lineLimit(1)
        }
    }

    private func placeholder(_ title: String, detail: String) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.system(size: 12, weight: .semibold))
            if !detail.isEmpty { Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.center) }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The icon of the app a clip was copied from.
struct AppIcon: View {
    let bundleID: String

    var body: some View {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().scaledToFit()
        } else {
            Color.clear
        }
    }
}
