import Foundation

/// The XPC contract between MacSpaces and `MacSpacesVoiceHelper` (Contents/XPCServices), the
/// process that runs Siren's speaker sorting and voice models, so the notch app never loads MLX
/// or a model. Requests and replies are JSON (`VoiceHelperMessage`); errors come back as one
/// line to show. The helper does one job at a time and quits when it has been idle a while.
@objc protocol VoiceHelperProtocol {
    /// Downloads a `VoiceModel` (by id) into `hub` from Hugging Face, resuming a part-way download.
    func download(model: String, hub: String, reply: @escaping (String?) -> Void)
    /// `VoiceHelperMessage.SortRequest` in, `SortResult` out.
    func sort(_ request: Data, reply: @escaping (Data?, String?) -> Void)
    /// `VoiceHelperMessage.SpeakRequest` in, the path of the WAV it wrote out.
    func speak(_ request: Data, reply: @escaping (String?, String?) -> Void)
    /// `VoiceHelperMessage.LikenessRequest` in, `LikenessResult` out: how alike files sound to a
    /// clip or a fingerprint, by the fingerprint model. The side-by-side harness asks
    /// (`Scripts/compare-siren.sh`), and a voice's clips from earlier versions are measured once
    /// before it first reads.
    func likeness(_ request: Data, reply: @escaping (Data?, String?) -> Void)
    /// `VoiceHelperMessage.TakeRequest` in, a `Person` out: Record My Voice's take made into a clip
    /// the way sorting makes one (noise reduction, words, the sample checks' evidence).
    func prepare(_ request: Data, reply: @escaping (Data?, String?) -> Void)
    /// Stops the job running, if any; its reply then comes back with an error.
    func cancel()
}

/// What the app hears while a job runs.
@objc protocol VoiceHelperClientProtocol {
    func progress(_ stage: String, fraction: Double)
}

enum VoiceHelperMessage {
    struct SortRequest: Codable, Sendable {
        /// The recordings, read and never changed.
        let files: [String]
        /// Where the found people's clips go (emptied first).
        let output: String
        let hub: String
    }

    struct Person: Codable, Sendable, Equatable, Identifiable {
        let id: Int
        /// "Host", "Guest 1" or "Main voice" from the recording it was heard most in.
        let label: String
        /// Seconds of them talking on their own, across every recording.
        let seconds: Double
        let recordings: Int
        /// The cleanest stretch, cut on word boundaries: what a voice made from them copies.
        let clip: String
        /// Exactly what the clip says; empty if nothing could be written down.
        let transcript: String
        let fingerprint: [Float]?
        /// What would make the voice better, when something would.
        let note: String?
        /// Clips for Siren's other deliveries (Slow and Soft, Upbeat), when enough clear stretches
        /// of them differed; nil or empty for one clip.
        var deliveries: [VoiceDelivery.Clip]? = nil
        /// What was measured of `clip`, for choosing between a voice's clips.
        var evidence: VoiceSamples.Evidence? = nil
    }

    struct SortResult: Codable, Sendable {
        let people: [Person]
        /// Files that couldn't be used, with why.
        let skipped: [String]
    }

    struct SpeakRequest: Codable, Sendable {
        let text: String
        let clip: String
        let transcript: String
        let engine: String
        let hub: String
        let output: String
        /// The random seed the engine samples with, so each take of the same words differs (and
        /// the same seed makes the same take again). Nil leaves the engine's own randomness.
        var seed: UInt64? = nil
        /// A delivery for an engine that follows one (CosyVoice 3); other engines ignore it.
        var style: String? = nil
        /// Best Quality: attempts at each piece, the one most like the voice kept (`TakeChoice`,
        /// at most `TakeChoice.attempts`). Nil or 1 makes one, as Fast.
        var takes: Int? = nil
    }

    /// A take of you reading `script` aloud (Record My Voice), in the Voices folder.
    struct TakeRequest: Codable, Sendable {
        let file: String
        /// The passage read, so a take whose words can't be confirmed says so.
        let script: String
        /// Where the clip goes (emptied first).
        let output: String
        let hub: String
    }

    struct LikenessRequest: Codable, Sendable {
        /// The clip the files are measured against (ignored with `fingerprint`).
        let reference: String
        let files: [String]
        let hub: String
        /// A person's fingerprint to measure the files against instead of `reference`'s.
        var fingerprint: [Float]? = nil
    }

    struct LikenessResult: Codable, Sendable {
        /// Cosine likeness of each file's fingerprint to the reference's, in order; nil where one
        /// couldn't be measured.
        let likeness: [Double?]
    }
}
