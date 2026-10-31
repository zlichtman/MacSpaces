// Records only the isolated demo window. Other apps, the desktop and pointer are excluded.
import AppKit
import ScreenCaptureKit
import AVFoundation

final class Recorder: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let writer: AVAssetWriter
    let input: AVAssetWriterInput
    let queue = DispatchQueue(label: "MacSpaces.demo.video")
    var pixelPool: CVPixelBufferPool?
    var signalPrefix = ""
    var first: CMTime?
    var firstDate: Date?
    var lastSample: CMSampleBuffer?
    var frames = 0
    var failure: Error?

    init(output: URL, width: Int, height: Int) throws {
        writer = try AVAssetWriter(outputURL: output, fileType: .mov)
        input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width, AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 24_000_000,
                                               AVVideoExpectedSourceFrameRateKey: 60,
                                               AVVideoMaxKeyFrameIntervalKey: 60,
                                               AVVideoAllowFrameReorderingKey: false]
        ])
        input.expectsMediaDataInRealTime = true
        guard writer.canAdd(input) else { throw NSError(domain: "DemoRecorder", code: 1) }
        writer.add(input)
        super.init()
        let attributes: [String: Any] = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]]
        guard CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attributes as CFDictionary, &pixelPool) == kCVReturnSuccess else {
            throw NSError(domain: "DemoRecorder.pixelPool", code: 8)
        }
    }
    func stream(_ stream: SCStream, didStopWithError error: Error) { failure = error }
    func stream(_ stream: SCStream, didOutputSampleBuffer sample: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sample.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int,
              SCFrameStatus(rawValue: raw) == .complete else { return }
        if first == nil {
            first = sample.presentationTimeStamp
            firstDate = Date()
            guard writer.startWriting() else { failure = writer.error; return }
            writer.startSession(atSourceTime: sample.presentationTimeStamp)
            try? Data().write(to: URL(fileURLWithPath: signalPrefix + ".ready"))
        }
        guard input.isReadyForMoreMediaData else {
            failure = NSError(domain: "DemoRecorder.encoderBackpressure", code: 2)
            return
        }
        guard let owned = copyFrame(sample) else {
            failure = NSError(domain: "DemoRecorder.copyFrame", code: 9)
            return
        }
        lastSample = owned
        if input.append(owned) { frames += 1 } else { failure = writer.error }
    }
    /// ScreenCaptureKit owns its IOSurfaces and can clear them at stream shutdown.
    /// The encoder and held final frame must retain pixels in our own pool instead.
    private func copyFrame(_ sample: CMSampleBuffer) -> CMSampleBuffer? {
        guard let source = sample.imageBuffer, let pixelPool else { return nil }
        var copy: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pixelPool, &copy) == kCVReturnSuccess,
              let copy else { return nil }
        CVPixelBufferLockBaseAddress(source, .readOnly)
        CVPixelBufferLockBaseAddress(copy, [])
        defer { CVPixelBufferUnlockBaseAddress(copy, []); CVPixelBufferUnlockBaseAddress(source, .readOnly) }
        guard let src = CVPixelBufferGetBaseAddress(source), let dst = CVPixelBufferGetBaseAddress(copy) else { return nil }
        let srcStride = CVPixelBufferGetBytesPerRow(source), dstStride = CVPixelBufferGetBytesPerRow(copy)
        let rows = CVPixelBufferGetHeight(source), bytes = CVPixelBufferGetWidth(source) * 4
        guard rows == CVPixelBufferGetHeight(copy), bytes <= srcStride, bytes <= dstStride else { return nil }
        for y in 0..<rows { memcpy(dst.advanced(by: y * dstStride), src.advanced(by: y * srcStride), bytes) }
        CVBufferPropagateAttachments(source, copy)
        var format: CMVideoFormatDescription?
        guard CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: copy,
            formatDescriptionOut: &format) == noErr, let format else { return nil }
        var timing = CMSampleTimingInfo(duration: sample.duration, presentationTimeStamp: sample.presentationTimeStamp,
                                       decodeTimeStamp: .invalid)
        var result: CMSampleBuffer?
        guard CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: copy,
            formatDescription: format, sampleTiming: &timing, sampleBufferOut: &result) == noErr else { return nil }
        return result
    }

    func finish() async throws {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                // A still window may send only one complete frame. Extend its last sample to the
                // actual stop time so static captures have the same honest timeline as moving ones.
                if let sample = self.lastSample, let first = self.first, let began = self.firstDate {
                    var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 60),
                        presentationTimeStamp: CMTimeAdd(first, CMTime(seconds: Date().timeIntervalSince(began), preferredTimescale: 600)),
                        decodeTimeStamp: .invalid)
                    var final: CMSampleBuffer?
                    if CMSampleBufferCreateCopyWithNewTiming(allocator: kCFAllocatorDefault, sampleBuffer: sample,
                        sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleBufferOut: &final) == noErr,
                       let final, self.input.isReadyForMoreMediaData {
                        if !self.input.append(final) { self.failure = self.writer.error }
                    }
                }
                self.lastSample = nil
                self.input.markAsFinished(); continuation.resume()
            }
        }
        guard frames > 0 else { throw NSError(domain: "DemoRecorder.noFrames", code: 3) }
        await writer.finishWriting()
        if let failure { throw failure }
        guard writer.status == .completed else { throw writer.error ?? NSError(domain: "DemoRecorder.encode", code: 4) }
    }
}

@main @MainActor struct Capture {
    static func main() async {
        do {
            // ScreenCaptureKit needs a WindowServer connection even in a command-line helper.
            _ = NSApplication.shared
            NSApp.setActivationPolicy(.prohibited)
            let args = CommandLine.arguments
            if args.count == 3, args[1] == "--verify-image" {
                guard let bitmap = NSBitmapImageRep(data: try Data(contentsOf: URL(fileURLWithPath: args[2]))),
                      bitmap.pixelsWide == 1640, bitmap.pixelsHigh == 940 else {
                    throw NSError(domain: "Invalid capture image", code: 10)
                }
                var sum = 0.0, count = 0, maximum = 0.0
                for y in stride(from: 8, to: 940, by: 24) { for x in stride(from: 8, to: 1640, by: 24) {
                    if let c = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) {
                        let value = Double((c.redComponent + c.greenComponent + c.blueComponent) / 3)
                        sum += value; count += 1; maximum = max(maximum, value)
                    }
                } }
                guard count > 0, sum / Double(count) > 0.015, maximum > 0.15 else {
                    throw NSError(domain: "Capture is empty or dark; refusing to replace assets", code: 11)
                }
                return
            }
            if args.count == 3, args[1] == "--verify-star" {
                guard let bitmap = NSBitmapImageRep(data: try Data(contentsOf: URL(fileURLWithPath: args[2]))), bitmap.pixelsWide == 1640, bitmap.pixelsHigh == 940 else {
                    throw NSError(domain: "Invalid Music poster", code: 6)
                }
                var yellow = 0
                for y in 310..<490 { for x in 1000..<1200 {
                    if let c = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                       c.redComponent > 0.65, c.greenComponent > 0.45, c.blueComponent < 0.4, c.alphaComponent > 0.8 {
                        yellow += 1
                    }
                } }
                guard yellow > 200 else { throw NSError(domain: "Music poster is missing its star scene; refusing to replace published assets", code: 7) }
                print("Verified visible native star scene (\(yellow) pixels)")
                return
            }
            if args.count == 2, args[1] == "--check" {
                guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
                    throw NSError(domain: "Enable Screen Recording for the capture terminal in System Settings, then rerun", code: 1)
                }
                print("Screen Recording access is ready")
                return
            }
            guard args.count == 6, let id = UInt32(args[1]), let width = Int(args[3]), let height = Int(args[4]) else {
                throw NSError(domain: "Usage: record-window WINDOW_ID OUTPUT WIDTH HEIGHT SIGNAL_PREFIX", code: 1)
            }
            guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
                throw NSError(domain: "Enable Screen Recording for the capture terminal in System Settings, then rerun", code: 1)
            }
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            guard let window = content.windows.first(where: { $0.windowID == id && $0.owningApplication?.bundleIdentifier == "dev.opensource.MacSpaces.WebsiteDemo" }) else {
                throw NSError(domain: "Isolated demo window is not available", code: 1)
            }
            let config = SCStreamConfiguration()
            config.width = width; config.height = height
            config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
            config.queueDepth = 5; config.showsCursor = false; config.capturesAudio = false
            config.pixelFormat = kCVPixelFormatType_32BGRA
            config.scalesToFit = true
            if #available(macOS 14.0, *) { config.ignoreShadowsSingleWindow = true }
            let recorder = try Recorder(output: URL(fileURLWithPath: args[2]), width: width, height: height)
            recorder.signalPrefix = args[5]
            let stream = SCStream(filter: SCContentFilter(desktopIndependentWindow: window), configuration: config, delegate: recorder)
            try stream.addStreamOutput(recorder, type: .screen, sampleHandlerQueue: recorder.queue)
            try await stream.startCapture()
            let prefix = args[5]
            let deadline = Date().addingTimeInterval(120)
            while !FileManager.default.fileExists(atPath: prefix + ".stop") {
                guard Date() < deadline else { throw NSError(domain: "DemoRecorder.timelineTimeout", code: 5) }
                try await Task.sleep(nanoseconds: 50_000_000)
            }
            try await stream.stopCapture()
            try await recorder.finish()
            print("Recorded \(recorder.frames) native frames")
        } catch {
            fputs("Capture failed: \(error)\n", stderr)
            exit(1)
        }
    }
}
