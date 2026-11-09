import AVFoundation
import AudioToolbox
import Darwin
import Foundation

/// Bounded, file-only PCM reads shared by analysis and saved-timeline cleanup.
/// In macOS 27, AVAudioFile reports -39 when asked to read past EOF; reaching
/// the declared end is normal and must not trigger an extra read.
enum AudioFileReader {
    enum Failure: LocalizedError {
        case unreadable, endedEarly, conversionFailed, sameFile
        var errorDescription: String? {
            switch self {
            case .unreadable:
                "This recording couldn't be read. Try another copy of the audio file."
            case .endedEarly:
                "This recording ended before all of its audio could be read. The original and existing samples are kept. Try Again, or choose another copy of the recording."
            case .conversionFailed:
                "This recording's audio couldn't be prepared. Try an .m4a, .mp3 or .wav copy."
            case .sameFile:
                "Choose a different destination so the original recording stays intact."
            }
        }
    }

    /// Keeps the decoder's actual error available for diagnostics while the
    /// UI gets a useful explanation instead of a raw operating-system code.
    struct DecoderFailure: LocalizedError {
        let reason: Failure
        let underlying: Error
        var errorDescription: String? { reason.errorDescription }
    }

    /// Clears the previous buffer and reads only frames which still exist.
    /// Early EOF and all unrelated errors remain failures. Some decoder
    /// versions report EOF together with the entire valid final buffer; that
    /// complete tail is usable, but a partial failed read is never invented.
    @discardableResult
    static func readAvailableFrames(from file: AVAudioFile, into buffer: AVAudioPCMBuffer,
                                    maximumFrames: AVAudioFrameCount? = nil) throws -> Bool {
        try Task.checkCancellation()
        buffer.frameLength = 0
        let position = file.framePosition
        let length = file.length
        guard position >= 0, length >= 0 else { throw Failure.unreadable }
        guard position < length else { return false }
        let capacity = min(buffer.frameCapacity, maximumFrames ?? buffer.frameCapacity)
        guard capacity > 0 else { throw Failure.unreadable }
        let requested = AVAudioFrameCount(min(AVAudioFramePosition(capacity), length - position))
        do {
            try file.read(into: buffer, frameCount: requested)
        } catch {
            let failure = error as NSError
            if failure.domain == NSOSStatusErrorDomain && failure.code == Int(kAudioFileEndOfFileError) {
                guard buffer.frameLength == requested, file.framePosition >= length else {
                    throw DecoderFailure(reason: .endedEarly, underlying: error)
                }
            } else { throw DecoderFailure(reason: .unreadable, underlying: error) }
        }
        guard buffer.frameLength > 0 else {
            if file.framePosition < length { throw Failure.endedEarly }
            return false
        }
        return true
    }

    /// Converts mono blocks without retaining the recording. maximumSeconds
    /// is an exact output cap; end-of-stream is still drained to preserve the
    /// converter's valid tail when the whole file is requested.
    ///
    /// With `recovered`, a file that stops being readable part-way (a cut-off
    /// download, a damaged copy) keeps everything before the damage. A failed
    /// read is retried from the same place in blocks halving from 10 ms down to
    /// 16 frames (blocks grow back after each success, so this costs a few
    /// dozen reads around the damage, however long the file). Decoding stops
    /// where even the smallest block fails, and `recovered` gets the seconds of
    /// the original that were read. Nothing past the damage is skipped to or
    /// invented, so the audio is always an exact start of the recording, and
    /// reading again at another rate stops at the same place. It throws only if
    /// nothing could be decoded. Without `recovered`, any read error throws.
    @discardableResult
    static func streamMono(_ source: URL, sampleRate: Double, maximumSeconds: Double = .infinity,
                           blockFrames: AVAudioFrameCount = 8_192, quality: AVAudioQuality? = nil,
                           recovered: ((Double) -> Void)? = nil,
                           progress: (Double) -> Void = { _ in },
                           sink: ([Float]) throws -> Void) throws -> Int {
        try Task.checkCancellation()
        guard sampleRate.isFinite, sampleRate > 0, maximumSeconds >= 0,
              !maximumSeconds.isNaN, blockFrames > 0, blockFrames <= 131_072 else { throw Failure.unreadable }
        let limit: Int?
        if maximumSeconds.isFinite {
            let frames = maximumSeconds * sampleRate
            guard frames.isFinite, frames < Double(Int.max) else { throw Failure.unreadable }
            limit = Int(frames)
            if limit == 0 { return 0 }
        } else { limit = nil }
        var input: AVAudioFile
        do { input = try AVAudioFile(forReading: source) }
        catch { throw DecoderFailure(reason: .unreadable, underlying: error) }
        defer { input.close() }
        let format = input.processingFormat
        guard input.length > 0, format.sampleRate.isFinite, format.sampleRate > 0, format.channelCount > 0,
              let output = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: format, to: output),
              let read = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: blockFrames),
              let converted = AVAudioPCMBuffer(pcmFormat: output, frameCapacity: blockFrames * 8) else { throw Failure.unreadable }
        converter.downmix = true
        if let quality { converter.sampleRateConverterQuality = quality.rawValue }
        let smallBlock = AVAudioFrameCount(max(16, min(Double(blockFrames), format.sampleRate / 100)))
        var ended = false
        var count = 0
        // Recovery: after a failed read, reads are capped at `salvageBlock`,
        // which halves on each failure and doubles back on each success.
        var salvageBlock: AVAudioFrameCount?
        var damage: Error?
        var readableFrames: AVAudioFramePosition?
        while limit.map({ count < $0 }) ?? true {
            try Task.checkCancellation()
            let previousPosition = input.framePosition
            converted.frameLength = 0
            var readError: Error?
            var conversionError: NSError?
            let status = converter.convert(to: converted, error: &conversionError) { requested, state in
                guard !ended else { state.pointee = .endOfStream; return nil }
                let wanted = max(1, requested)
                let start = input.framePosition
                do {
                    if try readAvailableFrames(from: input, into: read, maximumFrames: min(wanted, salvageBlock ?? wanted)) {
                        if let block = salvageBlock { salvageBlock = block < blockFrames / 2 ? block * 2 : nil }
                        state.pointee = .haveData
                        return read
                    }
                } catch let failure where recovered != nil && !(failure is CancellationError) {
                    var size = min(wanted, salvageBlock.map { $0 / 2 } ?? smallBlock)
                    while size >= min(16, wanted) {
                        // A failed read can leave the decoder refusing every
                        // later read, so each retry starts from a fresh open.
                        guard let fresh = try? AVAudioFile(forReading: source) else { break }
                        input.close()
                        input = fresh
                        input.framePosition = start
                        if (try? readAvailableFrames(from: input, into: read, maximumFrames: size)) == true {
                            salvageBlock = size
                            state.pointee = .haveData
                            return read
                        }
                        size /= 2
                    }
                    damage = failure
                    readableFrames = start
                } catch { readError = error }
                ended = true
                state.pointee = .endOfStream
                return nil
            }
            if let readError { throw readError }
            if let conversionError { throw DecoderFailure(reason: .conversionFailed, underlying: conversionError) }
            if status == .error { throw Failure.conversionFailed }
            let available = Int(converted.frameLength)
            let amount = min(available, limit.map { $0 - count } ?? available)
            if amount > 0 {
                guard let samples = converted.floatChannelData?[0] else { throw Failure.conversionFailed }
                try sink(Array(UnsafeBufferPointer(start: samples, count: amount)))
                count += amount
            }
            progress(min(1, Double(input.framePosition) / Double(input.length)))
            if status == .endOfStream || (ended && converted.frameLength == 0) { break }
            if amount == 0, input.framePosition == previousPosition, !ended { throw Failure.conversionFailed }
        }
        try Task.checkCancellation()
        if let readableFrames, let recovered {
            guard count > 0 else { throw damage ?? Failure.unreadable }
            recovered(Double(readableFrames) / format.sampleRate)
        }
        return count
    }

    /// Publishes a decoded WAV only once it holds at least `minimumSeconds`.
    /// Cancelling or failing keeps any previous destination and removes the
    /// same-directory partial file. A damaged original is read up to the damage,
    /// so a saved timeline first made from that readable start still fits, while
    /// one that needs more than is now readable fails instead of shifting.
    @discardableResult
    static func writeMono(_ source: URL, to destination: URL, sampleRate: Double, minimumSeconds: Double = 0,
                          progress: (Double) -> Void = { _ in }) throws -> Int {
        guard source.isFileURL, destination.isFileURL,
              source.standardizedFileURL.resolvingSymlinksInPath() != destination.standardizedFileURL.resolvingSymlinksInPath()
        else { throw Failure.sameFile }
        try Task.checkCancellation()
        guard sampleRate.isFinite, sampleRate > 0, minimumSeconds.isFinite, minimumSeconds >= 0,
              let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)
        else { throw Failure.conversionFailed }
        let partial = destination.deletingLastPathComponent().appendingPathComponent(".siren-decode-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: partial) }
        var output: AVAudioFile? = try AVAudioFile(forWriting: partial, settings: format.settings,
                                                commonFormat: .pcmFormatFloat32, interleaved: false)
        defer { output?.close() }
        let frames = try streamMono(source, sampleRate: sampleRate, recovered: { _ in }, progress: progress) { samples in
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
                  let data = buffer.floatChannelData?[0], let output else { throw Failure.conversionFailed }
            buffer.frameLength = AVAudioFrameCount(samples.count)
            samples.withUnsafeBufferPointer { if let base = $0.baseAddress { data.update(from: base, count: samples.count) } }
            try output.write(from: buffer)
        }
        output?.close()
        output = nil
        guard frames > 0 else { throw Failure.unreadable }
        guard Double(frames) / sampleRate >= minimumSeconds else { throw Failure.endedEarly }
        try Task.checkCancellation()
        let replaced = partial.withUnsafeFileSystemRepresentation { from in
            destination.withUnsafeFileSystemRepresentation { to in rename(from!, to!) }
        }
        guard replaced == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        return frames
    }
}
