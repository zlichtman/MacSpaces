import Foundation

/// One downloadable model for voices from recordings (Settings → Tsukumo → Voice): the
/// speaker-sorting pair, music removal for sorting, or one of Siren's three voice engines. Foundation only: the app lists,
/// sizes and removes downloads with it, and the voice helper downloads and loads them.
struct VoiceModel: Identifiable, Equatable, Hashable, Sendable {
    enum Runtime: String, Sendable { case sorting, musicRemoval, qwen, cosyVoice }

    /// Stable: saved in `voices.engine`.
    let id: String
    let title: String
    let goodAt: String
    let modelName: String
    let runtime: Runtime
    /// Every Hugging Face repository it needs, the model's own first.
    let parts: [String]
    /// Repositories downloaded with it that improve it but aren't needed: an install from before
    /// they were added keeps working without them until Download is pressed again (Update).
    var extras: [String] = []
    /// The files it downloads, from the repositories' listings.
    let downloadBytes: Int64
    /// Peak memory while it runs, in GB (Siren's measurements and estimates).
    let peakGB: Double
    let licence: String

    var repo: String { parts[0] }
    /// Everything Download fetches.
    var allParts: [String] { parts + extras }
    var speaks: Bool { runtime == .qwen || runtime == .cosyVoice }

    static func == (a: Self, b: Self) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    static let diarizerRepo = "mlx-community/diar_streaming_sortformer_4spk-v2.1-fp16"
    static let fingerprintRepo = "aufklarer/WeSpeaker-ResNet34-LM-MLX"
    /// Siren's light noise reduction for the clips sorting cuts (DeepFilterNet 3; the repository
    /// keeps each version in a folder of its own, 26 MB in all).
    static let enhancerRepo = "mlx-community/DeepFilterNet-mlx"
    /// Siren's music removal (SAM-Audio small, Meta), used as a mask on the original sound.
    static let separatorRepo = "mlx-community/sam-audio-small-fp16"

    /// Needed to sort recordings into people: Sortformer says who talks when, WeSpeaker tells voices
    /// apart, and DeepFilterNet takes the edge off the clips' background noise.
    static let sorting = VoiceModel(
        id: "sorting", title: "Finding voices",
        goodAt: "Separates the speakers in recordings and sorts them into people.",
        modelName: "Sortformer v2.1 and WeSpeaker", runtime: .sorting,
        parts: [diarizerRepo, fingerprintRepo], extras: [enhancerRepo], downloadBytes: 288_230_292, peakGB: 3.7,
        licence: "NVIDIA Open Model License, CC BY 4.0, DeepFilterNet MIT or Apache 2.0")

    /// Optional, and big, so not part of Finding voices: sorting takes music out from under
    /// someone talking (Siren's measured peak 3.2-3.5 GB, loaded only while cleaning).
    static let musicRemoval = VoiceModel(
        id: "music-removal", title: "Music removal",
        goodAt: "Takes music out from under talk, so more of a recording is usable.",
        modelName: "SAM-Audio small", runtime: .musicRemoval,
        parts: [separatorRepo], downloadBytes: 1_204_739_882, peakGB: 3.5,
        licence: "Meta SAM License")

    static let standard = VoiceModel(
        id: "standard", title: "Standard",
        goodAt: "The closest copy of the voice. Best for most replies.",
        modelName: "Qwen3-TTS 1.7B", runtime: .qwen,
        parts: ["mlx-community/Qwen3-TTS-12Hz-1.7B-Base-8bit"], downloadBytes: 3_104_158_788, peakGB: 5.0,
        licence: "Apache 2.0")

    static let standardSmall = VoiceModel(
        id: "standard-small", title: "Standard (small)",
        goodAt: "The same engine in a smaller size, for Macs with 8 GB of memory.",
        modelName: "Qwen3-TTS 0.6B", runtime: .qwen,
        parts: ["mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit"], downloadBytes: 1_991_296_593, peakGB: 3.0,
        licence: "Apache 2.0")

    static let expressive = VoiceModel(
        id: "expressive", title: "Expressive",
        goodAt: "Livelier delivery that follows the recording's mood.",
        modelName: "CosyVoice 3 0.5B", runtime: .cosyVoice,
        parts: ["aufklarer/CosyVoice3-0.5B-MLX-bf16", "aufklarer/CamPlusPlus-Speaker-CoreML"],
        downloadBytes: 2_267_679_874, peakGB: 4.0, licence: "Apache 2.0")

    /// In list order: sorting first, since every voice starts there, then its music removal.
    static let catalogue: [VoiceModel] = [.sorting, .musicRemoval, .standard, .standardSmall, .expressive]
    static let engines: [VoiceModel] = catalogue.filter(\.speaks)

    static func named(_ id: String?) -> VoiceModel? { catalogue.first { $0.id == id } }

    /// Speaking may use up to this share of the Mac's memory (Siren's rule): it keeps Standard's
    /// 5 GB peak within 16 GB Macs and gives 8 GB Macs Standard (small).
    static let memoryShare = 0.4

    func fits(memoryBytes: UInt64) -> Bool { peakGB <= Self.memoryShare * Double(memoryBytes) / 1_073_741_824 }

    /// The engine replies use: the one chosen under `voices.engine` while it's downloaded, else
    /// the closest copy this Mac can run that is downloaded, else any downloaded engine.
    static func speakingEngine(chosen: String?, downloaded: Set<String>,
                               memoryBytes: UInt64 = ProcessInfo.processInfo.physicalMemory) -> VoiceModel? {
        if let chosen = named(chosen), chosen.speaks, downloaded.contains(chosen.id) { return chosen }
        let available = engines.filter { downloaded.contains($0.id) }
        return available.first { $0.fits(memoryBytes: memoryBytes) } ?? available.first
    }
}

/// Where voices from recordings keep their files: Application Support/MacSpaces/Voices, outside
/// iCloud. `Models` holds the downloads (a Hugging Face cache), `People` the tagged voices and
/// `Sorting` the last drop's people until they're tagged or cleared. Debug harnesses get a
/// temporary folder of their own.
enum VoicePaths {
    static var root: URL {
        let base = Bundle.main.bundleIdentifier == "dev.opensource.MacSpaces"
            ? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            : FileManager.default.temporaryDirectory.appendingPathComponent("MacSpacesFixtures/" + (Bundle.main.bundleIdentifier ?? "tests"))
        return base.appendingPathComponent("MacSpaces/Voices", isDirectory: true)
    }

    static func models(in root: URL = root) -> URL { root.appendingPathComponent("Models", isDirectory: true) }
    static func people(in root: URL = root) -> URL { root.appendingPathComponent("People", isDirectory: true) }
    static func sorting(in root: URL = root) -> URL { root.appendingPathComponent("Sorting", isDirectory: true) }
}

/// Whether each model's download is whole, and removing it. Downloads sit in a Hugging Face cache
/// (`hub`), each repository in `hub/mlx-audio/<owner_name>` as mlx-audio-swift lays them out, with
/// the Hub's own resumable parts beside it. Siren's `ModelStore`, checked without the network.
struct VoiceModelStore: Sendable {
    enum State: Equatable, Sendable {
        case notDownloaded
        /// A download that stopped part-way; downloading again resumes it.
        case partial(bytes: Int64)
        case downloaded(bytes: Int64)

        var isDownloaded: Bool { if case .downloaded = self { true } else { false } }
    }

    /// The Hugging Face cache.
    let hub: URL

    init(hub: URL = VoicePaths.models()) { self.hub = hub }

    var root: URL { hub.appendingPathComponent("mlx-audio", isDirectory: true) }

    func folder(for part: String) -> URL {
        root.appendingPathComponent(part.replacingOccurrences(of: "/", with: "_"), isDirectory: true)
    }

    /// Everything a download of `part` leaves: its folder, the Hub's folder, and the Hub's lock
    /// files and listing for it.
    func folders(for part: String) -> [URL] {
        let name = "models--" + part.replacingOccurrences(of: "/", with: "--")
        return [folder(for: part), hub.appendingPathComponent(name, isDirectory: true),
                hub.appendingPathComponent(".locks/" + name, isDirectory: true),
                hub.appendingPathComponent(".metadata/" + name, isDirectory: true)]
    }

    /// Downloaded once every needed part is whole (its extras may still be missing: `lacksExtras`).
    func state(of model: VoiceModel) -> State {
        let bytes = model.allParts.reduce(Int64(0)) { total, part in total + folders(for: part).reduce(Int64(0)) { $0 + Self.size(of: $1) } }
        if model.parts.allSatisfy(isWhole) { return .downloaded(bytes: bytes) }
        return bytes > 0 ? .partial(bytes: bytes) : .notDownloaded
    }

    /// A downloaded model without one of its extras (downloaded before they were added).
    func lacksExtras(_ model: VoiceModel) -> Bool {
        state(of: model).isDownloaded && !model.extras.allSatisfy(isWhole)
    }

    func downloaded() -> Set<String> {
        Set(VoiceModel.catalogue.filter { state(of: $0).isDownloaded }.map(\.id))
    }

    /// Whole by MacSpaces' marker, written only after a download finished.
    func isWhole(_ part: String) -> Bool { Self.isComplete(folder(for: part)) }

    /// Records that every part is whole; call only after its download finished.
    func markWhole(_ model: VoiceModel) throws {
        for part in model.parts where !isWhole(part) { try Self.markComplete(folder(for: part)) }
    }

    /// Deletes the model's download, except parts another downloaded model still uses. Returns
    /// the bytes freed.
    @discardableResult
    func remove(_ model: VoiceModel) throws -> Int64 {
        let shared = Set(VoiceModel.catalogue.filter { $0 != model && state(of: $0) != .notDownloaded }.flatMap(\.allParts))
        var freed: Int64 = 0
        for part in model.allParts where !shared.contains(part) {
            for folder in folders(for: part) where FileManager.default.fileExists(atPath: folder.path) {
                freed += Self.size(of: folder)
                try FileManager.default.removeItem(at: folder)
            }
        }
        return freed
    }

    // MARK: Completion markers (Siren's `ModelCache`)

    static let markerName = ".macspaces-complete.json"

    private struct Entry: Codable, Equatable {
        let path: String
        let size: Int64
    }

    /// Every file recorded at its size, so a complete cache loads offline and a download that
    /// stopped part-way (no marker, or a file missing or short) is downloaded again.
    static func isComplete(_ folder: URL) -> Bool {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(markerName)),
              let entries = try? JSONDecoder().decode([Entry].self, from: data), !entries.isEmpty else { return false }
        return entries.allSatisfy { fileSize(folder.appendingPathComponent($0.path)) == $0.size }
    }

    static func markComplete(_ folder: URL) throws {
        let root = folder.standardizedFileURL.path
        var entries: [Entry] = []
        if let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey],
                                                       options: [.skipsHiddenFiles]) {
            for case let url as URL in walker {
                guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
                let path = url.standardizedFileURL.path
                guard path.hasPrefix(root + "/") else { continue }
                entries.append(Entry(path: String(path.dropFirst(root.count + 1)), size: fileSize(url) ?? 0))
            }
        }
        guard !entries.isEmpty else { throw CocoaError(.fileNoSuchFile) }
        try JSONEncoder().encode(entries.sorted { $0.path < $1.path })
            .write(to: folder.appendingPathComponent(markerName), options: .atomic)
    }

    private static func fileSize(_ url: URL) -> Int64? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value
    }

    /// Every file's size, hidden staging files included (resumable downloads still take space).
    static func size(of folder: URL) -> Int64 {
        guard let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in walker {
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true else { continue }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }
}
