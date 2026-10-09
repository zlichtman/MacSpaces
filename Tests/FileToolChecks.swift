import AppKit
import AVFoundation
import CoreVideo
import ImageIO
import PDFKit
import UniformTypeIdentifiers

@main struct FileToolChecks {
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
    }
    static func action(_ id: String, options: FileConverter.Options? = nil) -> FileConverter.Action {
        .init(id: id, title: id, symbol: nil, options: options)
    }
    static func image(_ url: URL, type: UTType = .png, frames: Int = 1) throws {
        let context = CGContext(data: nil, width: 600, height: 400, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor.red.withAlphaComponent(0.4).cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 300, height: 400))
        let image = context.makeImage()!
        let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, frames, nil)!
        for _ in 0..<frames { CGImageDestinationAddImage(destination, image, nil) }
        check(CGImageDestinationFinalize(destination), "write fixture")
    }
    @MainActor final class CancellationControl { var task: Task<FileConverter.BatchResult, Never>? }
    static func video(_ url: URL) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 320, AVVideoHeightKey: 200])
        let attributes: [String: Any] = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: 320, kCVPixelBufferHeightKey as String: 200]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: attributes)
        writer.add(input); check(writer.startWriting(), "video writer starts"); writer.startSession(atSourceTime: .zero)
        for index in 0..<24 {
            while !input.isReadyForMoreMediaData {
                check(writer.status == .writing, "video writer stays available")
                try await Task.sleep(for: .milliseconds(5))
            }
            var buffer: CVPixelBuffer?
            check(CVPixelBufferCreate(kCFAllocatorDefault, 320, 200, kCVPixelFormatType_32BGRA, attributes as CFDictionary, &buffer) == kCVReturnSuccess, "video pixel fixture")
            CVPixelBufferLockBaseAddress(buffer!, [])
            memset(CVPixelBufferGetBaseAddress(buffer!), Int32(index * 10), CVPixelBufferGetBytesPerRow(buffer!) * 200)
            CVPixelBufferUnlockBaseAddress(buffer!, [])
            check(adaptor.append(buffer!, withPresentationTime: CMTime(value: Int64(index), timescale: 12)), "append video frame")
        }
        input.markAsFinished(); await writer.finishWriting()
        check(writer.status == .completed, "video fixture finishes")
    }
    @MainActor static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("macspaces-file-check-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("transparent.tiff"), second = root.appendingPathComponent("second.png")
        let bad = root.appendingPathComponent("broken.png"), animation = root.appendingPathComponent("animated.gif")
        try image(source, type: .tiff); try image(second); try image(animation, type: .gif, frames: 2)
        try Data("not an image".utf8).write(to: bad)
        let localCancelled = Task { try await LocalFileTools.process(source, operation: .extractText) }
        localCancelled.cancel()
        do { _ = try await localCancelled.value; preconditionFailure("Cancelled local tool must not run") }
        catch is CancellationError {} catch { preconditionFailure("Local tool must report cancellation") }
        let original = try Data(contentsOf: source)
        let partial = await FileConverter.runBatch(action("image.png"), on: [source, bad, second]) { _ in }
        check(partial.outputs.count == 2 && partial.issues.count == 1 && partial.issues[0].url == bad, "mixed batch keeps both successes and names failure")
        let retainedOriginal = try Data(contentsOf: source)
        check(retainedOriginal == original, "original unchanged")
        let alpha = CGImageSourceCopyPropertiesAtIndex(CGImageSourceCreateWithURL(partial.outputs[0] as CFURL, nil)!, 0, nil) as! [CFString: Any]
        check(alpha[kCGImagePropertyHasAlpha] as? Bool == true, "PNG preserves transparency")
        let flattened = await FileConverter.runBatch(action("image.png"), on: [animation]) { _ in }
        check(flattened.outputs.isEmpty && flattened.issues.count == 1, "animated conversion refuses implicit frame loss")
        let still = await FileConverter.runBatch(action("tool.firstframe"), on: [animation]) { _ in }
        check(still.outputs.count == 1 && !FileConverter.isMultiFrame(still.outputs[0]), "explicit first frame")
        let compressed = await FileConverter.runBatch(action("tool.compress"), on: [source]) { _ in }
        check(compressed.outputs.count == 1, "compress fixture")
        let compressedBytes = try Data(contentsOf: compressed.outputs[0])
        check(compressedBytes.count < original.count && compressed.outputs[0].pathExtension == "png", "compression smaller and alpha-safe")
        let crop = await FileConverter.runBatch(action("preset.resize", options: .init(maximumDimension: 200, cropRatio: 1)), on: [source]) { _ in }
        let cropped = CGImageSourceCopyPropertiesAtIndex(CGImageSourceCreateWithURL(crop.outputs[0] as CFURL, nil)!, 0, nil) as! [CFString: Any]
        check(cropped[kCGImagePropertyPixelWidth] as? Int == cropped[kCGImagePropertyPixelHeight] as? Int, "square crop")
        check((cropped[kCGImagePropertyPixelWidth] as? Int ?? 1000) <= 200, "resize limit")
        let invalid = await FileConverter.runBatch(action("preset.gif", options: .init(gifFPS: .nan)), on: [source]) { _ in }
        check(invalid.outputs.isEmpty && invalid.issues.count == 1, "invalid finite settings rejected")
        async let first = FileConverter.runBatch(action("image.png"), on: [source]) { _ in }
        async let other = FileConverter.runBatch(action("image.png"), on: [source]) { _ in }
        let collision = await (first, other)
        check(collision.0.outputs.count == 1 && collision.1.outputs.count == 1 && collision.0.outputs != collision.1.outputs, "concurrent outputs never overwrite")
        let cancelled = Task { await FileConverter.runBatch(action("image.png"), on: [source, second]) { _ in } }
        cancelled.cancel()
        let cancellation = await cancelled.value
        check(cancellation.cancelled && cancellation.outputs.isEmpty && cancellation.remaining == [source, second], "cancellation keeps retry inputs")
        let document = PDFDocument()
        for _ in 0..<2 { document.insert(PDFPage(image: NSImage(contentsOf: second)!)!, at: document.pageCount) }
        let pdf = root.appendingPathComponent("two.pdf"); check(document.write(to: pdf), "PDF fixture")
        let pages = await FileConverter.runBatch(action("pdf.png"), on: [pdf]) { _ in }
        check(pages.outputs.count == 1 && pages.issues.isEmpty, "PDF folder result commits")
        let exportedPages = try FileManager.default.contentsOfDirectory(at: pages.outputs[0], includingPropertiesForKeys: nil)
        check(exportedPages.count == 2, "all PDF pages present")
        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        check(!files.contains { $0.lastPathComponent.hasPrefix(".macspaces-") }, "no abandoned staging files")
        let invalidPDF = root.appendingPathComponent("broken.pdf"); try Data("bad".utf8).write(to: invalidPDF)
        let merge = await FileConverter.runBatch(action("tool.merge"), on: [pdf, invalidPDF]) { _ in }
        check(merge.outputs.isEmpty && merge.issues.count == 2, "combined job cannot report partial merge as success")
        let movie = root.appendingPathComponent("fixture.mov")
        try await video(movie)
        let gif = await FileConverter.runBatch(action("preset.gif", options: .init(maximumDimension: 120, gifStart: 0.5, gifDuration: 1, gifFPS: 4)), on: [movie]) { _ in }
        check(gif.outputs.count == 1 && gif.issues.isEmpty, "custom GIF export")
        let gifSource = CGImageSourceCreateWithURL(gif.outputs[0] as CFURL, nil)!
        check(CGImageSourceGetCount(gifSource) == 4, "custom GIF frame count and duration")
        let gifProperties = CGImageSourceCopyPropertiesAtIndex(gifSource, 0, nil) as! [CFString: Any]
        check((gifProperties[kCGImagePropertyPixelWidth] as? Int ?? 1000) <= 120, "custom GIF edge")
        let nativeVideo = await FileConverter.runBatch(action("video.mp4"), on: [movie]) { _ in }
        check(nativeVideo.outputs.count == 1 && nativeVideo.issues.isEmpty, "native video export")
        let cancelControl = CancellationControl()
        cancelControl.task = Task {
            await FileConverter.runBatch(action("preset.gif", options: .init(maximumDimension: 320, gifDuration: 2, gifFPS: 12)), on: [movie]) { progress in
                if progress > 0 && progress < 1 { cancelControl.task?.cancel() }
            }
        }
        let midJob = await cancelControl.task!.value
        check(midJob.cancelled && midJob.outputs.isEmpty && midJob.remaining == [movie], "mid-export cancellation rolls back incomplete output")
        let finalFiles = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        check(!finalFiles.contains { $0.lastPathComponent.hasPrefix(".macspaces-") }, "mid-export cancellation clears staging")
        let huge = PDFDocument(); let hugePage = PDFPage(image: NSImage(contentsOf: second)!)!
        hugePage.setBounds(CGRect(x: 0, y: 0, width: 40000, height: 40000), for: .mediaBox); huge.insert(hugePage, at: 0)
        let hugeURL = root.appendingPathComponent("oversized.pdf"); check(huge.write(to: hugeURL), "oversized PDF fixture")
        let oversized = await FileConverter.runBatch(action("pdf.png"), on: [hugeURL]) { _ in }
        check(oversized.outputs.isEmpty && oversized.issues.count == 1, "oversized PDF fails before allocating bitmap")
        var tracker = CompletedFileTracker(existing: [source])
        let now = Date(), partialURL = root.appendingPathComponent("browser.crdownload")
        let zero = root.appendingPathComponent("empty"), next = root.appendingPathComponent("new.pdf")
        let fp = CompletedFileTracker.Fingerprint(bytes: 12, modified: now)
        let candidates = [source: fp, partialURL: fp, zero: .init(bytes: 0, modified: now), next: fp]
        check(tracker.poll(candidates, at: now).isEmpty, "no immediate watcher completion")
        check(tracker.poll(candidates, at: now.addingTimeInterval(5)).isEmpty, "stability wait")
        check(tracker.poll(candidates, at: now.addingTimeInterval(6)) == [next], "only new completed files")
        check(tracker.poll(candidates, at: now.addingTimeInterval(20)).isEmpty, "watcher emits each path once")
        let growing = root.appendingPathComponent("growing.pdf")
        check(tracker.poll([growing: fp], at: now).isEmpty, "growing starts wait")
        check(tracker.poll([growing: .init(bytes: 15, modified: now)], at: now.addingTimeInterval(7)).isEmpty, "growth resets stability")
        check(tracker.poll([growing: .init(bytes: 15, modified: now)], at: now.addingTimeInterval(13)) == [growing], "stable final file emits")
        print("File tools and completed-file watcher checks passed")
    }
}
