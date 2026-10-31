#if DEBUG
import AppKit
import SwiftUI

/// The `open-morph` scope: the Nook opening onto Music and closing again beside the
/// activities that sit next to the camera (the clear look's bubbles, the solid look's
/// lanes, and the agent bubble), as it was (one spring for both directions) and as it is
/// (down, then out). Time runs 3x slower and frames are taken at 30 a second, so each
/// frame is 1/90 s; `open-morph/<case>-<before|after>/f000.png` and, per case, a contact
/// sheet `<case>-open.png` and `<case>-close.png` (before on top, after below, every
/// third frame: 1/30 s apart). Reduce Motion is forced off (the runners have it on).
///
/// The `open-morph-song` scope: the song alone (`open-morph/song/<case>/`), as on screen: the pointer
/// reaches the closed notch (the hover peek), clicks it open onto Music a moment later
/// and it closes again, after one open and close to build the page. A runner draws only a
/// few frames a second, so time runs 12x slower and frames are taken as fast as it can,
/// kept in memory until the end; each is named for its moment in app time
/// (`t0450.png` is 0.450 s after the hover). At 2x pixels, only the top of the stage (the
/// camera, the bubbles and the top of the panel), as it was (`<case>-before`, the clear
/// look growing from its lanes) and as it is (`<case>-after`; the solid look once, as it's
/// unchanged), with strips `song/<case>-<variant>-open.png` and `-close.png`: the frame
/// nearest each 1/60 s, top to bottom.
/// Cases: the clear look on a notch, an island and a notchless screen, the solid look
/// on a notch and an island.
@MainActor enum OpenMorphCaptures {
    private static let slow = 3.0

    static func capture(to directory: URL) {
        let folder = directory.appendingPathComponent("open-morph")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        ThemeStore.shared.selectFamily(.macspaces)
        ThemeStore.shared.reduceMotionPreference = false
        ThemeStore.shared.setPreviewSystemReduceMotion(false)
        let settings = NookSettings.shared
        settings.widgets = [.media, .clock, .timer]
        settings.expandOnHover = false
        settings.showMusicLiveActivity = true
        settings.showTimerLiveActivity = true
        var track = NowPlayingInfo()
        track.title = "Harbour Lights"; track.artist = "Sample Artist"; track.album = "Low Tide"
        track.sourceName = "Music"; track.capabilities = [.playPause, .previous, .next, .seek]
        track.duration = 236; track.elapsed = 81; track.isPlaying = true
        AppServices.shared.nowPlaying.setPreviewInfo(track)
        AppServices.shared.timerService.setPreview(remaining: 754, total: 1500)
        AgentActivityMonitor.shared.preview()
        AgentPopout.shared.setPreview(AgentActivityMonitor.shared.sessions.filter { $0.id == "b" })
        Design.demoTimeScale = slow
        defer { Design.demoTimeScale = 1; NotchContainerView.stagesOpen = true }

        let cases: [(String, NotchGeometry)] = [
            ("notch-clear", NotchGeometry(width: 185, height: 32, cutout: .notch, look: .clear)),
            ("notch-solid", NotchGeometry(width: 185, height: 32, cutout: .notch, look: .solid)),
            ("notchless-clear", NotchGeometry(width: 156, height: 30, cutout: .none, look: .clear)),
        ]
        for (name, geometry) in cases {
            var sheets: [[CGImage]] = []
            for staged in [false, true] {
                NotchContainerView.stagesOpen = staged
                let model = NotchViewModel(geometry: geometry, availableWidth: 1512, settings: settings, shelf: ShelfStore.shared,
                    nowPlaying: AppServices.shared.nowPlaying, powerMonitor: AppServices.shared.powerMonitor,
                    timerService: AppServices.shared.timerService, bluetoothMonitor: AppServices.shared.bluetooth,
                    systemActivityMonitor: AppServices.shared.systemActivity, teleprompter: AppServices.shared.teleprompter)
                model.selectedTab = .music
                let size = NSSize(width: 820, height: 470)
                let frames = folder.appendingPathComponent("\(name)-\(staged ? "after" : "before")")
                sheets.append(record(Stage(model: model, staged: staged, size: size), model: model, size: size, to: frames))
            }
            for (part, range) in [("open", 0..<45), ("close", 45..<90)] {
                let picks = Array(range).filter { $0 % 3 == 0 }
                write(sheet(sheets.map { frames in picks.map { frames[$0] } }), to: folder.appendingPathComponent("\(name)-\(part).png"))
            }
        }
        print("Open morph captures written")
    }

    /// The `open-morph-song` scope, its own for time: the song sequence below.
    static func captureSong(into directory: URL) {
        ThemeStore.shared.selectFamily(.macspaces)
        ThemeStore.shared.reduceMotionPreference = false
        ThemeStore.shared.setPreviewSystemReduceMotion(false)
        NookSettings.shared.widgets = [.media, .clock, .timer]
        NookSettings.shared.expandOnHover = false
        NookSettings.shared.showMusicLiveActivity = true
        defer { Design.demoTimeScale = 1 }
        captureSong(to: directory.appendingPathComponent("open-morph").appendingPathComponent("song"))
        print("Open morph song captures written")
    }

    /// In app time: hover at 0, click at `clickTime`, close at `closeTime`, end at `endTime`.
    private static let clickTime = 0.07, closeTime = 0.8, endTime = 1.55, songSlow = 12.0
    /// The stage is laid out at `songStage` and only its top middle drawn.
    private static let songStage = NSSize(width: 820, height: 470)
    private static let songSize = NSSize(width: 700, height: 150)

    private static func captureSong(to folder: URL) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var track = NowPlayingInfo()
        track.title = "Golden Hour"; track.artist = "Sample Artist"; track.album = "Low Tide"
        track.sourceName = "Music"; track.capabilities = [.playPause, .previous, .next, .seek]
        track.duration = 240; track.elapsed = 150; track.isPlaying = true; track.artwork = cover
        AppServices.shared.nowPlaying.setPreviewInfo(track)
        AppServices.shared.timerService.setPreview(remaining: 0, total: 1500)
        NotchContainerView.stagesOpen = true
        let notch = NotchGeometry.Reading(screenWidth: 1512, safeTop: 32, auxiliaryLeft: 663.5, auxiliaryRight: 663.5)
        let island = NotchGeometry.Reading(screenWidth: 1512, safeTop: 0, menuBarHeight: 32, hasCameraIsland: true,
                                           islandCutout: CGRect(x: 0, y: 5, width: 120, height: 24))
        let notchless = NotchGeometry.Reading(screenWidth: 1512, safeTop: 0, menuBarHeight: 32)
        let cases: [(String, NotchGeometry.Reading, NotchGeometry.Look)] = [
            ("notch-clear", notch, .clear), ("island-clear", island, .clear), ("notchless-clear", notchless, .clear),
            ("notch-solid", notch, .solid), ("island-solid", island, .solid),
        ]
        defer { NotchContainerView.clearOnCamera = true }
        for (name, reading, look) in cases { for after in look == .clear ? [false, true] : [true] {
            NotchContainerView.clearOnCamera = after
            let model = NotchViewModel(geometry: NotchGeometry.resolve(reading, look: look, notchlessHint: true),
                availableWidth: 1512, settings: NookSettings.shared, shelf: ShelfStore.shared,
                nowPlaying: AppServices.shared.nowPlaying, powerMonitor: AppServices.shared.powerMonitor,
                timerService: AppServices.shared.timerService, bluetoothMonitor: AppServices.shared.bluetooth,
                systemActivityMonitor: AppServices.shared.systemActivity, teleprompter: AppServices.shared.teleprompter)
            model.selectedTab = .music
            let variant = "\(name)-\(after ? "after" : "before")"
            let frames = recordSong(SongStage(model: model, size: songStage), model: model, to: folder.appendingPathComponent(variant))
            for (part, from, to) in [("open", 0.0, closeTime), ("close", closeTime, endTime)] {
                let picks = stride(from: from, to: to, by: 1.0 / 60).compactMap { time in
                    frames.min { abs($0.time - time) < abs($1.time - time) }?.image
                }
                write(strip(picks), to: folder.appendingPathComponent("\(variant)-\(part).png"))
            }
        } }
    }

    private static let cover = NSImage(size: NSSize(width: 120, height: 120), flipped: false) { rect in
        NSGradient(colors: [NSColor(red: 0.98, green: 0.55, blue: 0.35, alpha: 1),
                            NSColor(red: 0.42, green: 0.25, blue: 0.62, alpha: 1)])?.draw(in: rect, angle: -60)
        NSColor(white: 1, alpha: 0.85).setFill()
        NSBezierPath(ovalIn: NSRect(x: 70, y: 66, width: 30, height: 30)).fill()
        return true
    }

    /// A light desktop with a menu bar, the Nook and the camera drawn over it (black
    /// whatever is under it, as the hardware is).
    private struct SongStage: View {
        @ObservedObject var model: NotchViewModel
        let size: NSSize

        var body: some View {
            let geometry = model.geometry
            ZStack(alignment: .top) {
                LinearGradient(colors: [Color(red: 0.78, green: 0.84, blue: 0.93), Color(red: 0.93, green: 0.86, blue: 0.80)],
                               startPoint: .top, endPoint: .bottom)
                Rectangle().fill(Color.white.opacity(0.35)).frame(height: 32)
                NotchContainerView(viewModel: model)
                switch geometry.cutout {
                case .notch:
                    UnevenRoundedRectangle(bottomLeadingRadius: 8, bottomTrailingRadius: 8).fill(Color.black)
                        .frame(width: geometry.width, height: geometry.height)
                case .island:
                    Capsule().fill(Color.black).frame(width: 120, height: 24).offset(y: 5)
                case .none:
                    EmptyView()
                }
            }
            .frame(width: size.width, height: size.height)
            .frame(width: songSize.width, height: songSize.height, alignment: .top)
            .clipped()
        }
    }

    private static func recordSong<V: View>(_ view: V, model: NotchViewModel, to folder: URL) -> [(time: Double, image: CGImage)] {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: songSize)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        window.ignoresMouseEvents = true
        let screen = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        window.setFrameOrigin(NSPoint(x: screen.minX, y: screen.maxY - songSize.height))
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        // Build the page once, as hover warming does on screen.
        Design.demoTimeScale = 1
        model.expand(to: .music)
        RunLoop.main.run(until: Date().addingTimeInterval(1.2))
        model.collapse()
        RunLoop.main.run(until: Date().addingTimeInterval(1.5))
        Design.demoTimeScale = songSlow
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(songSize.width * 2),
                                      pixelsHigh: Int(songSize.height * 2), bitsPerSample: 8, samplesPerPixel: 4,
                                      hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                      bytesPerRow: 0, bitsPerPixel: 0)!
        bitmap.size = songSize
        var frames: [(time: Double, image: CGImage)] = []
        var clicked = false, closed = false
        let start = Date()
        model.hoverChanged(true)
        while true {
            let time = Date().timeIntervalSince(start) / songSlow
            guard time < endTime else { break }
            if !clicked && time >= clickTime { clicked = true; model.expand(to: .music) }
            if !closed && time >= closeTime { closed = true; model.collapse() }
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
            host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
            host.cacheDisplay(in: host.bounds, to: bitmap)
            // Copied, since the bitmap is drawn into again for the next frame.
            let shown = Date().timeIntervalSince(start) / songSlow
            if let image = bitmap.cgImage.flatMap(copied) { frames.append(((time + shown) / 2, image)) }
        }
        window.close()
        Design.demoTimeScale = 1
        for frame in frames {
            write(frame.image, to: folder.appendingPathComponent(String(format: "t%04d.png", Int((frame.time * 1000).rounded()))))
        }
        return frames
    }

    /// The image drawn into its own pixels.
    private static func copied(_ image: CGImage) -> CGImage? {
        let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        context?.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context?.makeImage()
    }

    /// Frames top to bottom, with a thin gap between them.
    private static func strip(_ images: [CGImage]) -> CGImage {
        let cropped = images
        let width = Int(songSize.width * 2), height = Int(songSize.height * 2), gap = 4
        let context = CGContext(data: nil, width: width, height: max(1, cropped.count * (height + gap)),
                                bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: context.width, height: context.height))
        for (row, image) in cropped.enumerated() {
            context.draw(image, in: CGRect(x: 0, y: (cropped.count - 1 - row) * (height + gap), width: width, height: height))
        }
        return context.makeImage()!
    }

    /// The top of a light desktop with a menu bar, the camera, the Nook and the agent bubble.
    private struct Stage: View {
        @ObservedObject var model: NotchViewModel
        let staged: Bool
        let size: NSSize

        var body: some View {
            let closed = model.collapsedSize
            let side = model.closedBubbleSide
            ZStack(alignment: .top) {
                LinearGradient(colors: [Color(red: 0.78, green: 0.84, blue: 0.93), Color(red: 0.93, green: 0.86, blue: 0.80)],
                               startPoint: .top, endPoint: .bottom)
                Rectangle().fill(Color.white.opacity(0.35)).frame(height: 30)
                if model.geometry.isHardwareNotch {
                    // The camera housing: rounded below, square at the top edge.
                    RoundedRectangle(cornerRadius: 8).fill(Color(white: 0.16))
                        .frame(width: model.geometry.width, height: model.geometry.height + 8)
                        .offset(y: -8)
                }
                NotchContainerView(viewModel: model)
                if model.state == .collapsed {
                    // Hidden while open, as on screen: before, a 0.22 s tuck as the Nook
                    // opened and back out at once; now 0.12 s, and back once it has closed.
                    AgentPopoutView(popout: AgentPopout.shared, stillPulse: 0.6)
                        .frame(width: side, height: side)
                        .offset(x: model.collapsedContentOffset + closed.width / 2 + AgentPopoutLayout.gap + side / 2)
                        .transition(staged
                            ? .asymmetric(insertion: .opacity.animation(Design.timed(.easeOut(duration: 0.38).delay(Design.closeSettleDelay))),
                                          removal: .opacity.animation(Design.timed(.easeOut(duration: 0.12))))
                            : .asymmetric(insertion: .opacity.animation(Design.timed(.easeOut(duration: 0.38))),
                                          removal: .opacity.animation(Design.timed(.easeOut(duration: 0.22)))))
                }
            }
            .frame(width: size.width, height: size.height)
        }
    }

    private static func record<V: View>(_ view: V, model: NotchViewModel, size: NSSize, to frames: URL) -> [CGImage] {
        try? FileManager.default.createDirectory(at: frames, withIntermediateDirectories: true)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        window.ignoresMouseEvents = true
        // On screen: off it, the display link that steps SwiftUI's animations doesn't run,
        // and every frame would show the end state.
        let screen = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        window.setFrameOrigin(NSPoint(x: screen.minX, y: screen.maxY - size.height))
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        var images: [CGImage] = []
        let start = Date()
        for n in 0..<90 {
            if n == 0 { model.expand(to: .music) }
            if n == 45 { model.collapse() }
            RunLoop.main.run(until: start.addingTimeInterval(Double(n) / 30))
            host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
            guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                                                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { continue }
            bitmap.size = size
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try? bitmap.representation(using: .png, properties: [:])?
                .write(to: frames.appendingPathComponent(String(format: "f%03d.png", n)))
            if let image = bitmap.cgImage { images.append(image) }
        }
        window.close()
        return images
    }

    /// Rows of frames, each scaled to half size, with a gap between them.
    private static func sheet(_ rows: [[CGImage]]) -> CGImage {
        let width = (rows.first?.first?.width ?? 1) / 2, height = (rows.first?.first?.height ?? 1) / 2
        let columns = rows.map(\.count).max() ?? 1, gap = 6
        let context = CGContext(data: nil, width: columns * (width + gap), height: rows.count * (height + gap),
                                bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: context.width, height: context.height))
        for (row, images) in rows.enumerated() {
            for (column, image) in images.enumerated() {
                context.draw(image, in: CGRect(x: column * (width + gap), y: (rows.count - 1 - row) * (height + gap), width: width, height: height))
            }
        }
        return context.makeImage()!
    }

    private static func write(_ image: CGImage, to url: URL) {
        try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: url)
    }
}
#endif
