import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// The Folio page's Links: web addresses you paste or drop on the page, each a card with its
/// page's title and preview picture. A page is read once, when you add its address, and never
/// for anything else (`FolioLinkFetch`). The list is `folio-links.json` and the previews sit in
/// "Link previews" beside it, all written on `ShelfDisk.queue`.
@MainActor
final class FolioLinks: ObservableObject {
    static let shared = FolioLinks()
    @Published private(set) var book = FolioLinkBook()
    /// Links whose page is being read.
    @Published private(set) var fetching: Set<UUID> = []
    /// Preview pictures read so far, by link (at most `imageLimit`).
    @Published private(set) var images: [UUID: NSImage] = [:]
    @Published private(set) var undoText: String?
    private var removed: [(index: Int, item: FolioLink)] = []
    private var undoWork: DispatchWorkItem?
    private var saveWork: DispatchWorkItem?
    private var waiting: [FolioLink] = []
    private var running = false
    private var loading: Set<UUID> = []
    private var loaded = false
    private var savesDisabled = false
    private let file = FolioStorage.url("folio-links.json")
    static let previews = FolioStorage.url("Link previews")
    static let imageLimit = 120

    init() {
        let file = self.file
        ShelfDisk.queue.async {
            let saved = FolioStorage.read(FolioLinkBook.self, from: file)
            Task { @MainActor [weak self, saved] in
                guard let self else { return }
                // Links added while the file loaded stay in front (one per address).
                let older = saved?.links ?? []
                self.book = FolioLinkBook(self.book.links + older)
                self.loaded = true
            }
        }
    }

    /// Saves addresses you put on the page; each new one's page is read once, one at a time.
    func add(_ urls: [URL]) {
        let fresh = book.add(urls.filter(FolioWeb.isWeb), now: Date())
        guard !urls.isEmpty else { return }
        scheduleSave()
        waiting.append(contentsOf: fresh)
        next()
    }

    private func next() {
        guard !running, !waiting.isEmpty else { return }
        let link = waiting.removeFirst()
        guard let url = link.url, book.links.contains(where: { $0.id == link.id }) else { next(); return }
        running = true
        fetching.insert(link.id)
        let id = link.id, folder = Self.previews
        Task { [weak self] in
            let page = await Task.detached(priority: .utility) { await FolioLinkFetch.read(url) }.value
            let name: String? = await withCheckedContinuation { continuation in
                ShelfDisk.queue.async {
                    guard let image = page.image else { continuation.resume(returning: nil); return }
                    let name = id.uuidString + ".jpg"
                    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    let saved = (try? image.write(to: folder.appendingPathComponent(name), options: .atomic)) != nil
                    continuation.resume(returning: saved ? name : nil)
                }
            }
            guard let self else { return }
            self.running = false
            self.fetching.remove(id)
            // A link removed while its page was read keeps nothing of it.
            if self.book.links.contains(where: { $0.id == id }) {
                self.book.fill(id, title: page.title, preview: name)
                self.scheduleSave()
            }
            self.next()
        }
    }

    /// The preview picture, read off the main thread the first time a card shows.
    func loadImage(_ link: FolioLink) {
        guard images[link.id] == nil, !loading.contains(link.id), let name = link.preview else { return }
        loading.insert(link.id)
        let url = Self.previews.appendingPathComponent(name), id = link.id
        Task { [weak self] in
            let image = await Task.detached(priority: .utility) { () -> NSImage? in
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                      let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
                return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            }.value
            guard let self else { return }
            self.loading.remove(id)
            guard let image, self.book.links.contains(where: { $0.id == id }) else { return }
            if self.images.count >= Self.imageLimit, let first = self.images.keys.first { self.images[first] = nil }
            self.images[id] = image
        }
    }

    func open(_ link: FolioLink) {
        guard let url = link.url, FolioWeb.isWeb(url) else { return }
        NSWorkspace.shared.open(url)
    }

    func copy(_ link: FolioLink) {
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(link.address, forType: .string)
        if let url = link.url { board.setString(url.absoluteString, forType: .URL) }
    }

    func remove(_ ids: Set<UUID>) {
        let gone = book.remove(ids)
        guard !gone.isEmpty else { return }
        removed = gone
        undoText = gone.count == 1 ? "Removed \u{201C}\(gone[0].item.title.isEmpty ? gone[0].item.host : gone[0].item.title)\u{201D}" : "Removed \(gone.count) links"
        undoWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            withAnimation(Design.spring()) { self.undoText = nil }
            self.forgetPreviews(self.removed.map(\.item))
            self.removed = []
        }
        undoWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + ShelfStore.undoSeconds, execute: work)
        scheduleSave()
    }

    func removeAll() { remove(Set(book.links.map(\.id))) }

    func undo() {
        guard !removed.isEmpty else { return }
        book.restore(removed)
        removed = []
        undoWork?.cancel(); undoText = nil
        scheduleSave()
    }

    /// A removed link's preview picture goes once Undo can no longer bring it back.
    private func forgetPreviews(_ links: [FolioLink]) {
        guard !savesDisabled else { return }
        let names = links.compactMap(\.preview), folder = Self.previews
        links.forEach { images[$0.id] = nil }
        ShelfDisk.queue.async { names.forEach { try? FileManager.default.removeItem(at: folder.appendingPathComponent($0)) } }
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
    /// Check renders: no links and none saved; links added after this go through the fetcher,
    /// which the check stubs.
    func setPreview() {
        savesDisabled = true
        saveWork?.cancel()
        book = FolioLinkBook()
        images = [:]
        loaded = true
    }

    /// Finishes when every page waiting to be read has been.
    func waitForFetches() async {
        for _ in 0..<200 where running || !waiting.isEmpty { try? await Task.sleep(nanoseconds: 50_000_000) }
        for link in book.links { loadImage(link) }
        for _ in 0..<100 where !loading.isEmpty { try? await Task.sleep(nanoseconds: 50_000_000) }
    }
#endif
}

/// Reading one web page you saved: only http and https, no cookies, no cache, nothing run (the
/// HTML's head is only parsed for its title and preview picture), a 10-second timeout, at most
/// 1 MB of page and 8 MB of picture. The picture is kept as a small JPEG.
enum FolioLinkFetch {
    struct Page: Sendable {
        var title = ""
        /// The preview picture as a JPEG at most 640 pixels across.
        var image: Data?
    }

    static let timeout: TimeInterval = 10
    static let pageLimit = 1_000_000
    static let imageLimit = 8_000_000

    /// How a request is made; the check renders replace it, so they never use the network.
    static var transport: (URLRequest, Int) async throws -> (Data, URLResponse) = { request, limit in
        try await download(request, limit: limit)
    }

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout * 2
        configuration.httpMaximumConnectionsPerHost = 2
        return URLSession(configuration: configuration)
    }()

    static func read(_ url: URL) async -> Page {
        guard FolioWeb.isWeb(url), let answer = try? await transport(request(url), pageLimit) else { return Page() }
        let (data, response) = answer
        let final = response.url ?? url
        guard FolioWeb.isWeb(final), ok(response) else { return Page() }
        let mime = (response.mimeType ?? "").lowercased()
        // An address of a picture is its own preview.
        if mime.hasPrefix("image/") { return Page(title: final.lastPathComponent, image: thumbnail(data)) }
        guard mime.isEmpty || mime.contains("html") else { return Page() }
        let html = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        let head = FolioWeb.page(html: html, base: final)
        var page = Page(title: head.title)
        if let picture = head.image, let fetched = try? await transport(request(picture), imageLimit) {
            let kind = (fetched.1.mimeType ?? "image/").lowercased()
            if ok(fetched.1), kind.hasPrefix("image/") { page.image = thumbnail(fetched.0) }
        }
        return page
    }

    private static func ok(_ response: URLResponse) -> Bool {
        guard let http = response as? HTTPURLResponse else { return true }
        return (200..<300).contains(http.statusCode)
    }

    private static func request(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.httpShouldHandleCookies = false
        request.setValue("text/html,application/xhtml+xml,image/*;q=0.8", forHTTPHeaderField: "Accept")
        return request
    }

    /// At most `limit` bytes; the rest is never read.
    private static func download(_ request: URLRequest, limit: Int) async throws -> (Data, URLResponse) {
        let (bytes, response) = try await session.bytes(for: request)
        var data = Data()
        data.reserveCapacity(min(limit, 262_144))
        for try await byte in bytes {
            data.append(byte)
            if data.count >= limit { break }
        }
        return (data, response)
    }

    /// A JPEG at most 640 pixels across, or nil when it isn't a picture of a useful size.
    static func thumbnail(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0 else { return nil }
        let options = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 640,
                       kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options), image.width >= 60, image.height >= 40 else { return nil }
        let out = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? out as Data : nil
    }
}

/// The Links place: a card per saved address with its page's picture, title and site. A click
/// opens it in the default browser.
struct FolioLinksGrid: View {
    let terms: [String]
    @ObservedObject var links = FolioLinks.shared
    @Binding var isDropTargeted: Bool
    let drop: ([NSItemProvider]) -> Bool
    @ObservedObject var theme = ThemeStore.shared

    var body: some View {
        let shown = links.book.matching(terms)
        Group {
            if links.book.links.isEmpty {
                FolioQuietEmpty(symbol: "link", title: "No links yet",
                                detail: "Paste or drop a web address to save it as a card with its page's title and picture.")
            } else if shown.isEmpty {
                FolioQuietEmpty(symbol: "magnifyingglass", title: "No matching links", detail: "Search reads each page's title and address.")
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 124, maximum: 190), spacing: 8)], alignment: .leading, spacing: 8) {
                        ForEach(shown) { link in
                            FolioLinkCard(link: link, image: links.images[link.id], fetching: links.fetching.contains(link.id))
                                .onAppear { links.loadImage(link) }
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

private struct FolioLinkCard: View {
    let link: FolioLink
    let image: NSImage?
    let fetching: Bool
    @ObservedObject private var theme = ThemeStore.shared
    @State private var hovering = false

    var body: some View {
        let corner = RoundedRectangle(cornerRadius: 9, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            picture
                .frame(height: 64)
                .frame(maxWidth: .infinity)
                .clipped()
            VStack(alignment: .leading, spacing: 2) {
                Text(link.title.isEmpty ? link.host : link.title)
                    .font(.system(size: 10, weight: .semibold)).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 3) {
                    Image(systemName: "globe").font(.system(size: 7.5, weight: .semibold))
                    Text(link.host).font(.system(size: 8.5)).lineLimit(1).truncationMode(.middle)
                }
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 7).padding(.vertical, 6)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .topLeading)
        }
        .background(Color.primary.opacity(0.06))
        .clipShape(corner)
        .overlay { corner.strokeBorder(Color.primary.opacity(hovering ? 0.22 : 0.09), lineWidth: hovering ? 1 : 0.5) }
        .overlay(alignment: .topTrailing) {
            if hovering {
                Button { withAnimation(Design.spring()) { FolioLinks.shared.remove([link.id]) } } label: {
                    Image(systemName: "xmark").font(.system(size: 7, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 15, height: 15)
                        .background(Color.black.opacity(0.6), in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Remove this link")
                .padding(4)
            }
        }
        .scaleEffect(hovering && !theme.reduceMotion ? 1.015 : 1)
        .animation(Design.hoverAnimation, value: hovering)
        .contentShape(corner)
        .onHover { hovering = $0 }
        .onTapGesture { FolioLinks.shared.open(link) }
        .contextMenu {
            Button("Open in Browser") { FolioLinks.shared.open(link) }
            Button("Copy Address") { FolioLinks.shared.copy(link) }
            Divider()
            Button("Remove", role: .destructive) { FolioLinks.shared.remove([link.id]) }
        }
        .help("\(link.address)\nClick to open it in your browser.")
        .accessibilityAddTraits(.isLink)
        .accessibilityLabel(link.title.isEmpty ? link.host : link.title)
    }

    @ViewBuilder
    private var picture: some View {
        if let image {
            Color.clear.overlay { Image(nsImage: image).resizable().interpolation(.medium).scaledToFill() }
        } else {
            ZStack {
                LinearGradient(colors: [tint.opacity(0.55), tint.opacity(0.25)], startPoint: .topLeading, endPoint: .bottomTrailing)
                if fetching {
                    ProgressView().controlSize(.small)
                } else {
                    Text(String(link.host.prefix(1)).uppercased())
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
        }
    }

    /// A steady colour per site, for cards without a picture.
    private var tint: Color {
        let value = link.host.unicodeScalars.reduce(UInt32(7)) { ($0 &* 31) &+ $1.value }
        return Color(hue: Double(value % 360) / 360, saturation: 0.45, brightness: 0.7)
    }
}
