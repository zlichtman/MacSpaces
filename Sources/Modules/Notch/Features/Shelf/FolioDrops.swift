import AppKit
import UniformTypeIdentifiers

/// What the Folio page does with something dropped or pasted on it: hex codes and colours from
/// the colour picker become swatches in Colors, web addresses become cards in Links, and files,
/// pictures and other text join the list showing. `saved` hears which place took colours or
/// links, so the page can show them.
@MainActor
enum FolioDrops {
    /// The colour picker's own type.
    static let colorType = NSPasteboard.PasteboardType.color.rawValue

    /// Everything the page takes.
    static let types: [UTType] = [.fileURL, .url, .image, .plainText] + [UTType(colorType)].compactMap { $0 }

    static func handle(_ providers: [NSItemProvider], into store: ShelfStore, saved: ((FolioPlace) -> Void)? = nil) -> Bool {
        var accepted = false
        var rest: [NSItemProvider] = []
        for provider in providers {
            let isFile = provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
            if provider.hasItemConformingToTypeIdentifier(colorType) {
                accepted = true
                provider.loadDataRepresentation(forTypeIdentifier: colorType) { data, _ in
                    Task { @MainActor in
                        guard let data, let color = NSColor(pasteboardPropertyList: data, ofType: .color) else { return }
                        if FolioSwatches.shared.add(color) > 0 { saved?(.colors) }
                    }
                }
            } else if !isFile, provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                accepted = true
                provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, _ in
                    let url = Self.url(from: item)
                    Task { @MainActor in
                        if let url, FolioWeb.isWeb(url) {
                            FolioLinks.shared.add([url])
                            saved?(.links)
                        } else {
                            store.handleDrop(providers: [provider])
                        }
                    }
                }
            } else if !isFile, !provider.hasItemConformingToTypeIdentifier(UTType.image.identifier),
                      provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                accepted = true
                provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
                    let text = (item as? String) ?? (item as? Data).flatMap { String(data: $0, encoding: .utf8) }
                    Task { @MainActor in
                        guard let text else { return }
                        if let place = take(text) { saved?(place) } else { store.addText(text) }
                    }
                }
            } else {
                rest.append(provider)
            }
        }
        if !rest.isEmpty, store.handleDrop(providers: rest) { accepted = true }
        return accepted
    }

    /// ⌘V or Paste on the page: files and pictures join the list; a colour, hex codes or web
    /// addresses go to Colors or Links; other text joins the list.
    static func paste(into store: ShelfStore, saved: ((FolioPlace) -> Void)? = nil) {
        let board = NSPasteboard.general
        let files = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        if !files.isEmpty || board.data(forType: .png) != nil || board.data(forType: .tiff) != nil {
            store.paste()
            return
        }
        if let color = NSColor(from: board), FolioSwatches.shared.add(color) > 0 {
            saved?(.colors)
            return
        }
        if let text = board.string(forType: .string), let place = take(text) {
            saved?(place)
            return
        }
        if let link = board.string(forType: .URL), let url = URL(string: link), FolioWeb.isWeb(url) {
            FolioLinks.shared.add([url])
            saved?(.links)
            return
        }
        store.paste()
    }

    /// Text that's only hex codes becomes swatches, and only web addresses becomes links.
    /// Returns the place that took it, or nil for any other text.
    static func take(_ text: String) -> FolioPlace? {
        let colors = FolioHex.palette(in: text)
        if !colors.isEmpty {
            FolioSwatches.shared.add(colors, source: colors.count > 1 ? "Pasted palette" : "Pasted")
            return .colors
        }
        let addresses = FolioWeb.addresses(in: text)
        if !addresses.isEmpty {
            FolioLinks.shared.add(addresses)
            return .links
        }
        return nil
    }

    nonisolated private static func url(from item: NSSecureCoding?) -> URL? {
        if let url = item as? URL { return url }
        if let data = item as? Data { return URL(dataRepresentation: data, relativeTo: nil) }
        if let text = item as? String { return URL(string: text) }
        return nil
    }
}
