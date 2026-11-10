import AVFoundation

/// Studio's audio work, done off the main thread: a take's length, and Siren's pace change
/// (quicker or slower without changing the pitch), rendered offline into a new WAV.
enum StudioAudio {
    enum Failure: LocalizedError {
        case unreadable
        var errorDescription: String? { "The take's audio couldn't be read." }
    }

    static func seconds(of url: URL) -> Double {
        guard let file = try? AVAudioFile(forReading: url), file.processingFormat.sampleRate > 0 else { return 0 }
        return Double(file.length) / file.processingFormat.sampleRate
    }

    /// `input` played at `rate` (0.75 to 1.25), its pitch kept, written to `output`.
    static func paced(_ input: URL, rate: Double, to output: URL) throws {
        let file = try AVAudioFile(forReading: input)
        let format = file.processingFormat
        guard format.sampleRate > 0, file.length > 0 else { throw Failure.unreadable }
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let pitch = AVAudioUnitTimePitch()
        pitch.rate = Float(rate)
        engine.attach(player)
        engine.attach(pitch)
        engine.connect(player, to: pitch, format: format)
        engine.connect(pitch, to: engine.mainMixerNode, format: format)
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)
        try engine.start()
        defer { player.stop(); engine.stop() }
        player.scheduleFile(file, at: nil)
        player.play()
        let rendering = engine.manualRenderingFormat
        let written = try AVAudioFile(forWriting: output, settings: rendering.settings,
                                      commonFormat: rendering.commonFormat, interleaved: rendering.isInterleaved)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: rendering, frameCapacity: 4096) else { throw Failure.unreadable }
        // The pace change holds back a little at the start, so a tenth of a second more keeps the last word.
        let total = AVAudioFramePosition(Double(file.length) / rate + format.sampleRate * 0.1)
        var stalls = 0
        while engine.manualRenderingSampleTime < total {
            let frames = AVAudioFrameCount(min(Int64(buffer.frameCapacity), total - engine.manualRenderingSampleTime))
            switch try engine.renderOffline(frames, to: buffer) {
            case .success: try written.write(from: buffer)
            case .insufficientDataFromInputNode, .cannotDoInCurrentContext:
                stalls += 1
                if stalls > 100 { throw Failure.unreadable }
            case .error: throw Failure.unreadable
            @unknown default: throw Failure.unreadable
            }
        }
    }
}
