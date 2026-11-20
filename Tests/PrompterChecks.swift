import Foundation

@main
enum PrompterChecks {
    static func main() {
        let script = ScriptAligner.words("""
        Good morning, everyone. Thanks for joining the launch review.
        Today we'll walk through what shipped, what's next, and what we learned.
        First, what shipped: the new onboarding flow went live on Tuesday.
        """)
        precondition(script.first == "good" && script.contains("well") && script.contains("whats"), "words are normalised")
        // Following along from the start.
        let afterThanks = ScriptAligner.position(script: script, heard: ["good", "morning", "everyone", "thanks", "for"], from: 0)
        precondition(afterThanks == 5, "position after 'for' (got \(String(describing: afterThanks)))")
        // A recognition slip (one letter) still matches.
        let slip = ScriptAligner.position(script: script, heard: ["joining", "the", "lunch", "review"], from: 5)
        precondition(slip == 9, "fuzzy word match (got \(String(describing: slip)))")
        // Never jumps back to an earlier repeat of "what".
        let later = ScriptAligner.position(script: script, heard: ["what", "shipped"], from: 22)
        let laterIndex = script.indices.filter { script[$0] == "shipped" }.last! + 1
        precondition(later == laterIndex, "forward-only match (got \(String(describing: later)), wanted \(laterIndex))")
        // Unrelated speech or a lone short word doesn't move the script.
        precondition(ScriptAligner.position(script: script, heard: ["banana", "submarine", "orchestra"], from: 3) == nil)
        precondition(ScriptAligner.position(script: script, heard: ["the"], from: 3) == nil)
        precondition(ScriptAligner.position(script: [], heard: ["hello"], from: 0) == nil)
        // Voice following runs only with on-device recognition (audit 2.75 #4).
        precondition(OnDeviceSpeech.decide(hasRecognizer: true, isAvailable: true, supportsOnDevice: true) == .listen)
        for (has, available, onDevice) in [(true, true, false), (false, false, false), (true, false, false), (true, false, true)] {
            precondition(OnDeviceSpeech.decide(hasRecognizer: has, isAvailable: available, supportsOnDevice: onDevice) != .listen,
                         "No server recognition: refuse unless on-device recognition is available")
        }

        // An unreadable scripts library is kept, never overwritten (#2).
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("prompter-check-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("scripts.json")
        let original = Data("MSE1 sealed with a key that is not available".utf8)
        try! original.write(to: url)
        var store = ProtectedFile(url: url)
        guard case .unreadable = store.load({ try JSONDecoder().decode([String].self, from: $0) }) else { preconditionFailure("must report unreadable") }
        precondition(!store.isWritable)
        precondition((try? store.write(Data("[\"Welcome\"]".utf8))) == nil && (try? store.remove()) == nil, "Writes and removals are refused")
        precondition(try! Data(contentsOf: url) == original, "The unreadable file is untouched")
        let aside = try! store.setAside()!
        precondition(try! Data(contentsOf: aside) == original && aside.lastPathComponent.hasPrefix("scripts-unreadable-"), "Reset keeps the original beside it")
        try! store.write(Data("[\"New\"]".utf8))
        guard case .loaded(let fresh) = store.load({ try JSONDecoder().decode([String].self, from: $0) }), fresh == ["New"] else { preconditionFailure() }
        var missing = ProtectedFile(url: folder.appendingPathComponent("none.json"))
        guard case .missing = missing.load({ $0 }), missing.isWritable else { preconditionFailure("A missing file may be created") }
        print("Prompter checks passed: word normalisation, following speech, fuzzy words, forward-only, noise rejection, on-device-only voice and protected script library")
    }
}
