import SwiftUI
import AppKit
import ImageIO

/// Rotating slideshow of images from a folder (defaults to ~/Pictures).
/// Click to open the current photo. macOS shows a one-time folder prompt.
struct PhotosWidget: View {
    @StateObject private var model = PhotosModel()

    var body: some View {
        Button {
            if let url = model.current {
                NSWorkspace.shared.open(url)
            }
        } label: {
            Group {
                if let image = model.currentImage {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    WidgetEmptyState(
                        systemImage: "photo.on.rectangle.angled",
                        caption: "Add images to ~/Pictures",
                        captionSize: 8
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onAppear { model.start() }
        .onDisappear { model.stop() }
        .contextMenu {
            Button("Next Photo") { model.advance() }
        }
    }
}

@MainActor
private final class PhotosModel: ObservableObject {
    @Published private(set) var current: URL?
    @Published private(set) var currentImage: NSImage?

    private var urls: [URL] = []
    private var index = 0
    private var timer: Timer?
    private var cache: [URL: NSImage] = [:]
    private var loadTask: Task<Void, Never>?
    private var scanTask: Task<Void, Never>?
    private var scanGeneration = 0

    func start() {
        guard timer == nil else { return }
        reload(advanceWhenReady: true)
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.advance()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        loadTask?.cancel()
        loadTask = nil
        scanGeneration += 1
        scanTask?.cancel()
        scanTask = nil
    }

    deinit {
        timer?.invalidate()
        loadTask?.cancel()
        scanTask?.cancel()
    }

    private func reload(advanceWhenReady: Bool) {
        scanGeneration += 1
        let generation = scanGeneration
        scanTask?.cancel()
        scanTask = Task { [weak self] in
            let scanned = await Task.detached(priority: .utility) {
                Self.scanPictures()
            }.value
            guard !Task.isCancelled,
                  let self,
                  self.scanGeneration == generation else { return }
            self.urls = scanned
            self.index = -1
            self.scanTask = nil
            if advanceWhenReady {
                self.advance()
            }
        }
    }

    func advance() {
        guard scanTask == nil else { return }
        if urls.isEmpty {
            reload(advanceWhenReady: true)
            return
        }
        guard !urls.isEmpty else {
            current = nil
            currentImage = nil
            return
        }
        index = (index + 1) % urls.count
        let url = urls[index]
        current = url
        loadImage(for: url)
    }

    nonisolated private static func scanPictures() -> [URL] {
        guard let pictures = FileManager.default.urls(
            for: .picturesDirectory,
            in: .userDomainMask
        ).first else { return [] }
        let imageExtensions: Set<String> = [
            "png", "jpg", "jpeg", "heic", "gif", "webp",
        ]
        return ((try? FileManager.default.contentsOfDirectory(
            at: pictures,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? [])
            .filter { imageExtensions.contains($0.pathExtension.lowercased()) }
            .shuffled()
    }

    /// Decodes a downsampled thumbnail off the main thread; full-resolution
    /// `NSImage(contentsOf:)` on the main thread stalls body evaluation.
    private func loadImage(for url: URL) {
        if let cached = cache[url] {
            currentImage = cached
            return
        }
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            let thumbnailData = await Task.detached(priority: .utility) {
                Self.thumbnailData(for: url)
            }.value
            guard !Task.isCancelled,
                  let self,
                  self.current == url else { return }
            if let thumbnailData, let image = NSImage(data: thumbnailData) {
                // Keep the cache tiny; tiles are small.
                if cache.count > 4 { cache.removeAll() }
                cache[url] = image
                currentImage = image
            } else {
                currentImage = nil
            }
            loadTask = nil
        }
    }

    nonisolated private static func thumbnailData(for url: URL) -> Data? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(
                source,
                0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 320,
                    kCGImageSourceShouldCacheImmediately: true,
                ] as CFDictionary
              ) else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }
}
