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
        print("Prompter checks passed: word normalisation, following speech, fuzzy words, forward-only and noise rejection")
    }
}
